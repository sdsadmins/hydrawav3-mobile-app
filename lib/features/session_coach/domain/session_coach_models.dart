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

  /// The pad colours the admin picked for this muscle (`#RRGGBB`), or empty
  /// for the viewer's default Sun/Moon colours.
  final String sunColor;
  final String moonColor;

  const CoachMuscle({
    required this.muscleId,
    required this.muscleName,
    this.sun,
    this.moon,
    this.sunColor = '',
    this.moonColor = '',
  });

  factory CoachMuscle.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic>? marker(dynamic m) =>
        m is Map ? Map<String, dynamic>.from(m) : null;
    return CoachMuscle(
      muscleId: (j['muscleId'] ?? '').toString(),
      muscleName: (j['muscleName'] ?? '').toString(),
      sun: marker(j['sun']),
      moon: marker(j['moon']),
      sunColor: _hexColor(j['sunColor']),
      moonColor: _hexColor(j['moonColor']),
    );
  }
}

/// `#RRGGBB` (or `#RGB`) as sent, else empty — it goes into the viewer's
/// JavaScript, so nothing else is let through.
String _hexColor(dynamic raw) {
  final v = (raw ?? '').toString().trim();
  return RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').hasMatch(v) ? v : '';
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

  /// Every placed pad in this set, in the viewer's marker shape, with the
  /// muscle's pad colour as `color` when the admin picked one.
  List<Map<String, dynamic>> get markers => [
        for (final m in muscles) ...[
          if (m.sun != null)
            {...m.sun!, if (m.sunColor.isNotEmpty) 'color': m.sunColor},
          if (m.moon != null)
            {...m.moon!, if (m.moonColor.isNotEmpty) 'color': m.moonColor},
        ],
      ];

  /// The set's muscles, in order, for the viewer to light up.
  List<String> get muscleNames => [
        for (final m in muscles)
          if (m.muscleName.trim().isNotEmpty) m.muscleName,
      ];

  List<String> get sunMuscles =>
      [for (final m in muscles) if (m.sun != null) m.muscleName];
  List<String> get moonMuscles =>
      [for (final m in muscles) if (m.moon != null) m.muscleName];
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
        secondaryProtocols:
            (j['secondaryProtocolIds'] is List ? j['secondaryProtocolIds'] as List : const [])
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
      supportTypes: (j['supportTypes'] is List ? j['supportTypes'] as List : const [])
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
