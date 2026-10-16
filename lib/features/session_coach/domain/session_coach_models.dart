/// Session Coach — what the Node `session-coach` module returns (admin builds
/// it on the website: Usage protocols → Session coach → Add). One coach per
/// body part: a default protocol (+ secondaries) and, per support type, 1–3
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

  const CoachMuscle({
    required this.muscleId,
    required this.muscleName,
    this.sun,
    this.moon,
  });

  factory CoachMuscle.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic>? marker(dynamic m) =>
        m is Map ? Map<String, dynamic>.from(m) : null;
    return CoachMuscle(
      muscleId: (j['muscleId'] ?? '').toString(),
      muscleName: (j['muscleName'] ?? '').toString(),
      sun: marker(j['sun']),
      moon: marker(j['moon']),
    );
  }
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

  /// Every placed pad in this set, in the viewer's marker shape.
  List<Map<String, dynamic>> get markers => [
        for (final m in muscles) ...[
          if (m.sun != null) m.sun!,
          if (m.moon != null) m.moon!,
        ],
      ];

  List<String> get sunMuscles =>
      [for (final m in muscles) if (m.sun != null) m.muscleName];
  List<String> get moonMuscles =>
      [for (final m in muscles) if (m.moon != null) m.muscleName];
}

class SessionCoach {
  final String id;
  final String bodyPartName;
  final CoachProtocolRef? defaultProtocol;
  final List<CoachProtocolRef> secondaryProtocols;
  final List<String> supportTypes;
  final Map<String, List<CoachSet>> sets;
  final DateTime? updatedAt;

  const SessionCoach({
    required this.id,
    required this.bodyPartName,
    required this.defaultProtocol,
    required this.secondaryProtocols,
    required this.supportTypes,
    required this.sets,
    this.updatedAt,
  });

  factory SessionCoach.fromJson(Map<String, dynamic> j) {
    final rawSets = j['sets'] is Map ? j['sets'] as Map : const {};
    final bodyPart = j['bodyPartId'];
    return SessionCoach(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      bodyPartName:
          bodyPart is Map ? (bodyPart['partName'] ?? '').toString() : '',
      defaultProtocol: CoachProtocolRef.fromRef(j['defaultProtocolId']),
      secondaryProtocols:
          (j['secondaryProtocolIds'] is List ? j['secondaryProtocolIds'] as List : const [])
              .map(CoachProtocolRef.fromRef)
              .whereType<CoachProtocolRef>()
              .toList(),
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

  /// Default first, then the secondaries (de-duplicated, server order).
  List<CoachProtocolRef> get protocols {
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
