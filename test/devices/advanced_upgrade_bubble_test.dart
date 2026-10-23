// Session Plan → unit card → Advanced: the premium upgrade bubble (R4-01) and
// the normal expand/collapse of the Advanced panel (R4-02).
//
// The real Session Plan screen (DeviceListScreen) is pumped in WiFi mode with
// one selected unit, so the card is the exact widget a practitioner taps.
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_snap.dart';
import 'session_plan_host.dart';

const _premiumTitle = 'Advanced is a premium feature';
const _premiumBody =
    'Upgrade your account to unlock advanced session settings.';

void main() {
  setUpAll(loadAppFonts);

  qaTestWidgets(
    '[R4-01] locked Advanced shows the premium bubble, builds no panel, Got it closes it',
    (tester) async {
      // No protocol can be seeded (empty catalogue) → Advanced stays locked.
      await pumpSessionPlan(tester, protocols: const []);

      expect(find.byTooltip('Advanced settings'), findsOneWidget);
      expect(find.text('More settings'), findsNothing);

      await tester.tap(find.byTooltip('Advanced settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(_premiumTitle), findsOneWidget);
      expect(find.text(_premiumBody), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
      // The advanced panel itself is never built for a locked unit.
      expect(find.text('More settings'), findsNothing);

      await tester.tap(find.text('Got it'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(_premiumTitle), findsNothing);
    },
    // device_list_screen.dart:3079 — in the v6 card (refDesign, the only path
    // the Session Plan tab renders) a locked Advanced button has onTap: null,
    // so _showAdvancedUpgradeInfo (line 3867) is never reached.
    tags: ['qa-known-bug'],
  );

  qaTestWidgets(
    '[R4-02] Advanced enabled: tapping toggles the panel and never shows the premium text',
    (tester) async {
      await pumpSessionPlan(tester, protocols: [kPlanProtocolOption]);

      expect(find.text('More settings'), findsNothing);

      await tester.tap(find.byTooltip('Advanced settings'));
      await settlePlan(tester);
      expect(find.text('More settings'), findsOneWidget);
      expect(find.text(_premiumTitle), findsNothing);
      expect(find.text(_premiumBody), findsNothing);

      await tester.tap(find.byTooltip('Advanced settings'));
      await settlePlan(tester);
      expect(find.text('More settings'), findsNothing);
      expect(find.text(_premiumTitle), findsNothing);
      expect(tester.takeException(), isNull);

      // The armed Start FAB schedules a one-shot 4s timer; let it elapse so
      // nothing outlives the test.
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
