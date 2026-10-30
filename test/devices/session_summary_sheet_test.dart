import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrawav3/features/devices/presentation/widgets/plan_sheet.dart';
import 'package:hydrawav3/features/devices/presentation/widgets/session_plan_widgets.dart';

/// Session Plan summary strip → the read-only "This session" sheet
/// (v6 `V6.summarySheet`).
void main() {
  for (final size in [const Size(390, 844), const Size(1024, 1366)]) {
    final tag = size.width > 600 ? 'tablet' : 'phone';

    testWidgets('tapping the summary opens This session ($tag)',
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
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        builder: (c, child) => RepaintBoundary(child: child),
        home: Scaffold(
          body: Builder(
            builder: (context) => Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: PlanSummaryStrip(
                  who: 'Guest',
                  units: 2,
                  longest: const Duration(minutes: 12),
                  protocols: const ['Deep-Tension Recovery', 'Energizing 3'],
                  guest: true,
                  onTap: () => showPlanSheet<void>(
                    context,
                    title: 'This session',
                    subtitle: 'Guest · 2 units will run after a 5s delay.',
                    builder: (_) => const PlanSessionSummaryBody(
                      run: [
                        PlanSummaryUnit(
                            name: 'Hydra-Mobile',
                            protocol: 'Deep-Tension Recovery',
                            right: '12 min'),
                        PlanSummaryUnit(
                            name: 'Unit 2',
                            protocol: 'Energizing 3',
                            right: '7 min · +5s'),
                        PlanSummaryUnit(
                            name: 'Unit 3',
                            protocol: 'Total Recovery',
                            right: 'Running'),
                      ],
                      off: [
                        PlanSummaryUnit(
                            name: 'Unit 4',
                            protocol: 'Total Recovery',
                            right: 'Off',
                            dim: true),
                      ],
                      guest: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Guest'));
      for (var k = 0; k < 6; k++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(find.text('This session'), findsOneWidget);
      expect(find.text('7 min · +5s'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
      expect(find.textContaining('CONNECTED BUT OFF'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final dir = Platform.environment['SHOTS'];
      if (dir != null) {
        final ro = tester.renderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary).first);
        await tester.runAsync(() async {
          final img = await ro.toImage(pixelRatio: 1);
          final d = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$dir/summary_sheet_$tag.png')
              .writeAsBytesSync(d!.buffer.asUint8List());
        });
      }

      await tester.tap(find.text('Close'));
      for (var k = 0; k < 6; k++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(find.text('This session'), findsNothing);
    });
  }
}
