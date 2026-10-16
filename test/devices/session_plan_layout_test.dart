import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/core/theme/widgets/hw_tablet.dart';
import 'package:hydrawav3/features/advanced_settings/domain/advanced_settings_model.dart';
import 'package:hydrawav3/features/devices/presentation/screens/device_list_screen.dart';
import 'package:hydrawav3/features/devices/presentation/widgets/find_pad_placements_card.dart';
import 'package:hydrawav3/features/devices/presentation/widgets/session_plan_widgets.dart';

/// Lays out the v6 Session Plan pieces at phone and tablet width. The unit
/// card packs a switch, an animated puck, a pill and a two-line protocol into
/// one row, so an overflow here would only show up on a real device.
void main() {
  Future<void> pump(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          final side = HwTablet.sidePadding(context, phone: 16);
          return ListView(
            padding: EdgeInsets.symmetric(horizontal: side),
            children: [child],
          );
        }),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  }

  testWidgets('unit cards lay out in every state on the narrowest phone',
      (tester) async {
    await pump(
      tester,
      const Size(320, 2400),
      Column(children: [
        debugSessionUnitCard(name: 'Unit 1'),
        debugSessionUnitCard(name: 'Unit 2', inUse: false),
        debugSessionUnitCard(
          name: 'Hydrawav3 Studio North Treatment Room',
          protocolTitle: 'Deep-Tension Recovery with Lymphatic Activation',
          isRunning: true,
          inUse: false,
        ),
        debugSessionUnitCard(name: 'Unit 4', isPendingStop: true),
        const IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: FindPadPlacementsCard()),
              SizedBox(width: 10),
              Expanded(child: FindPadPlacementsCard()),
            ],
          ),
        ),
        const PlanSummaryStrip(
          who: 'Guest',
          units: 2,
          longest: Duration(minutes: 9),
          protocols: ['Performance Activation'],
          guest: true,
        ),
      ]),
    );
    expect(find.text('PROTOCOL:'), findsNWidgets(3));
    expect(find.text('Running — controlled elsewhere'), findsOneWidget);
    expect(find.text('In use'), findsOneWidget);
    expect(find.text('Stop pending'), findsOneWidget);
  });

  testWidgets('the ID pill reveals the unit id', (tester) async {
    await pump(tester, const Size(390, 900),
        debugSessionUnitCard(name: 'Unit 1'));
    expect(find.text('48:CA:43:B0:02:B1'), findsNothing);
    await tester.tap(find.text('ID'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('48:CA:43:B0:02:B1'), findsOneWidget);
  });

  testWidgets('the Delay stepper steps the start delay within 0-60',
      (tester) async {
    var delay = 0;
    await pump(
      tester,
      const Size(320, 900),
      StatefulBuilder(
        builder: (context, setState) => debugSessionUnitCard(
          name: 'Unit 1',
          startDelay: delay,
          onChangeStartDelay: (v) => setState(() => delay = v),
        ),
      ),
    );
    expect(find.text('DELAY'), findsOneWidget);
    await tester.tap(find.text('−'));
    await tester.pump();
    expect(delay, 0);
    await tester.tap(find.text('+'));
    await tester.pump();
    await tester.tap(find.text('+'));
    await tester.pump();
    expect(delay, 2);
    await tester.tap(find.text('−'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(delay, 1);
  });

  testWidgets('a busy unit shows its state chip instead of the stepper',
      (tester) async {
    await pump(tester, const Size(390, 900),
        debugSessionUnitCard(name: 'Unit 1', isRunning: true, inUse: false));
    expect(find.text('DELAY'), findsNothing);
  });

  testWidgets('advanced panel: tap-to-reset, More settings, same setters',
      (tester) async {
    var adv = const AdvancedSettings(hotPercent: 4);
    await pump(
      tester,
      const Size(320, 1600),
      StatefulBuilder(
        builder: (context, setState) => debugSessionUnitCard(
          name: 'Unit 1',
          showAdvanced: true,
          advanced: adv,
          onChangeAdvanced: (v) => setState(() => adv = v),
        ),
      ),
    );
    expect(find.text('Start Delay (seconds)'), findsNothing);
    await tester.tap(find.text('+4%'));
    await tester.pump();
    expect(adv.hotPercent, 0);

    expect(find.text('Warm Opening Cycle'), findsNothing);
    await tester.tap(find.text('More settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.text('Lights'));
    await tester.pump();
    await tester.tap(find.text('Lights'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(adv.lights, isFalse);

    await tester.ensureVisible(find.text('OFF'));
    await tester.pump();
    await tester.tap(find.text('OFF'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(adv.vibrationMode, 'Off');
    expect(find.text('VIBRATION MIN'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Protocol Plus panel keeps its own controls', (tester) async {
    await pump(
      tester,
      const Size(320, 1400),
      debugSessionUnitCard(
        name: 'Unit 1',
        showAdvanced: true,
        protocolPlus: true,
        advanced: const AdvancedSettings(),
      ),
    );
    for (final t in ['Vibration', 'Lights', 'Flip Sun and Moon pad']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('More settings'), findsNothing);
    expect(find.text('START DELAY'), findsNothing);
  });

  testWidgets('tablet puts the units two across', (tester) async {
    await pump(
      tester,
      const Size(834, 1400),
      HwAutoGrid(gap: 14, children: [
        debugSessionUnitCard(name: 'Unit A'),
        debugSessionUnitCard(name: 'Unit B'),
      ]),
    );
    final a = tester.getTopLeft(find.text('Unit A'));
    final b = tester.getTopLeft(find.text('Unit B'));
    expect((a.dy - b.dy).abs(), lessThan(2));
    expect(b.dx, greaterThan(a.dx + 300));
  });
}
