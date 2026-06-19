import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/logger.dart';
import '../domain/music_model.dart';

final musicRemoteSourceProvider = Provider<MusicRemoteSource>((ref) {
  return MusicRemoteSource(ref.read(nodeDioProvider));
});

class MusicRemoteSource {
  final Dio _dio;

  MusicRemoteSource(this._dio);

  /// GET /musics — the list of session "Atmosphere" tracks (auth header is
  /// attached automatically by the Dio auth interceptor). Tolerates a bare
  /// JSON array or a `{ data: [...] }` envelope, mirroring the other sources.
  Future<List<Music>> getMusics() async {
    try {
      appLogger.i('Music: fetching tracks from /musics …');
      final response = await _dio.get(ApiEndpoints.musics);

      final data = response.data;
      final List<dynamic> items = data is List ? data : (data['data'] ?? []);

      return items
          .whereType<Map>()
          .map((e) => Music.fromJson(e.cast<String, dynamic>()))
          .where((m) => m.isPlayable)
          .toList();
    } on DioException catch (e) {
      // No tracks / no access is not an error worth crashing the picker over —
      // surface an empty list for those, throw for genuine failures.
      final code = e.response?.statusCode;
      if (code == 401 || code == 403 || code == 404 || code == 204) {
        appLogger.w('Music: /musics returned $code — treating as empty');
        return const <Music>[];
      }
      appLogger.e('Music: API error (status: $code)');
      final msg = (e.response?.data is Map
              ? e.response?.data['message']?.toString()
              : null) ??
          'Failed to fetch music';
      throw ServerException(msg, statusCode: code);
    } catch (e) {
      appLogger.e('Music: parse error: $e');
      rethrow;
    }
  }
}
