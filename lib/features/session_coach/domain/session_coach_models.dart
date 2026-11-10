/// Session Coach — what the Node `session-coach` module returns (admin builds
/// it on the website: Usage protocols → Session coach → Add). One coach per
/// body part: per support type, a default protocol (+ secondaries) and 1–3
/// sets of muscles, each with a Sun and/or Moon pad placed on the Z-Anatomy
/// body.
///
/// The pad markers are kept as the raw maps the server sent: they go straight
/// back into the same Z-Anatomy viewer that placed them, so nothing here
/// reinterprets a position.
library;

const kSupportActivation = 'Support activation';
const kSupportRecovery = 'Support recovery';
const kDefaultCoachMuscleColor = '#EF4444';
const kDefaultCoachSunColor = '#FBBF24';
const kDefaultCoachMoonColor = '#818CF8';

String _referenceId(dynamic value) {
  if (value is Map) return (value['_id'] ?? value['id'] ?? '').toString();
  return (value ?? '').toString();
}

String _referenceName(dynamic value, dynamic fallback) {
  if (value is Map) {
    final name = (value['partName'] ?? value['name'] ?? '').toString();
    if (name.isNotEmpty) return name;
  }
  return (fallback ?? '').toString();
}

/// A body part from `GET /body-part` (id + name; the coach is looked up by id).
class CoachBodyPart {
  final String id;
  final String name;
  const CoachBodyPart({required this.id, required this.name});
}

/// A protocol reference as the coach returns it (populated `template_name`).
class CoachProtocolRef {
  final String id;
  final String name;
  const CoachProtocolRef({required this.id, required this.name});

  static CoachProtocolRef? fromRef(dynamic raw) {
    if (raw is String && raw.isNotEmpty) {
      return CoachProtocolRef(id: raw, name: '');
    }
    if (raw is Map) {
      final id = (raw['_id'] ?? raw['id'] ?? '').toString();
      if (id.isEmpty) return null;
      return CoachProtocolRef(
        id: id,
        name: (raw['template_name'] ?? raw['templateName'] ?? '').toString(),
      );
    }
    return null;
  }
}

class CoachMuscle {
  final String muscleId;
  final String muscleName;
  final Map<String, dynamic>? sun;
  final Map<String, dynamic>? moon;

  /// The admin-selected 3D muscle highlight and Sun/Moon pad colours.
  final String muscleColor;
  final String sunColor;
  final String moonColor;

  const CoachMuscle({
    required this.muscleId,
    required this.muscleName,
    this.sun,
    this.moon,
    this.muscleColor = kDefaultCoachMuscleColor,
    this.sunColor = kDefaultCoachSunColor,
    this.moonColor = kDefaultCoachMoonColor,
  });

  factory CoachMuscle.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic>? marker(dynamic m) =>
        m is Map ? Map<String, dynamic>.from(m) : null;
    return CoachMuscle(
      muscleId: (j['muscleId'] ?? '').toString(),
      muscleName: (j['muscleName'] ?? '').toString(),
      sun: marker(j['sun']),
      moon: marker(j['moon']),
      muscleColor: _hexColor(
        j['muscleColor'],
        fallback: kDefaultCoachMuscleColor,
      ),
      sunColor: _hexColor(j['sunColor'], fallback: kDefaultCoachSunColor),
      moonColor: _hexColor(j['moonColor'], fallback: kDefaultCoachMoonColor),
    );
  }
}

/// `#RRGGBB` (or `#RGB`) as sent, else a safe viewer-compatible default.
String _hexColor(dynamic raw, {required String fallback}) {
  final v = (raw ?? '').toString().trim();
  return RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').hasMatch(v)
      ? v
      : fallback;
}

/// The Session Coach selection attached to an intake record.
class SessionCoachRun {
  final String sessionCoachId;
  final String bodyPartId;
  final String bodyPartName;
  final String supportType;
  final List<SessionCoachRunSet> sets;

  const SessionCoachRun({
    required this.sessionCoachId,
    required this.bodyPartId,
    required this.bodyPartName,
    required this.supportType,
    required this.sets,
  });

