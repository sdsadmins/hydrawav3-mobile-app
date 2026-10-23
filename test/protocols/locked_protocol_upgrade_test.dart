// Protocol Library: a protocol the plan doesn't include (active = false) is
// shown locked. Tapping it must explain the upgrade in a bubble (like the
// Session Plan's "premium feature" dialog) and must NOT open the detail page.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:hydrawav3/features/payments/presentation/providers/token_balance_provider.dart';
import 'package:hydrawav3/features/protocols/domain/protocol_model.dart';
import 'package:hydrawav3/features/protocols/presentation/providers/protocol_provider.dart';
import 'package:hydrawav3/features/protocols/presentation/screens/protocol_list_screen.dart';

import '../helpers/pump_app.dart';
import '../helpers/qa_snap.dart';

const _locked = Protocol(
  id: 'elite',
  templateName: 'Elite Lymphatic Protocol',
  description: 'Included in a higher plan',
  apiTotalDurationSeconds: 900,
  active: false,
);

const _included = Protocol(
  id: 'calm',
  templateName: 'Deep Relaxation',
  description: 'Long, slow parasympathetic settle',
  apiTotalDurationSeconds: 1200,
);

void main() {
  late GoRouter router;

  Future<void> pumpLibrary(WidgetTester tester) async {
    router = GoRouter(
      initialLocation: '/protocols',
      routes: [
        GoRoute(
          path: '/protocols',
          builder: (_, __) => const ProtocolListScreen(),
        ),
        GoRoute(
          path: '/protocols/:id',
          builder: (_, s) => Scaffold(
            body: Text('DETAIL ${s.pathParameters['id']}'),
          ),
        ),
      ],
    );
    setTestViewSize(tester, QaDevice.phone.size);
    await tester.pumpWidget(
      RepaintBoundary(
        key: qaRootKey,
        child: ProviderScope(
          overrides: [
            protocolListProvider
                .overrideWith((ref) async => const [_locked, _included]),
            goalTagListProvider.overrideWith((ref) async => const []),
            currentPlanProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp.router(
            theme: qaThemeFor(Brightness.light),
            routerConfig: router,
          ),
        ),
      ),
    );
    await pumpFrames(tester);
  }

  qaTestWidgets(
    '[R4-03] tapping a locked protocol shows an upgrade bubble and does not open it',
    (tester) async {
      await pumpLibrary(tester);
      expect(find.text('Elite Lymphatic Protocol'), findsOneWidget);
      expect(find.text('Locked'), findsOneWidget);

      await tester.tap(find.text('Elite Lymphatic Protocol'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Never pushes /protocols/:id for a locked protocol. (An imperative
      // push shows up as the LAST match, not in `currentConfiguration.uri`.)
      expect(router.routerDelegate.currentConfiguration.last.matchedLocation,
          '/protocols');
      expect(find.textContaining('DETAIL'), findsNothing);

      // An upgrade bubble — a dialog that talks about upgrading the plan,
      // with a way to dismiss it — not just a passing SnackBar.
      expect(find.byType(Dialog), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) =>
            w is Text &&
            RegExp(r'upgrade', caseSensitive: false)
                .hasMatch(w.data ?? w.textSpan?.toPlainText() ?? '')),
        findsWidgets,
      );
      expect(find.text('Got it'), findsOneWidget);
    },
    // protocol_list_screen.dart:437 — today `_lockedNotice` only shows the
    // SnackBar "This protocol isn't included in your plan."; no upgrade bubble
    // exists on the Protocol Library yet.
    tags: ['qa-known-bug'],
  );

  qaTestWidgets('[R4-03] an included protocol still opens its detail page',
      (tester) async {
    await pumpLibrary(tester);
    await tester.tap(find.text('Deep Relaxation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/protocols/calm');
    expect(find.text('DETAIL calm'), findsOneWidget);
  });
}
