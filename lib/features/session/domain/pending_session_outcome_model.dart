import '../../intake/domain/intake_models.dart';
import '../../protocols/domain/protocol_model.dart';
import 'question_answer_model.dart';

/// A self-contained snapshot of a completed session, captured the moment it
/// goes terminal — BEFORE its live card is removed from the feed — so the
/// post-session outcomes sheet can be built and the `/intake` record finalized
/// later, without a live engine or a live card.
///
/// Persisted (SharedPreferences) by `pendingOutcomesProvider`. Stays queued as
/// "needs review" until the user submits or skips.
class PendingSessionOutcome {
  final String sessionId;
  final String protocolId;
  final String protocolName;
  final List<String> deviceIds;

  /// deviceId -> (protocol name, its duration seconds). Plus-aware: for a
  /// Protocol Plus device this may hold the Plus template name; the ordered
  /// sub-protocol names live in [protocolNamesByDeviceId].
  final Map<String, ({String name, int durationSeconds})> protocolByDeviceId;

  /// deviceId -> the ordered protocol names run on it (one for a normal
  /// device, the sub-protocol sequence for a Plus device). Drives which
  /// protocol sections show and how answers attach.
  final Map<String, List<String>> protocolNamesByDeviceId;

  /// protocol name -> its admin-defined questions (with preset answers).
  final Map<String, List<ProtocolQuestion>> questionsByProtocolName;

  final String clientType;
  final String? clientId;
  final int? discomfortBefore;
  final int totalDurationSeconds;
  final int elapsedSeconds;
  final DateTime createdAt;

  /// Guided Assessment intake captured for this session (null for Quick Start).
  /// Carried here so the single finalize POST includes ROM / activities / real
  /// discomfort areas, independent of any live engine.
  final GuidedAssessmentData? intake;

  /// Answers captured once the user submits. Null while still "needs review".
  final PostSessionOutcomes? answers;

  /// True when [answers] were captured but the `/intake` POST hasn't succeeded
  /// yet (retry via `drainSyncPending`).
  final bool syncPending;

  const PendingSessionOutcome({
    required this.sessionId,
    required this.protocolId,
    required this.protocolName,
    required this.deviceIds,
    this.protocolByDeviceId = const {},
    this.protocolNamesByDeviceId = const {},
    this.questionsByProtocolName = const {},
    this.clientType = 'guest',
    this.clientId,
    this.discomfortBefore,
    this.totalDurationSeconds = 0,
    this.elapsedSeconds = 0,
    required this.createdAt,
    this.intake,
    this.answers,
    this.syncPending = false,
  });

  PendingSessionOutcome copyWith({
    PostSessionOutcomes? answers,
    bool? syncPending,
  }) {
    return PendingSessionOutcome(
      sessionId: sessionId,
      protocolId: protocolId,
      protocolName: protocolName,
      deviceIds: deviceIds,
      protocolByDeviceId: protocolByDeviceId,
      protocolNamesByDeviceId: protocolNamesByDeviceId,
      questionsByProtocolName: questionsByProtocolName,
      clientType: clientType,
      clientId: clientId,
      discomfortBefore: discomfortBefore,
      totalDurationSeconds: totalDurationSeconds,
      elapsedSeconds: elapsedSeconds,
      createdAt: createdAt,
      intake: intake,
      answers: answers ?? this.answers,
      syncPending: syncPending ?? this.syncPending,
    );
  }

  /// Distinct protocols (ordered by first appearance across [deviceIds]) with
  /// their questions, dropping protocols that have no questions — exactly the
  /// list the outcomes sheet renders (web `sessionProtocolQuestions` parity).
  List<({String protocolName, List<ProtocolQuestion> questions})>
      get orderedProtocolQuestions {
    final seen = <String>{};
    final out = <({String protocolName, List<ProtocolQuestion> questions})>[];
    for (final deviceId in deviceIds) {
      final names = protocolNamesByDeviceId[deviceId] ??
          [protocolByDeviceId[deviceId]?.name ?? protocolName];
      for (final name in names) {
        if (name.isEmpty || !seen.add(name)) continue;
        final qs = questionsByProtocolName[name] ?? const <ProtocolQuestion>[];
        if (qs.isNotEmpty) out.add((protocolName: name, questions: qs));
      }
    }
    return out;
  }

