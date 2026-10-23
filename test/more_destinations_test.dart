import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/ai_hub/presentation/screens/ai_hub_screen.dart';
import 'package:hydrawav3/features/clients/presentation/providers/client_providers.dart';
import 'package:hydrawav3/features/history/data/history_repository.dart';
import 'package:hydrawav3/features/history/domain/session_history_model.dart';
import 'package:hydrawav3/features/history/presentation/screens/history_list_screen.dart';
import 'package:hydrawav3/features/notifications/domain/app_notification.dart';
import 'package:hydrawav3/features/notifications/presentation/providers/notification_provider.dart';
import 'package:hydrawav3/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:hydrawav3/features/payments/presentation/providers/token_balance_provider.dart';
import 'package:hydrawav3/features/notifications/data/notification_remote_source.dart';
import 'package:hydrawav3/features/protocols/domain/protocol_model.dart';
import 'package:hydrawav3/features/protocols/domain/protocol_plus_model.dart';
import 'package:hydrawav3/features/protocols/presentation/providers/protocol_plus_detail_provider.dart';
import 'package:hydrawav3/features/protocols/presentation/providers/protocol_provider.dart';
import 'package:hydrawav3/features/protocols/presentation/screens/protocol_list_screen.dart';
import 'package:hydrawav3/features/settings/presentation/screens/legal_screen.dart';

import 'helpers/fakes.dart';
import 'helpers/pump_app.dart';

