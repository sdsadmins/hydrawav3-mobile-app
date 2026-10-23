// Session Plan → Start: the plan's concurrent-device limit. With a 1-device
// plan and one device already running org-wide, Start must refuse with the
// exact message and never launch a session.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/devices/presentation/widgets/session_plan_widgets.dart';

import '../helpers/qa_snap.dart';
import 'session_plan_host.dart';

const _limitMessage =
    'Your plan allows 1 device(s) at a time (1 already running). Stop a '
    'device or upgrade your plan to run more.';

void main() {
  setUpAll(loadAppFonts);

  qaTestWidgets(
    '[R4-45] limit 1 with 1 live device: Start refuses with the plan message and does not launch',
    (tester) async {
      await pumpSessionPlan(
        tester,
        protocols: [kPlanProtocolOption],
        deviceLimit: 1,
        liveDevices: 1,
      );

      // The unit is selected with its seeded protocol, so Start is armed.
      final fab = tester.widget<PlanStartFab>(find.byType(PlanStartFab));
      expect(fab.ready, isTrue, reason: 'unit + protocol → Start is ready');
      expect(fab.starting, isFalse);

      await tester.tap(find.byType(PlanStartFab));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.widgetWithText(SnackBar, _limitMessage), findsOneWidget);

      // launchSession was never entered: no "Starting..." state, no session
      // route pushed (there is no router here — a push would throw), and the
      // Start button is back to idle.
      expect(
        tester.widget<PlanStartFab>(find.byType(PlanStartFab)).starting,
        isFalse,
      );
      expect(find.text('Starting...'), findsNothing);
      expect(find.textContaining('Start failed'), findsNothing);
      expect(tester.takeException(), isNull);

      // Drain the 4s SnackBar so no timer outlives the test.
      await tester.pump(const Duration(seconds: 5));
    },
  );

  qaTestWidgets(
    '[R4-45] a 2-device plan with 1 running does not show the limit message',
    (tester) async {
      await pumpSessionPlan(
        tester,
        protocols: [kPlanProtocolOption],
        deviceLimit: 2,
        liveDevices: 1,
      );
      expect(
        tester.widget<PlanStartFab>(find.byType(PlanStartFab)).ready,
        isTrue,
      );
      // Not tapping Start here (that would launch a real session); the guard
      // message must simply not be anywhere on the plan.
      expect(find.textContaining('Your plan allows'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
