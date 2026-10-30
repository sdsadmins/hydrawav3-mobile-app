import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/features/clients/domain/client_model.dart';
import 'package:hydrawav3/features/clients/presentation/providers/client_providers.dart';
import 'package:hydrawav3/features/devices/presentation/providers/players_provider.dart';
import 'package:hydrawav3/features/history/data/history_repository.dart';
import 'package:hydrawav3/features/history/domain/session_history_model.dart';
import 'package:hydrawav3/features/home/presentation/providers/hub_prefs_provider.dart';
import 'package:hydrawav3/features/home/presentation/providers/hub_stats_provider.dart';
import 'package:hydrawav3/features/home/presentation/widgets/hub_modules.dart';
import 'package:hydrawav3/features/protocols/presentation/providers/protocol_provider.dart';

SessionHistoryItem _s(String client, DateTime at, int rank,
        [String protocol = 'Performance Activation']) =>
    SessionHistoryItem(
      id: '$client-${at.millisecondsSinceEpoch}',
      clientId: client,
      clientType: 'client',
      createdAt: at,
      protocols: [
        HistoryProtocol(
          protocol: protocol,
          duration: 600,
          questionAnswers: [
            HistoryQuestionAnswer(question: 'q', answer: 'a', rank: rank),
          ],
        ),
      ],
    );

void main() {
  final now = DateTime.now();
  final today940 = DateTime(now.year, now.month, now.day, 9, 40);

  test('readiness = share of check-ins that helped, per day', () {
    final r = readinessOf([
      _s('m', today940, 5),
      _s('m', today940.subtract(const Duration(days: 1)), 2),
      _s('m', today940.subtract(const Duration(days: 1)), 4),
      _s('m', today940.subtract(const Duration(days: 40)), 1), // outside 14d
    ])!;
    expect(r.score, 67); // 2 of 3 in the window
    expect(r.trend, [50, 100]); // yesterday, today
    expect(readinessOf([]), isNull);
    expect(sessionHelped(_s('m', today940, 5)), isTrue);
    expect(sessionHelped(_s('m', today940, 2)), isFalse);
  });

  test('UTC createdAt from the server reads as local time', () {
    final item = SessionHistoryItem.fromJson({
      '_id': 'x',
      'createdAt': '2026-10-22T04:10:00.000Z',
      'protocols': [],
    });
    expect(item.createdAt!.isUtc, isFalse);
    expect(item.createdAt, DateTime.utc(2026, 10, 22, 4, 10).toLocal());
  });

  testWidgets('Athlete Focus: ring, last session and 14-day chart',
      (tester) async {
    final fonts = Platform.environment['ROBOTO_DIR'];
    if (fonts != null) {
      final l = FontLoader('Roboto');
      for (final f in ['regular', 'medium', 'bold', 'black']) {
        l.addFont(Future.value(ByteData.view(
            File('$fonts/roboto-$f.ttf').readAsBytesSync().buffer)));
      }
      await l.load();
    }
    tester.view.physicalSize = const Size(390, 1100) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const malik = Client(
        id: 'm',
        clientName: 'Malik Carter',
        memberType: 'Player',
        sport: 'Football',
        jerseyNumber: 8);
    final oneDay = Platform.environment['ONE_DAY'] != null;
    final sessions = [
      _s('m', today940, 5),
      if (!oneDay)
        for (var d = 1; d < 12; d++)
          _s('m', today940.subtract(Duration(days: d)), d.isEven ? 4 : 3),
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        allSessionsProvider.overrideWith((ref) async => sessions),
        clientListProvider.overrideWith((ref) async => const [malik]),
        protocolListProvider.overrideWith((ref) async => []),
        orgSportsProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp(
        builder: (c, child) => RepaintBoundary(child: child),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: HubModuleView(HubModule.gameprep, HubSize.large),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    // prepped players sit under the Prepped filter
    await tester.tap(find.textContaining('Prepped').first);
    for (var k = 0; k < 4; k++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    // the card's prepped time is local and short
    expect(find.text('PREPPED ✓ · 9:40'), findsOneWidget);
    {
      final dir = Platform.environment['SHOTS'];
      if (dir != null) {
        final ro = tester.renderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary).first);
        await tester.runAsync(() async {
          final img = await ro.toImage(pixelRatio: 1);
          final d = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$dir/prep_rail.png').writeAsBytesSync(d!.buffer.asUint8List());
        });
      }
    }

    await tester.tap(find.text('Malik'));
    for (var k = 0; k < 10; k++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('ATHLETE FOCUS'), findsOneWidget);
    expect(find.text('READINESS'), findsOneWidget);
    expect(find.text('LAST SESSION'), findsOneWidget);
    expect(find.text('Performance Activation · Football'), findsOneWidget);
    expect(find.text('Today · 9:40 · said it helped'), findsOneWidget);
    expect(find.text('READINESS · LAST 14 DAYS'), findsOneWidget);
    expect(
        find.textContaining(
            oneDay ? "Malik's first check-in" : "Malik's readiness"),
        findsOneWidget);
    expect(tester.takeException(), isNull);

    final dir = Platform.environment['SHOTS'];
    if (dir != null) {
      final ro = tester.renderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary).first);
      await tester.runAsync(() async {
        final img = await ro.toImage(pixelRatio: 1);
        final d = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$dir/athlete_focus${oneDay ? '_one' : ''}.png')
            .writeAsBytesSync(d!.buffer.asUint8List());
      });
    }
    await tester.pumpWidget(const SizedBox());
  });
}
