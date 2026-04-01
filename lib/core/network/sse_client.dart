import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// Lightweight SSE (Server-Sent Events) client using Dio streaming.
/// Used for AI chat streaming responses.
class SseClient {
  final Dio _dio;

  SseClient(this._dio);

  /// Sends a POST request and returns a stream of parsed SSE data events.
  Stream<String> postStream({
    required String path,
    required Map<String, dynamic> data,
    Duration timeout = const Duration(minutes: 2),
  }) async* {
    final response = await _dio.post<ResponseBody>(
      path,
      data: data,
      options: Options(
        responseType: ResponseType.stream,
        receiveTimeout: timeout,
        headers: {'Accept': 'text/event-stream'},
      ),
    );

    final stream = response.data?.stream;
    if (stream == null) return;

    String buffer = '';

    await for (final chunk in stream) {
      buffer += utf8.decode(chunk);

      // Process complete SSE lines
      while (buffer.contains('\n')) {
        final lineEnd = buffer.indexOf('\n');
        final line = buffer.substring(0, lineEnd).trim();
        buffer = buffer.substring(lineEnd + 1);

        if (line.startsWith('data: ')) {
          final data = line.substring(6);
          if (data == '[DONE]') return;
          yield data;
        }
      }
    }

    // Process any remaining data in buffer
    if (buffer.trim().startsWith('data: ')) {
      final data = buffer.trim().substring(6);
      if (data != '[DONE]') {
        yield data;
      }
    }
  }
}
