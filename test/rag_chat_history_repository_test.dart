import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrawav3/features/assistant/data/rag_chat_history_repository.dart';

/// Answers each POST with [reply] and records the bodies it was sent.
class _Server implements HttpClientAdapter {
  final ResponseBody Function(Map<String, dynamic> body) reply;
  final bodies = <Map<String, dynamic>>[];
  _Server(this.reply);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = Map<String, dynamic>.from(options.data as Map);
    bodies.add(body);
    return reply(body);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object data) => ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  const placement = {'display_name': 'Hamstring chain', 'sets': []};

  test('sends the placement as `placements`', () async {
    final server = _Server((_) => _json(201, {'conversationId': 'conv-1'}));
    final repo = RagChatHistoryRepository(Dio()..httpClientAdapter = server);
    final id = await repo.addMessage(
        isGuest: true, isUser: false, message: 'Pads', placement: placement);
    expect(id, 'conv-1');
    expect(server.bodies.single['placements'], placement);
    expect(server.bodies.single.containsKey('placement'), isFalse);
  });

  test('a server that rejects `placements` still gets the message', () async {
    // what the current backend does: unknown property → 400
    final server = _Server((b) => b.containsKey('placements')
        ? _json(400, {
            'message': ['property placements should not exist']
          })
        : _json(201, {'conversationId': 'conv-2'}));
    final repo = RagChatHistoryRepository(Dio()..httpClientAdapter = server);
    final id = await repo.addMessage(
        isGuest: true, isUser: false, message: 'Pads', placement: placement);
    expect(id, 'conv-2');
    expect(server.bodies.length, 2);
    expect(server.bodies.last.containsKey('placements'), isFalse);
    expect(server.bodies.last['message'], 'Pads');
  });

  test('reads `placements` back, and the older `placement` too', () {
    expect(
        RagMessage.fromJson(
                {'role': 'assistant', 'message': 'a', 'placements': placement})
            .placement,
        placement);
    expect(
        RagMessage.fromJson(
                {'role': 'assistant', 'message': 'a', 'placement': placement})
            .placement,
        placement);
  });
}
