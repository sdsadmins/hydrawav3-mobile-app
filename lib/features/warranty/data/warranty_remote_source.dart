import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../domain/warranty_model.dart';

final warrantyRemoteSourceProvider = Provider<WarrantyRemoteSource>((ref) {
  return WarrantyRemoteSource(ref.read(nodeDioProvider));
});

/// Talks to `GET warranty/:orgId` — one record per registered sensor in the
/// organization, warranty-active or not.
class WarrantyRemoteSource {
  final Dio _dio;

  WarrantyRemoteSource(this._dio);

  Future<List<WarrantyRecord>> getWarranties(String orgId) async {
    final res = await _dio.get(ApiEndpoints.warrantyByOrg(orgId));
    final data = res.data;
    final list = data is List
        ? data
        : (data is Map && data['data'] is List)
            ? data['data'] as List
            : const [];
    return list
        .whereType<Map>()
        .map((e) => WarrantyRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
