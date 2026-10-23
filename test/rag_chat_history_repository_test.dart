import 'package:flutter_test/flutter_test.dart';
import 'package:hydrawav3/core/constants/api_endpoints.dart';
import 'package:hydrawav3/features/assistant/data/rag_chat_history_repository.dart';

import 'helpers/fake_http.dart';

void main() {
  const placement = {'display_name': 'Hamstring chain', 'sets': []};

  test('sends the placement as `placements`', () async {
    final server = FakeHttp()
      ..onJson(
          'POST', ApiEndpoints.ragChatHistory, {'conversationId': 'conv-1'},
          status: 201);
    final repo = RagChatHistoryRepository(server.dio());
    final id = await repo.addMessage(
        isGuest: true, isUser: false, message: 'Pads', placement: placement);
    expect(id, 'conv-1');
    final body = server.requests.single.json;
    expect(body['placements'], placement);
    expect(body.containsKey('placement'), isFalse);
  });

  test('a server that rejects `placements` still gets the message', () async {
    // what the current backend does: unknown property → 400
    final server = FakeHttp()
      ..on(
        'POST',
        ApiEndpoints.ragChatHistory,
        (req) => req.json.containsKey('placements')
            ? FakeReply.json(400, {
                'message': ['property placements should not exist']
              })
            : FakeReply.json(201, {'conversationId': 'conv-2'}),
      );
    final repo = RagChatHistoryRepository(server.dio());
    final id = await repo.addMessage(
        isGuest: true, isUser: false, message: 'Pads', placement: placement);
    expect(id, 'conv-2');
    expect(server.requests, hasLength(2));
    expect(server.requests.every((r) => r.method == 'POST'), isTrue);
    expect(server.requests.last.json.containsKey('placements'), isFalse);
    expect(server.requests.last.json['message'], 'Pads');
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

  test('lists a client\'s conversations, dropping rows with no id', () async {
    final server = FakeHttp()
      ..onJson('GET', ApiEndpoints.ragChatConversations, {
        'conversations': [
          {
            'conversationId': 'conv-9',
            'lastMessage': 'knee',
            'messageCount': 2
          },
          {'lastMessage': 'orphan'},
        ],
      });
    final repo = RagChatHistoryRepository(server.dio());

    final list = await repo.conversations('c1');

    expect(list.map((c) => c.conversationId), ['conv-9']);
    final req = server.requestsTo(ApiEndpoints.ragChatConversations).single;
    expect(req.method, 'GET');
    expect(req.query, {'clientId': 'c1', 'page': '1', 'limit': '50'});
  });

  test('an unrouted request gets the 404 fallback and is still recorded',
      () async {
    final server = FakeHttp();
    final repo = RagChatHistoryRepository(server.dio());
    await expectLater(repo.conversation('nope'), throwsA(anything));
    expect(server.requests.single.path, endsWith('nope'));
  });
}
