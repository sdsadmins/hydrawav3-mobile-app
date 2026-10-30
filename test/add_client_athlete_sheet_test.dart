import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrawav3/features/clients/presentation/widgets/new_client_sheet.dart';
import 'package:hydrawav3/features/devices/presentation/providers/players_provider.dart';

/// The one "Add client / athlete" sheet (v6 `55-intake`): the Sports athlete
/// switch opens sport, jersey and positions, and the button follows it.
void main() {
  const football = OrgSport(
    mappingId: 'm1',
    sportId: 's1',
    name: 'Football',
    isActive: true,
    positions: [
      Position(id: 'p1', name: 'Quarterback'),
      Position(id: 'p2', name: 'Wide Receiver'),
      Position(id: 'p3', name: 'Linebacker'),
    ],
  );

  Future<void> open(WidgetTester tester, {required bool athlete}) async {
    final fonts = Platform.environment['ROBOTO_DIR'];
    if (fonts != null) {
      final l = FontLoader('Roboto');
      for (final f in ['regular', 'medium', 'bold', 'black']) {
        l.addFont(Future.value(ByteData.view(
            File('$fonts/roboto-$f.ttf').readAsBytesSync().buffer)));
      }
      await l.load();
    }
    tester.view.physicalSize = const Size(390, 1000) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        orgSportsProvider.overrideWith((ref) async => const [football]),
      ],
      child: MaterialApp(
        builder: (c, child) => RepaintBoundary(child: child),
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    showAddClientAthleteSheet(context, ref, athlete: athlete),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    for (var k = 0; k < 6; k++) {
      await tester.pump(const Duration(milliseconds: 150));
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

  testWidgets('client by default; the switch turns it into an athlete',
      (tester) async {
    await open(tester, athlete: false);
    expect(find.text('New client · athlete intake'), findsOneWidget);
    expect(find.text('Sports athlete'), findsOneWidget);
    expect(find.text('Create client'), findsOneWidget);
    expect(find.text('Quarterback'), findsNothing);
    await shot(tester, 'add_client_off');

    await tester.tap(find.text('Sports athlete'));
    for (var k = 0; k < 4; k++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.text('Create athlete'), findsOneWidget);
    expect(find.text('Football'), findsOneWidget);
    expect(find.text('Quarterback'), findsOneWidget);
    await tester.ensureVisible(find.text('Quarterback'));
    await tester.tap(find.text('Quarterback'));
    for (var k = 0; k < 3; k++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    // picked: solid copper chip, dark text
    expect(tester.widget<Text>(find.text('Quarterback')).style?.color,
        const Color(0xFF2B1D12));
    await shot(tester, 'add_client_on');
    expect(tester.takeException(), isNull);
  });

  testWidgets('university entry opens as an athlete', (tester) async {
    await open(tester, athlete: true);
    expect(find.text('Create athlete'), findsOneWidget);
    expect(find.text('Wide Receiver'), findsOneWidget);
  });
}
