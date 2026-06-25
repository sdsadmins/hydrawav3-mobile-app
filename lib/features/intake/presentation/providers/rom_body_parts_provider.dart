import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/network/dio_client.dart';

/// ROM "impacted body part" options for the Range of Motion step
/// (`GET roms` — parity with the web `getRoms`). Returns the body-part names.
final romBodyPartsProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final dio = ref.read(nodeDioProvider);
  try {
    final res = await dio.get(
      ApiEndpoints.roms,
      queryParameters: {'page': 1, 'perPage': 100},
    );
    final data = res.data;
    final list = data is Map && data['data'] is List
        ? data['data'] as List
        : data is List
            ? data
            : const [];
    return list
        .whereType<Map>()
        .map((e) => (e['bodyPart'] ?? '').toString())
        .where((s) => s.trim().isNotEmpty)
        .toList();
  } on DioException {
    return const [];
  }
});