  bool get isValid =>
      sessionCoachId.isNotEmpty &&
      bodyPartId.isNotEmpty &&
      bodyPartName.isNotEmpty &&
      supportType.isNotEmpty &&
      sets.isNotEmpty &&
      sets.every((set) =>
          set.setId.isNotEmpty &&
          set.name.isNotEmpty &&
          set.protocolId.isNotEmpty &&
          set.protocolName.isNotEmpty &&
          set.macAddress.isNotEmpty);

  SessionCoachRun copyWith({List<SessionCoachRunSet>? sets}) => SessionCoachRun(
        sessionCoachId: sessionCoachId,
        bodyPartId: bodyPartId,
        bodyPartName: bodyPartName,
        supportType: supportType,
        sets: sets ?? this.sets,
      );

  Map<String, dynamic> toJson() => {
        'sessionCoachId': sessionCoachId,
        'bodyPartId': bodyPartId,
        'bodyPartName': bodyPartName,
        'supportType': supportType,
        'sets': [for (final set in sets) set.toJson()],
      };

  factory SessionCoachRun.fromJson(Map<String, dynamic> json) =>
      SessionCoachRun(
        sessionCoachId: (json['sessionCoachId'] ?? '').toString(),
        bodyPartId: _referenceId(json['bodyPartId']),
        bodyPartName:
            _referenceName(json['bodyPartId'], json['bodyPartName']),
        supportType: (json['supportType'] ?? '').toString(),
        sets: (json['sets'] is List ? json['sets'] as List : const [])
            .whereType<Map>()
            .map((set) =>
                SessionCoachRunSet.fromJson(Map<String, dynamic>.from(set)))
            .toList(),
      );
}

class SessionCoachRunSet {
  final int index;
  final String setId;
  final String name;
  final String protocolId;
  final String protocolName;
  final String macAddress;
  final int? startDelay;

