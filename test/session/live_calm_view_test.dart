import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrawav3/features/session/presentation/widgets/live_calm_view.dart';

/// Live screen "Simple" view (v6 `30-calm`): ring + time + stage + treatment
/// per unit, and "Hold to return" — a tap does nothing, a 0.9s hold exits.
void main() {
  const one = LiveCalmUnit(
    unit: 'Hydra-Mobile',
    remaining: Duration(minutes: 7, seconds: 42),
    progress: .38,
    stage: 'Energizing 3',
    treatment: 'BM4a. Forearm - Activation',
  );
  const two = LiveCalmUnit(
    unit: 'Unit 2',
    remaining: Duration(minutes: 3, seconds: 5),
    progress: .7,
    stage: 'Resting between protocols',
    treatment: 'Deep-Tension Recovery',
  );

  Future<void> pump(WidgetTester tester, List<LiveCalmUnit> units,
      {VoidCallback? onExit,
      Size size = const Size(390, 844),
      String? who}) async {
    final fonts = Platform.environment['ROBOTO_DIR'];
    if (fonts != null) {
      final l = FontLoader('Roboto');
      for (final f in ['regular', 'medium', 'bold', 'black']) {
        l.addFont(Future.value(ByteData.view(
            File('$fonts/roboto-$f.ttf').readAsBytesSync().buffer)));
      }
      await l.load();
    }
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (c, child) => RepaintBoundary(child: child),
      home: Scaffold(
        body: LiveCalmView(
            read: () => units, onExit: onExit ?? () {}, who: who),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
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

  testWidgets('one unit: big ring, time, stage, treatment', (tester) async {
    await pump(tester, const [one], who: 'Malik Carter');
    expect(find.text('HYDRAWAV3'), findsOneWidget);
    expect(find.text('Malik Carter'), findsOneWidget);
    expect(find.text('Session in progress'), findsOneWidget);
    expect(find.text('07:42'), findsOneWidget);
    expect(find.text('Energizing 3'), findsOneWidget);
    expect(find.text('BM4a. Forearm - Activation'), findsOneWidget);
    expect(find.text('HYDRA-MOBILE'), findsOneWidget); // every ring names its unit
    await shot(tester, 'calm_one');
    expect(tester.takeException(), isNull);
  });

  testWidgets('two units: names, both rings', (tester) async {
    await pump(tester, const [one, two], who: 'Guest');
    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('2 sessions in progress'), findsOneWidget);
    expect(find.text('HYDRA-MOBILE'), findsOneWidget);
    expect(find.text('Resting between protocols'), findsOneWidget);
    await shot(tester, 'calm_two');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap does not exit; a 0.9s hold does', (tester) async {
    var exits = 0;
    await pump(tester, const [one], onExit: () => exits++);
    await tester.tap(find.text('Hold to return'));
    await tester.pump(const Duration(milliseconds: 950));
    expect(exits, 0);

    final g = await tester.startGesture(
        tester.getCenter(find.text('Hold to return')));
    for (var k = 0; k < 5; k++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(exits, 0); // half-way: still here
    for (var k = 0; k < 7; k++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(exits, 1);
    await g.up();
  });
}