  /// Whether there is anything to ask (protocol questions). The sheet still
  /// shows for pain/notes even when this is empty.
  bool get hasQuestions => orderedProtocolQuestions.isNotEmpty;

  /// The intake's areas of focus for the sheet's discomfort mapping —
  /// body part + pre-session pain (seeds the per-area post slider).
  List<({String bodyPart, int before})> get discomfortAreasForSheet =>
      (intake?.discomfortAreas ?? const [])
          .map((a) => (bodyPart: a.bodyPart, before: a.discomfortBefore))
          .toList();

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'protocolId': protocolId,
        'protocolName': protocolName,
        'deviceIds': deviceIds,
        'protocolByDeviceId': protocolByDeviceId.map(
          (k, v) => MapEntry(k, {'name': v.name, 'duration': v.durationSeconds}),
        ),
        'protocolNamesByDeviceId': protocolNamesByDeviceId,
        'questionsByProtocolName': questionsByProtocolName.map(
          (k, v) => MapEntry(k, v.map((q) => q.toJson()).toList()),
        ),
        'clientType': clientType,
        if (clientId != null) 'clientId': clientId,
        if (discomfortBefore != null) 'discomfortBefore': discomfortBefore,
        'totalDurationSeconds': totalDurationSeconds,
        'elapsedSeconds': elapsedSeconds,
        'createdAt': createdAt.toIso8601String(),
        if (intake != null) 'intake': intake!.toJson(),
        if (answers != null) 'answers': answers!.toJson(),
        'syncPending': syncPending,
      };

  factory PendingSessionOutcome.fromJson(Map<String, dynamic> json) {
    Map<String, List<String>> parseNames(dynamic raw) {
      final out = <String, List<String>>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is List) {
            out[k.toString()] = v.map((e) => e.toString()).toList();
          }
        });
      }
      return out;
    }

    Map<String, List<ProtocolQuestion>> parseQuestions(dynamic raw) {
      final out = <String, List<ProtocolQuestion>>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is List) {
            out[k.toString()] = v.map((e) {
              if (e is Map) {
                return ProtocolQuestion.fromJson(Map<String, dynamic>.from(e));
              }
              return ProtocolQuestion(text: e.toString());
            }).toList();
          }
        });
      }
      return out;
    }

    final byDevice = <String, ({String name, int durationSeconds})>{};
    final rawByDevice = json['protocolByDeviceId'];
    if (rawByDevice is Map) {
      rawByDevice.forEach((k, v) {
        if (v is Map) {
          byDevice[k.toString()] = (
            name: (v['name'] ?? '').toString(),
            durationSeconds: (v['duration'] as num?)?.toInt() ?? 0,
          );
        }
      });
    }

    return PendingSessionOutcome(
      sessionId: (json['sessionId'] ?? '').toString(),
      protocolId: (json['protocolId'] ?? '').toString(),
      protocolName: (json['protocolName'] ?? '').toString(),
      deviceIds: (json['deviceIds'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      protocolByDeviceId: byDevice,
      protocolNamesByDeviceId: parseNames(json['protocolNamesByDeviceId']),
      questionsByProtocolName: parseQuestions(json['questionsByProtocolName']),
      clientType: (json['clientType'] ?? 'guest').toString(),
      clientId: json['clientId']?.toString(),
      discomfortBefore: (json['discomfortBefore'] as num?)?.toInt(),
      totalDurationSeconds: (json['totalDurationSeconds'] as num?)?.toInt() ?? 0,
      elapsedSeconds: (json['elapsedSeconds'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      intake: json['intake'] is Map
          ? GuidedAssessmentData.fromJson(
              Map<String, dynamic>.from(json['intake'] as Map))
          : null,
      answers: json['answers'] is Map
          ? PostSessionOutcomes.fromJson(
              Map<String, dynamic>.from(json['answers'] as Map))
          : null,
      syncPending: json['syncPending'] as bool? ?? false,
    );
  }
}
