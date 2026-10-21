import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/assistant/data/rag_chat_history_repository.dart';
import 'package:hydrawav3/features/assistant/presentation/screens/assistant_history_screen.dart';
import 'package:hydrawav3/features/history/data/history_repository.dart';
import 'package:hydrawav3/features/history/domain/session_history_model.dart';

class _FakeRag implements RagChatHistoryRepository {
  @override
  Future<List<RagConversationSummary>> conversations(String? clientId,
          {int page = 1, int limit = 50}) async =>
      [
        RagConversationSummary(
          conversationId: 'conv-1',
          lastMessage: 'Pad placement: Hamstring chain',
          lastRole: 'assistant',
          lastAt: DateTime(2026, 10, 12, 9, 30),
          messageCount: 3,
        ),
      ];

  @override
  Future<List<RagMessage>> conversation(String conversationId) async => [
        const RagMessage(isUser: true, message: 'Football'),
        const RagMessage(
          isUser: false,
          message: 'Pad placement: Hamstring chain',
          placement: {
            'discipline': 'football',
            'display_name': 'Hamstring chain',
            'sets': [],
          },
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final _sessions = [
  SessionHistoryItem(
    id: 's1',
    clientId: 'c1',
    clientType: 'client',
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
    protocols: const [
      HistoryProtocol(
        protocol: 'Total Recovery',
        duration: 840,
        deviceName: 'Unit 1',
        questionAnswers: [
          // "Yes" is good on one question and bad on the other
          HistoryQuestionAnswer(
              question: 'Did the session help?', answer: 'Yes', rank: 5),
          HistoryQuestionAnswer(
              question: 'Any soreness after?', answer: 'No', rank: 4),
        ],
      ),
    ],
    discomfortAreas: const [
      HistoryDiscomfort(
          bodyPart: 'knee',
          side: 'left',
          discomfortBefore: 6,
          discomfortAfter: 3),
    ],
  ),
  SessionHistoryItem(
    id: 's2',
    clientId: 'c1',
    clientType: 'client',
    createdAt: DateTime.now().subtract(const Duration(days: 9)),
    protocols: const [
      HistoryProtocol(
        protocol: 'Total Recovery',
        duration: 840,
        questionAnswers: [
          HistoryQuestionAnswer(
              question: 'Did the session help?', answer: 'No', rank: 2),
          HistoryQuestionAnswer(
              question: 'Any soreness after?', answer: 'Yes', rank: 1),
        ],
      ),
      HistoryProtocol(protocol: 'Performance Activation', duration: 540),
    ],
  ),
];

/// Assistant → clock: History with Protocols / Usage / Outcomes / Chat, and
/// a saved pad placement that reopens in 3D.
void main() {
  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        ragChatHistoryRepositoryProvider.overrideWithValue(_FakeRag()),
        clientHistoryProvider.overrideWith((ref, id) async => _sessions),
        allSessionsProvider.overrideWith((ref) async => _sessions),
      ],
      child: MaterialApp(
        // around the navigator, so shots include overlays (tooltips)
        builder: (context, child) => RepaintBoundary(child: child),
        home:
            const AssistantHistoryScreen(clientId: 'c1', name: 'Malik Carter'),
      ),
    ));
    for (var k = 0; k < 4; k++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> tab(WidgetTester tester, String name) async {
    await tester.tap(find.widgetWithText(Tab, name));
    for (var k = 0; k < 6; k++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    final dir = Platform.environment['SHOTS'];
    if (dir == null) return;
    final ro = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first);
    await tester.runAsync(() async {
      final img = await ro.toImage(pixelRatio: 1);
      final d = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$name.png').writeAsBytesSync(d!.buffer.asUint8List());
    });
  }

  for (final size in [const Size(390, 844), const Size(1024, 1366)]) {
    final tag = size.width > 600 ? 'tablet' : 'phone';

    testWidgets('four tabs from the client\'s sessions and chats ($tag)',
        (tester) async {
      final fonts = Platform.environment['ROBOTO_DIR'];
      if (fonts != null) {
        final l = FontLoader('Roboto');
        for (final f in ['regular', 'medium', 'bold', 'black']) {
          l.addFont(Future.value(ByteData.view(
              File('$fonts/roboto-$f.ttf').readAsBytesSync().buffer)));
        }
        await l.load();
        final i = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(
              File('$fonts/materialicons-regular.otf')
                  .readAsBytesSync()
                  .buffer)));
        await i.load();
      }
      await pump(tester, size);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Malik Carter'), findsOneWidget);

      // Protocols: summary, then cards most-run first
      expect(
          find.text('2 protocols · 3 runs · 37 min in total',
              findRichText: true),
          findsOneWidget);
      expect(find.text('Total Recovery'), findsOneWidget);
      expect(find.text('Most used'), findsOneWidget);
      expect(find.text('28 min'), findsOneWidget); // total time
      expect(find.text('14 min'), findsOneWidget); // avg per run
      expect(find.text('50%'), findsOneWidget); // 1 of 2 checked runs helped
      expect(find.text('Performance Activation'), findsOneWidget);
      // just the last run — no per-run list
      // the sample's latest run is 2 days ago
      final d = DateTime.now().subtract(const Duration(days: 2));
      const mo = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      expect(
          find.text('Last run ${mo[d.month - 1]} ${d.day}, ${d.year} · Unit 1'),
          findsOneWidget);
      expect(find.textContaining('Last run'), findsNWidgets(2));
      expect(find.byIcon(Icons.cancel_rounded), findsNothing);
      await shot(tester, 'hist_protocols_$tag');

      await tab(tester, 'Usage');
      expect(find.text('Sessions'), findsOneWidget);
      expect(find.text('2'), findsWidgets);
      expect(find.text('37 min'), findsOneWidget); // 840+840+540 s
      // weekly chart: this week vs last, real week labels, no average
      expect(find.text('Last 8 weeks'), findsOneWidget);
      expect(find.text('Now'), findsOneWidget);
      expect(find.text('avg / week'), findsNothing);
      // tap this week's bar → its Monday–Sunday range and count
      final now = DateTime.now();
      final mon = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      final sun = mon.add(const Duration(days: 6));
      const m = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      final week = mon.year == sun.year
          ? '${m[mon.month - 1]} ${mon.day} – ${m[sun.month - 1]} ${sun.day}, ${sun.year}'
          : '${m[mon.month - 1]} ${mon.day}, ${mon.year} – '
              '${m[sun.month - 1]} ${sun.day}, ${sun.year}';
      await tester.tap(find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message ?? '').startsWith(week)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          find.text('$week · 1 session', findRichText: true), findsOneWidget);
      await shot(tester, 'hist_usage_tip_$tag');
      await tester.pump(const Duration(seconds: 4));
      await shot(tester, 'hist_usage_$tag');

      await tab(tester, 'Outcomes');
      // 2 of 4 check-ins helped; no discomfort section any more
      expect(find.text('2 of 4 check-ins said it helped'), findsOneWidget);
      expect(find.text('50%'), findsWidgets);
      expect(find.text('How sessions felt'.toUpperCase()), findsOneWidget);
      // answers grouped under their own question
      expect(find.text('Did the session help?'), findsOneWidget);
      expect(find.text('Any soreness after?'), findsOneWidget);
      expect(find.text('2 answers'), findsNWidgets(2));
      expect(find.text('By protocol'.toUpperCase()), findsOneWidget);
      expect(find.text('2 of 4 check-ins helped'), findsOneWidget);
      expect(find.text('Recent check-ins'.toUpperCase()), findsNothing);
      expect(find.textContaining('Discomfort'), findsNothing);
      expect(find.text('Left knee'), findsNothing);
      await shot(tester, 'hist_outcomes_$tag');

      await tab(tester, 'Chat');
      expect(find.text('Pad placement: Hamstring chain'), findsOneWidget);
      await tester.tap(find.text('Pad placement: Hamstring chain'));
      for (var k = 0; k < 6; k++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('Conversation'), findsOneWidget);
      expect(find.text('Hamstring chain'), findsOneWidget);
      expect(find.text('View in 3D'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('protocols show a skeleton while loading ($tag)',
        (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final never = Completer<List<SessionHistoryItem>>();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ragChatHistoryRepositoryProvider.overrideWithValue(_FakeRag()),
          clientHistoryProvider.overrideWith((ref, id) => never.future),
        ],
        child: MaterialApp(
          builder: (context, child) => RepaintBoundary(child: child),
          home: const AssistantHistoryScreen(
              clientId: 'c1', name: 'Malik Carter'),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await shot(tester, 'hist_protocols_loading_$tag');
      await tester.pumpWidget(const SizedBox());
    });
  }
}
