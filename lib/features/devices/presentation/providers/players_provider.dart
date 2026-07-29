import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/network/dio_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

// The university roster (players) is backed by the Clients API — a player is a
// client with `memberType: "Player"` (see the clients feature). This file only
// provides the org's sports (+ positions) used by the Add Player form.

// ── Org sports (backend) ─────────────────────────────────────────────────────

/// A position within a sport — its ObjectId (sent when creating a player) + a
/// display name.
class Position {
  final String id;
  final String name;
  const Position({required this.id, required this.name});
}

/// One sport mapped to the org, with its positions — compatible with both the
/// older object response and the newer plain-string list returned by
/// `GET /sports/:organisationId`.
class OrgSport {
  final String mappingId;
  final String sportId;
  final String name;
  final List<Position> positions;
  final bool isActive;

  const OrgSport({
    required this.mappingId,
    required this.sportId,
    required this.name,
    required this.positions,
    required this.isActive,
  });

  static String _s(dynamic v) => v?.toString() ?? '';

  factory OrgSport.fromName(String name) {
    return OrgSport(
      mappingId: name,
      sportId: name,
      name: name,
      positions: const [],
      isActive: true,
    );
  }

  factory OrgSport.fromJson(Map<String, dynamic> json) {
    final sport = json['sport'];
    final sm = sport is Map ? sport : const <dynamic, dynamic>{};

    final positions = <Position>[];
    final raw = json['positions'];
    if (raw is List) {
      for (final p in raw) {
        if (p is Map) {
          final id = _s(p['_id'] ?? p['id']);
          final name = _s(p['name'] ??
              p['positionName'] ??
              p['position'] ??
              p['title']);
          if (name.isNotEmpty || id.isNotEmpty) {
            positions.add(Position(id: id, name: name.isEmpty ? id : name));
          }
        } else {
          // A bare ObjectId string with no name.
          final id = _s(p);
          if (id.isNotEmpty) positions.add(Position(id: id, name: id));
        }
      }
    }

    final ia = json['isActive'];
    final active = ia is bool
        ? ia
        : ia is num
            ? ia != 0
            : ia is String
                ? ia.toLowerCase() == 'true'
                : true;

    return OrgSport(
      mappingId: _s(json['mappingId'] ?? json['_id']),
      sportId: _s(sm['_id'] ?? sm['id']),
      name: _s(sm['name'] ?? sm['sportName'] ?? sm['title']),
      positions: positions,
      isActive: active,
    );
  }
}

/// The org's active sports (+ positions) for the Add Player form. Calls the
/// Node `GET /sports/:organisationId` for the selected organization.
final orgSportsProvider =
    FutureProvider.autoDispose<List<OrgSport>>((ref) async {
  final auth = ref.watch(authStateProvider);
  final orgId = auth.selectedOrgId ?? auth.user?.organizationId;
  if (orgId == null || orgId.isEmpty) return const [];

  final dio = ref.read(nodeDioProvider);
  final res = await dio.get(ApiEndpoints.orgSports(orgId));
  final body = res.data;
  final list = (body is Map ? body['data'] : body);
  if (list is! List) return const [];

  return list
      .map((item) {
        if (item is String) return OrgSport.fromName(item);
        if (item is Map) {
          return OrgSport.fromJson(Map<String, dynamic>.from(item));
        }
        return null;
      })
      .whereType<OrgSport>()
      .where((s) => s.isActive && s.name.isNotEmpty)
      .toList();
});
