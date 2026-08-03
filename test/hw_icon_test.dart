import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrawav3/core/theme/widgets/hw_icon.dart';

/// Every icon in the handoff set is hand-authored SVG. A typo in the path data
/// or a missing pubspec asset entry only shows up as a blank square at runtime,
/// so parse them all through flutter_svg's real loader here instead.
void main() {
  const assets = <String>[
    // nav
    HwIcons.home, HwIcons.bolt, HwIcons.assistant, HwIcons.users,
    HwIcons.more,
    // hub
    HwIcons.wave, HwIcons.arrow, HwIcons.chev, HwIcons.caret, HwIcons.check,
    HwIcons.sliders, HwIcons.offline, HwIcons.chat, HwIcons.play,
    HwIcons.target, HwIcons.chart, HwIcons.clock, HwIcons.star,
    HwIcons.flask, HwIcons.book, HwIcons.phone, HwIcons.briefcase,
    HwIcons.bag, HwIcons.drag, HwIcons.x,
    // more
    HwIcons.pencil, HwIcons.building, HwIcons.sun, HwIcons.moon,
    HwIcons.bot, HwIcons.note, HwIcons.guest, HwIcons.key, HwIcons.bell,
    HwIcons.scale, HwIcons.gear, HwIcons.trash, HwIcons.doc,
  ];

  testWidgets('every HwIcons asset loads and renders', (tester) async {
    for (final asset in assets) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: HwIcon(asset, size: 24, color: Colors.black)),
        ),
      );
      // flutter_svg decodes asynchronously; settle so a parse error surfaces.
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: '$asset failed to load or parse',
      );
      expect(find.byType(HwIcon), findsOneWidget, reason: asset);
    }
  });

  testWidgets('an icon with a baked colour renders without a tint',
      (tester) async {
    // HwIcons.guest carries stroke="#A87B5C" so it stays copper in both
    // themes; passing color: null must not throw.
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: HwIcon(HwIcons.guest, size: 24))),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
