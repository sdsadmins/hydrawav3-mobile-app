import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/preferences.dart';
import '../domain/session_coach_models.dart';

/// One set of a saved coach plan: the protocol, the unit it ran on and its
/// start time (seconds from Start).
class CoachPlanSet {
  final int index;
  final String? setId;
  final String? name;
  final String? protocolId;
  final String? protocolName;
  final String? unitId;
  final int startAt;

  const CoachPlanSet({
    required this.index,
    this.setId,
    this.name,
    this.protocolId,
    this.protocolName,
    this.unitId,
    this.startAt = 0,
  });

  Map<String, dynamic> toJson() => {
        'i': index,
        if (setId != null) 'setId': setId,
        if (name != null) 'name': name,
        if (protocolId != null) 'protocolId': protocolId,
        if (protocolName != null) 'protocolName': protocolName,
        if (unitId != null) 'unitId': unitId,
        'at': startAt,
      };

  factory CoachPlanSet.fromJson(Map<String, dynamic> j) => CoachPlanSet(
        index: (j['i'] as num?)?.toInt() ?? 0,
        setId: j['setId'] as String?,
        name: j['name'] as String?,
        protocolId: j['protocolId'] as String?,
        protocolName: j['protocolName'] as String?,
        unitId: j['unitId'] as String?,
        startAt: (j['at'] as num?)?.toInt() ?? 0,
      );
}

/// What a client last ran from the Session Coach (prototype B0-coach
/// `saveClientPlan`): body part, goal, and per set the protocol, unit and
/// start delay. Read back by Game Prep's START.
class CoachPlanRecord {
  final String bodyPartId;
  final String bodyPartName;
  final String goal;
  final List<CoachPlanSet> sets;
  final DateTime savedAt;
  final SessionCoachRun? run;

  const CoachPlanRecord({
    required this.bodyPartId,
    required this.bodyPartName,
    required this.goal,
    required this.sets,
    required this.savedAt,
    this.run,
  });

  Map<String, dynamic> toJson() => {
        'bodyPartId': bodyPartId,
        'bodyPartName': bodyPartName,
        'goal': goal,
        'sets': [for (final s in sets) s.toJson()],
        'savedAt': savedAt.toIso8601String(),
        if (run != null) 'sessionCoach': run!.toJson(),
      };

  static CoachPlanRecord? fromRun(
    SessionCoachRun run, {
    DateTime? savedAt,
  }) {
    if (!run.isValid) return null;
    return CoachPlanRecord(
      bodyPartId: run.bodyPartId,
      bodyPartName: run.bodyPartName,
      goal: run.supportType,
      sets: [
        for (final set in run.sets)
          CoachPlanSet(
            index: set.index,
            setId: set.setId,
            name: set.name,
            protocolId: set.protocolId,
            protocolName: set.protocolName,
            unitId: set.macAddress,
            startAt: set.startDelay ?? 0,
          ),
      ],
      savedAt: savedAt ?? DateTime.now(),
      run: run,
    );
  }

  static CoachPlanRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final body = j['bodyPartId'] as String?;
    final goal = j['goal'] as String?;
    final sets = j['sets'];
    if (body == null || goal == null || sets is! List || sets.isEmpty) {
      return null;
    }
    return CoachPlanRecord(
      bodyPartId: body,
      bodyPartName: (j['bodyPartName'] as String?) ?? '',
      goal: goal,
      sets: [
        for (final s in sets)
          if (s is Map) CoachPlanSet.fromJson(Map<String, dynamic>.from(s)),
      ],
      savedAt: DateTime.tryParse(j['savedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      run: j['sessionCoach'] is Map
          ? SessionCoachRun.fromJson(
              Map<String, dynamic>.from(j['sessionCoach'] as Map))
          : null,
    );
  }
}

/// Local cache of each client's most recently applied coach plan, per
/// organization. Server intake history is the cross-device source of truth;
/// this cache keeps Game Prep useful offline and before a coached session is
/// finalized.
class CoachPlanStore {
  static const _key = 'coach_client_plans_v1';
  final SharedPreferences _prefs;
  CoachPlanStore(this._prefs);

  Map<String, dynamic> _all() {
    try {
      final raw = jsonDecode(_prefs.getString(_key) ?? '{}');
      return raw is Map ? Map<String, dynamic>.from(raw) : {};
    } catch (_) {
      return {};
    }
  }

  CoachPlanRecord? load(String orgId, String clientId) {
    final org = _all()[orgId];
    return org is Map ? CoachPlanRecord.fromJson(org[clientId]) : null;
  }

  Future<void> save(
      String orgId, String clientId, CoachPlanRecord record) async {
    final all = _all();
    final org = all[orgId] is Map
        ? Map<String, dynamic>.from(all[orgId] as Map)
        : <String, dynamic>{};
    org[clientId] = record.toJson();
    all[orgId] = org;
    await _prefs.setString(_key, jsonEncode(all));
  }
}

final coachPlanStoreProvider = Provider<CoachPlanStore>(
    (ref) => CoachPlanStore(ref.read(sharedPreferencesProvider)));

/// Session Coach details attached to the next session started from the device
/// screen. Cleared after launch so later normal sessions aren't mislabeled.
final sessionCoachRunProvider = StateProvider<SessionCoachRun?>((ref) => null);

/// Set by Game Prep's START: the client whose last plan the coach should
/// reopen at placement. The coach clears it once handled.
final coachRestoreRequestProvider = StateProvider<String?>((ref) => null);

/// Set when a saved history row asks Session Coach to reopen that exact plan.
final coachHistoryRestoreRequestProvider =
    StateProvider<CoachPlanRecord?>((ref) => null);
