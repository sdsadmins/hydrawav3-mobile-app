/// A pad-placement session plan for one body part (web parity:
/// `TreatmentPlanByBodyPartResponse` from `GET treatment-plans/body-part/:name`).
/// Each area carries the two electrode polarities (`sun` / `moon`) and the
/// recommended protocol.
class SessionPlan {
  final String bodyPartName;
  final String treatmentName;
  final List<PlacementArea> areas;

  const SessionPlan({
    this.bodyPartName = '',
    this.treatmentName = '',
    this.areas = const [],
  });

  factory SessionPlan.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] is Map)
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    final rawAreas = data['areas'];
    return SessionPlan(
      bodyPartName: (data['bodyPartName'] ?? '').toString(),
      treatmentName: (data['treatmentName'] ?? '').toString(),
      areas: rawAreas is List
          ? rawAreas
              .whereType<Map>()
              .map((e) => PlacementArea.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

class PlacementArea {
  /// The option/muscle heading (web: `opt.areaname`).
  final String? areaname;
  final PlacementPoint? sun;
  final PlacementPoint? moon;
  final String? description;
  final String? protocolName;
  final int protocolDuration;
  final String protocolDurationFormatted;

  const PlacementArea({
    this.areaname,
    this.sun,
    this.moon,
    this.description,
    this.protocolName,
    this.protocolDuration = 0,
    this.protocolDurationFormatted = '',
  });

  factory PlacementArea.fromJson(Map<String, dynamic> json) {
    return PlacementArea(
      areaname: json['areaname']?.toString() ?? json['areaName']?.toString(),
      sun: json['sun'] is Map
          ? PlacementPoint.fromJson(Map<String, dynamic>.from(json['sun']))
          : null,
      moon: json['moon'] is Map
          ? PlacementPoint.fromJson(Map<String, dynamic>.from(json['moon']))
          : null,
      description: json['description']?.toString(),
      protocolName: json['protocolName']?.toString(),
      protocolDuration: (json['protocolDuration'] as num?)?.toInt() ?? 0,
      protocolDurationFormatted:
          (json['protocolDurationFormatted'] ?? '').toString(),
    );
  }
}

/// One electrode placement point on a body diagram (coords kept for a future
/// visual overlay; the MVP renders them as a list).
class PlacementPoint {
  final String muscle;
  final double x;
  final double y;
  final String label;
  final String view; // 'front' | 'rear'
  final String? description;

  const PlacementPoint({
    this.muscle = '',
    this.x = 0,
    this.y = 0,
    this.label = '',
    this.view = '',
    this.description,
  });

  factory PlacementPoint.fromJson(Map<String, dynamic> json) {
    return PlacementPoint(
      muscle: (json['muscle'] ?? '').toString(),
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      label: (json['label'] ?? '').toString(),
      view: (json['view'] ?? '').toString(),
      description: json['description']?.toString(),
    );
  }
}