/// Every screen More opens must lay out with no backend reachable.
///
/// This is the pattern that caught a blank Hub earlier: `flutter analyze` and a
/// release build both pass with a scroll-view layout assertion in place, so the
/// only way to catch one is to pump the widget and check for an exception.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    List<Override> overrides = const [],
  }) async {
    await pumpApp(
      tester,
      screen,
      // Tall, so every section lays out without scrolling.
      size: const Size(390, 2400),
      pixelRatio: 3.0,
      overrides: [
        currentPlanProvider.overrideWith((ref) async => null),
        planTokenGrantProvider.overrideWith((ref) async => null),
        ...overrides,
      ],
      settle: const Duration(milliseconds: 600),
    );
  }

  // The "Generate a report" (guided assessment) card was deliberately
  // commented out in 5376752 and AI Reports is behind a "Coming soon" banner,
  // so the Hub now shows two cards.
  testWidgets('AI Hub renders its two cards', (tester) async {
    await pump(tester, const AiHubScreen());

    expect(tester.takeException(), isNull);
    expect(find.text('AI Hub'), findsOneWidget);
    expect(find.text('AI Assistant'), findsOneWidget);
    expect(find.text('AI Reports'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.text('Generate a report'), findsNothing);
  });

  testWidgets('Legal shows the wellness statement and required attribution',
      (tester) async {
    await pump(tester, const LegalScreen());

    expect(tester.takeException(), isNull);
    expect(find.text('Legal & licenses'), findsOneWidget);
    expect(find.text('WELLNESS STATEMENT'), findsOneWidget);
    // The Z-Anatomy licence requires this credit to be present.
    expect(find.textContaining('Z-Anatomy (CC BY-SA 4.0)'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Help center'), findsOneWidget);
  });

  testWidgets('Notifications dims read rows and counts the unread',
      (tester) async {
    await pump(
      tester,
      const NotificationsScreen(),
      overrides: [
        // The screen marks unread entries read on view, which POSTs — stub the
        // source so the test doesn't leave a live request behind.
        notificationRemoteSourceProvider
            .overrideWithValue(FakeNotificationSource()),
        notificationsProvider.overrideWith((ref) async => [
              const AppNotification(
                  id: '1', title: 'AI report ready', message: 'Kinetic chain'),
              const AppNotification(
                  id: '2',
                  title: 'Lease activated',
                  message: 'Unit 3',
                  read: true),
            ]),
      ],
    );

    expect(tester.takeException(), isNull);
    expect(find.text('1 unread'), findsOneWidget);
    expect(find.text('AI report ready'), findsOneWidget);
    expect(find.text('Lease activated'), findsOneWidget);
    expect(
      find.textContaining('Quiet by design'),
      findsOneWidget,
    );
  });

  testWidgets('Notifications says so when there is nothing', (tester) async {
    await pump(
      tester,
      const NotificationsScreen(),
      overrides: [notificationsProvider.overrideWith((ref) async => [])],
    );

    expect(tester.takeException(), isNull);
    expect(find.text('all caught up'), findsOneWidget);
  });

  testWidgets('Protocol Library splits stacks from protocols', (tester) async {
    await pump(
      tester,
      const ProtocolListScreen(),
      overrides: [
        goalTagListProvider.overrideWith((ref) async => []),
        // Each stack card fetches its sub-protocols; stub it so no request is
        // left in flight.
        protocolPlusDetailProvider.overrideWith(
          (ref, id) async => const ProtocolPlus(
            id: 's1',
            templateName: 'Total Recovery',
            protocols: [
              Protocol(
                  id: 'a', templateName: 'Hot Pack', description: 'Warm up.'),
              Protocol(
                  id: 'b',
                  templateName: 'Deep Session',
                  description: 'Settle.'),
            ],
          ),
        ),
        protocolListProvider.overrideWith((ref) async => [
              const Protocol(
                id: 'p1',
                templateName: 'Short Session',
                description: 'A quick reset.',
                apiTotalDurationSeconds: 540,
              ),
              const Protocol(
                id: 's1',
                templateName: 'Total Recovery',
                description: 'A full sequence.',
                isProtocolPlus: true,
                apiTotalDurationSeconds: 1200,
              ),
            ]),
      ],
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Protocol Library'), findsOneWidget);
    expect(find.text('RECOMMENDED STACKS'), findsOneWidget);
    expect(find.text('PROTOCOLS'), findsOneWidget);
    expect(find.text('Total Recovery'), findsOneWidget);
    expect(find.text('Short Session'), findsOneWidget);
    // Counts come from the real list, not a hardcoded string.
    expect(find.textContaining('1 stacks · 1 protocols'), findsOneWidget);
  });

  testWidgets('Protocol Library marks plan-locked protocols', (tester) async {
    await pump(
      tester,
      const ProtocolListScreen(),
      overrides: [
        goalTagListProvider.overrideWith((ref) async => []),
        protocolListProvider.overrideWith((ref) async => [
              const Protocol(
                id: 'p1',
                templateName: 'Locked One',
                description: '',
                active: false,
              ),
            ]),
      ],
    );

    expect(tester.takeException(), isNull);
    // The spec badges everything "Included"; real plan gating says otherwise.
    expect(find.text('Locked'), findsOneWidget);
    expect(find.text('Included'), findsNothing);
  });

  testWidgets('History groups rows under day headers', (tester) async {
    final now = DateTime.now();
    await pump(
      tester,
      const HistoryListScreen(),
      overrides: [
        clientListProvider.overrideWith((ref) async => []),
        // Since 8957c83 the "All" list is the scroll-paginated
        // historyPagingProvider, not allSessionsProvider.
        historyPagingProvider.overrideWith(
          (ref) => FixedHistory(ref, [
            SessionHistoryItem(
              id: 'a',
              clientType: 'guest',
              createdAt: now,
              protocols: const [HistoryProtocol(protocol: 'Short Session')],
            ),
            SessionHistoryItem(
              id: 'b',
              clientType: 'guest',
              createdAt: now.subtract(const Duration(days: 3)),
              protocols: const [HistoryProtocol(protocol: 'Deep Session')],
            ),
          ]),
        ),
      ],
    );

    expect(tester.takeException(), isNull);
    expect(find.text('History'), findsWidgets);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('Guest'), findsNWidgets(2));
    // No outcome check captured → a "--" placeholder (e55bb93 dropped the
    // em-dash app-wide), never a fabricated result.
    expect(find.text('--'), findsNWidgets(2));
  });

  testWidgets('History keeps working embedded in the Users tab',
      (tester) async {
    await pump(
      tester,
      const Scaffold(body: HistoryListScreen(embedded: true)),
      overrides: [
        clientListProvider.overrideWith((ref) async => []),
        historyPagingProvider.overrideWith((ref) => FixedHistory(ref, [])),
      ],
    );

    expect(tester.takeException(), isNull);
    // Embedded mode drops the backbar and segmented control — the host page
    // already provides that context.
    expect(find.text('Team'), findsNothing);
    expect(find.textContaining('outcome checks build'), findsNothing);
  });
}
