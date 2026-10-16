import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/features/assistant/data/rag_chat_history_repository.dart';
import 'package:hydrawav3/features/assistant/presentation/screens/assistant_history_screen.dart';
import 'package:hydrawav3/features/assistant/presentation/screens/assistant_screen.dart';
import 'package:hydrawav3/features/auth/domain/auth_models.dart';
import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';
import 'package:hydrawav3/features/clients/domain/client_model.dart';
import 'package:hydrawav3/features/clients/presentation/providers/client_providers.dart';
import 'package:hydrawav3/features/history/data/history_repository.dart';

class _FakeAuth extends StateNotifier<AuthState> implements AuthNotifier {
  _FakeAuth()
      : super(const AuthState(
          isAuthenticated: true,
          isInitialized: true,
          selectedOrgId: '1',
          user: UserProfile(id: '7', firstName: 'Marcus'),
        ));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRag implements RagChatHistoryRepository {
  final saved = <Map<String, Object?>>[];

  @override
  Future<String?> addMessage({
    required bool isGuest,
    String? clientId,
    String? conversationId,
    required bool isUser,
    required String message,
    List<String> sourceChunkIds = const [],
    Map<String, dynamic>? placement,
  }) async {
    saved.add({
      'placement': placement,
      'guest': isGuest,
      'clientId': clientId,
      'conv': conversationId,
      'user': isUser,
      'msg': message,
    });
    return conversationId ?? 'conv-1';
  }

  @override
  Future<List<RagConversationSummary>> conversations(String? clientId,
          {int page = 1, int limit = 50}) async =>
      [
        RagConversationSummary(
          conversationId: 'conv-9',
          lastMessage: clientId == null
              ? 'guest: tight hamstrings'
              : 'my knee hurts after running',
          lastRole: 'user',
          lastAt: DateTime(2026, 10, 1, 9, 30),
          messageCount: 4,
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_FakeRag> pump(WidgetTester tester,
      {ClientMode mode = ClientMode.guest, Client? selected}) async {
    final prefs = await SharedPreferences.getInstance();
    final rag = _FakeRag();
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authStateProvider.overrideWith((ref) => _FakeAuth()),
        ragChatHistoryRepositoryProvider.overrideWithValue(rag),
        clientListProvider.overrideWith((ref) async => const [
              Client(id: 'c1', clientName: 'Malik Carter'),
            ]),
        sessionClientModeProvider.overrideWith((ref) => mode),
        selectedClientProvider.overrideWith((ref) => selected),
        allSessionsProvider.overrideWith((ref) async => const []),
        clientHistoryProvider.overrideWith((ref, id) async => const []),
      ],
      child: MaterialApp(
        builder: (context, child) => RepaintBoundary(child: child),
        home: const AssistantScreen(intent: 'pads'),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    return rag;
  }

  testWidgets('opening alone saves nothing; the first tap saves the thread',
      (tester) async {
    final fonts = Platform.environment['ROBOTO_DIR'];
    if (fonts != null) {
      final l = FontLoader('Roboto');
      for (final f in ['regular', 'medium', 'bold', 'black']) {
        l.addFont(Future.value(ByteData.view(
            File('$fonts/roboto-$f.ttf').readAsBytesSync().buffer)));
      }
      await l.load();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.view(
                File('$fonts/materialicons-regular.otf')
                    .readAsBytesSync()
                    .buffer))))
          .load();
    }
    final rag = await pump(tester);
    expect(rag.saved, isEmpty);
    // header: the labelled History button
    expect(find.text('History'), findsOneWidget);
    final dir = Platform.environment['SHOTS'];
    if (dir != null) {
      final ro = tester.renderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary).first);
      await tester.runAsync(() async {
        final img = await ro.toImage(pixelRatio: 1);
        final d = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$dir/assistant_header.png')
            .writeAsBytesSync(d!.buffer.asUint8List());
      });
    }

    await tester.tap(find.text('Performance'));
    await tester.pump(const Duration(milliseconds: 900));

    expect(rag.saved.length, greaterThanOrEqualTo(3));
    // the waiting opening line, then the tap, then the AI's next question
    expect(rag.saved[0]['user'], false);
    expect(rag.saved[0]['msg'], contains('pad placement'));
    expect(rag.saved[1], containsPair('msg', 'Performance'));
    expect(rag.saved[1]['user'], true);
    expect(rag.saved[2]['msg'], contains('Who are we prepping'));
    // guest by default; one conversation id carried after the first save
    expect(rag.saved.every((m) => m['guest'] == true), isTrue);
    expect(rag.saved[0]['conv'], isNull);
    expect(rag.saved.skip(1).every((m) => m['conv'] == 'conv-1'), isTrue);
    // Guest mode: History opens on guest sessions, chats under the Chat tab
    await tester.tap(find.byIcon(Icons.history_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Guest sessions'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Chat'));
    for (var k = 0; k < 6; k++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('guest: tight hamstrings'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a selected client saves under them and shows past chats',
      (tester) async {
    const malik = Client(id: 'c1', clientName: 'Malik Carter');
    final rag = await pump(tester, mode: ClientMode.client, selected: malik);

    await tester.tap(find.text('Performance'));
    await tester.pump(const Duration(milliseconds: 900));
    expect(rag.saved.first['clientId'], 'c1');
    expect(rag.saved.first['guest'], false);

    await tester.tap(find.byIcon(Icons.history_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // the History screen's title (the header button also says History)
    expect(
        find.descendant(
            of: find.byType(AssistantHistoryScreen),
            matching: find.text('History')),
        findsOneWidget);
    expect(find.text('Malik Carter'), findsWidgets);
    await tester.tap(find.widgetWithText(Tab, 'Chat'));
    for (var k = 0; k < 6; k++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('my knee hurts after running'), findsOneWidget);
    expect(find.textContaining('4 messages'), findsOneWidget);
    // let the Performance flow's own delays run out
    await tester.pump(const Duration(seconds: 5));
  });
}
