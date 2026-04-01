import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/logger.dart';

final chatSseSourceProvider = Provider<ChatSseSource>((ref) {
  return ChatSseSource(ref.read(djangoDioProvider));
});

class ChatSseSource {
  final Dio _dio;

  ChatSseSource(this._dio);

  /// Stream chat response from /api/chat via SSE.
  Stream<String> streamChat({
    required List<Map<String, dynamic>> messages,
    String? analysisContext,
    String? pageContext,
    String provider = 'anthropic',
    String? model,
  }) async* {
    try {
      final response = await _dio.post<ResponseBody>(
        ApiEndpoints.aiChat,
        data: {
          'messages': messages,
          if (analysisContext != null) 'analysisContext': analysisContext,
          if (pageContext != null) 'pageContext': pageContext,
          'provider': provider,
          if (model != null) 'model': model,
        },
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: AppConstants.aiChatTimeout,
          headers: {'Accept': 'text/event-stream'},
        ),
      );

      final stream = response.data?.stream;
      if (stream == null) return;

      String buffer = '';

      await for (final chunk in stream) {
        buffer += utf8.decode(chunk);

        while (buffer.contains('\n')) {
          final lineEnd = buffer.indexOf('\n');
          final line = buffer.substring(0, lineEnd).trim();
          buffer = buffer.substring(lineEnd + 1);

          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data == '[DONE]') return;

            try {
              // Try parsing as JSON first (OpenAI format)
              final json = jsonDecode(data) as Map<String, dynamic>;
              final content = json['choices']?[0]?['delta']?['content'] ??
                  json['content'] ??
                  data;
              yield content.toString();
            } catch (_) {
              // Plain text chunk
              yield data;
            }
          }
        }
      }
    } catch (e) {
      appLogger.e('SSE Chat error: $e');
      rethrow;
    }
  }
}