  const SessionCoachRunSet({
    required this.index,
    required this.setId,
    required this.name,
    required this.protocolId,
    required this.protocolName,
    required this.macAddress,
    this.startDelay,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'setId': setId,
        'name': name,
        'protocolId': protocolId,
        'protocolName': protocolName,
        'macAddress': macAddress,
        if (startDelay != null) 'startDelay': startDelay,
      };

  factory SessionCoachRunSet.fromJson(Map<String, dynamic> json) =>
      SessionCoachRunSet(
        index: (json['index'] as num?)?.toInt() ?? 0,
        setId: (json['setId'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        protocolId: (json['protocolId'] ?? '').toString(),
        protocolName: (json['protocolName'] ?? '').toString(),
        macAddress: (json['macAddress'] ?? '').toString(),
        startDelay: (json['startDelay'] as num?)?.toInt(),
      );
}

class CoachSet {
  final String id;
  final String name;
  final List<CoachMuscle> muscles;

  const CoachSet({required this.id, required this.name, required this.muscles});

  factory CoachSet.fromJson(Map<String, dynamic> j) => CoachSet(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        muscles: (j['muscles'] is List ? j['muscles'] as List : const [])
            .whereType<Map>()
            .map((m) => CoachMuscle.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
      );

  List<Map<String, String>> get muscleHighlights => [
        for (final m in muscles)
          if (m.muscleName.trim().isNotEmpty)
            {'name': m.muscleName, 'color': m.muscleColor},
      ];

  List<CoachPadLabel> get padLabels => [
        for (final m in muscles) ...[
          if (m.sun != null)
            CoachPadLabel(type: 'sun', muscleName: m.muscleName, color: m.sunColor),
          if (m.moon != null)
            CoachPadLabel(type: 'moon', muscleName: m.muscleName, color: m.moonColor),
        ],
      ];

  /// Every placed pad in this set, with the admin-selected color attached.
  List<Map<String, dynamic>> get markers => [
        for (final m in muscles) ...[
          if (m.sun != null)
            {...m.sun!, 'color': m.sunColor},
          if (m.moon != null)
            {...m.moon!, 'color': m.moonColor},
        ],
      ];

  /// The set's muscles, in order, for the viewer to light up.
  List<String> get muscleNames => [
        for (final m in muscles)
          if (m.muscleName.trim().isNotEmpty) m.muscleName,
      ];

  List<String> get sunMuscles => [
        for (final m in muscles)
          if (m.sun != null) m.muscleName
      ];
  List<String> get moonMuscles => [
        for (final m in muscles)
          if (m.moon != null) m.muscleName
      ];
}

class CoachPadLabel {
      final String type;
      final String muscleName;
      final String color;

      const CoachPadLabel({
        required this.type,
        required this.muscleName,
        required this.color,
      });
}

/// A support type's protocols: `protocols[type]` on the coach.
class CoachProtocolChoice {
  final CoachProtocolRef? defaultProtocol;
  final List<CoachProtocolRef> secondaryProtocols;

  const CoachProtocolChoice({
    this.defaultProtocol,
    this.secondaryProtocols = const [],
  });

  factory CoachProtocolChoice.fromJson(Map j) => CoachProtocolChoice(
        defaultProtocol: CoachProtocolRef.fromRef(j['defaultProtocolId']),
        secondaryProtocols: (j['secondaryProtocolIds'] is List
                ? j['secondaryProtocolIds'] as List
                : const [])
            .map(CoachProtocolRef.fromRef)
            .whereType<CoachProtocolRef>()
            .toList(),
      );

  /// Default first, then the secondaries (de-duplicated, server order).
  List<CoachProtocolRef> get all {
    final out = <CoachProtocolRef>[];
    for (final p in [
      if (defaultProtocol != null) defaultProtocol!,
      ...secondaryProtocols,
    ]) {
      if (!out.any((x) => x.id == p.id)) out.add(p);
    }
    return out;
  }
}

class SessionCoach {
  final String id;
  final String bodyPartName;

  /// Coach-wide protocols: the older shape, with `defaultProtocolId` /
  /// `secondaryProtocolIds` at the top level. Used for a support type that
  /// has no entry in [protocolsByType].
  final CoachProtocolChoice protocolsAll;

  /// Support type → its protocols (`protocols` on the coach).
  final Map<String, CoachProtocolChoice> protocolsByType;
  final List<String> supportTypes;
  final Map<String, List<CoachSet>> sets;
  final DateTime? updatedAt;

  const SessionCoach({
    required this.id,
    required this.bodyPartName,
    this.protocolsAll = const CoachProtocolChoice(),
    this.protocolsByType = const {},
    required this.supportTypes,
    required this.sets,
    this.updatedAt,
  });

  factory SessionCoach.fromJson(Map<String, dynamic> j) {
    final rawSets = j['sets'] is Map ? j['sets'] as Map : const {};
    final bodyPart = j['bodyPartId'];
    final byType = j['protocols'] is Map ? j['protocols'] as Map : const {};
    return SessionCoach(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      bodyPartName:
          bodyPart is Map ? (bodyPart['partName'] ?? '').toString() : '',
      protocolsAll: CoachProtocolChoice.fromJson(j),
      protocolsByType: {
        for (final e in byType.entries)
          if (e.value is Map)
            e.key.toString(): CoachProtocolChoice.fromJson(e.value as Map),
      },
      supportTypes:
          (j['supportTypes'] is List ? j['supportTypes'] as List : const [])
              .map((e) => e.toString())
              .toList(),
      sets: {
        for (final e in rawSets.entries)
          e.key.toString(): (e.value is List ? e.value as List : const [])
              .whereType<Map>()
              .map((s) => CoachSet.fromJson(Map<String, dynamic>.from(s)))
              .toList(),
      },
      updatedAt: DateTime.tryParse((j['updatedAt'] ?? '').toString()),
    );
  }

  /// Sets for one support type (empty when the type isn't enabled).
  List<CoachSet> setsFor(String supportType) =>
      supportTypes.contains(supportType)
          ? (sets[supportType] ?? const [])
          : const [];

  CoachProtocolChoice _choiceFor(String? supportType) {
    final own = protocolsByType[supportType];
    return own != null && own.all.isNotEmpty ? own : protocolsAll;
  }

  /// The support type's default protocol.
  CoachProtocolRef? defaultProtocolFor(String? supportType) =>
      _choiceFor(supportType).defaultProtocol;

  /// The support type's protocols: default first, then the secondaries
  /// (de-duplicated, server order).
  List<CoachProtocolRef> protocolsFor(String? supportType) =>
      _choiceFor(supportType).all;
}
