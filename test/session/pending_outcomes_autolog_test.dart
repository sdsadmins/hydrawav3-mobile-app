// [FIX-01] / [FIX-02] Post-session outcomes are logged exactly once.
//
// PendingOutcomesNotifier (lib/features/session/presentation/providers/
// pending_outcomes_provider.dart) finalizes a queued session by POSTing one
// `/intake` record through SessionRepository.finalizeSession.
//
// - FIX-01: leaving SessionAfterScreen by ANY route (unmount, Navigator pop,
//   "Save & done") calls autoLog → ONE POST /intake for that session.
// - FIX-02: autoLogUnreviewed (app start / History open) POSTs each queued
//   outcome once; a later "Save & done" on an auto-saved session makes no
//   second POST.
//
// The real SessionRepository needs the Drift database, so it is replaced by a
// thin repository that performs the same `POST /intake` with
// `record.toIntakeJson()` against a FakeHttp — the request log is what the
// assertions count.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/constants/api_endpoints.dart';
import 'package:hydrawav3/core/network/dio_client.dart';
import 'package:hydrawav3/core/router/route_names.dart';
import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';
import 'package:hydrawav3/features/clients/domain/client_model.dart';
import 'package:hydrawav3/features/clients/presentation/providers/client_providers.dart';
import 'package:hydrawav3/features/protocols/domain/protocol_model.dart';
import 'package:hydrawav3/features/session/data/session_repository.dart';
import 'package:hydrawav3/features/session/domain/pending_session_outcome_model.dart';
import 'package:hydrawav3/features/session/domain/session_model.dart';
import 'package:hydrawav3/features/session/presentation/providers/pending_outcomes_provider.dart';
import 'package:hydrawav3/features/session/presentation/screens/session_after_screen.dart';

import '../helpers/fake_http.dart';
import '../helpers/fakes.dart';
import '../helpers/qa_snap.dart';

/// `POST /intake` with the record's intake JSON — the network half of
/// SessionRepository.finalizeSession, minus the local Drift write.
class _IntakeRepo implements SessionRepository {
  _IntakeRepo(this._dio);
  final Dio _dio;

  @override
  Future<bool> finalizeSession(SessionRecord record) async {
    try {
      await _dio.post(ApiEndpoints.intake, data: record.toIntakeJson());
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

const _protocolName = 'PNF Active Training 3';

/// The intake body carries no session id, so each session runs on its own
/// device (`DEV-<sessionId>`) to tell the POSTs apart.
PendingSessionOutcome _pending(String sessionId) => PendingSessionOutcome(
      sessionId: sessionId,
      protocolId: 'p1',
      protocolName: _protocolName,
      deviceIds: ['DEV-$sessionId'],
      protocolNamesByDeviceId: {
        'DEV-$sessionId': const [_protocolName],
      },
      questionsByProtocolName: const {
        _protocolName: [
          ProtocolQuestion(
            text: 'Did your mobility improve?',
            answers: [
              ProtocolAnswerOption(answer: 'Yes', rank: 5),
              ProtocolAnswerOption(answer: 'No', rank: 1),
            ],
          ),
        ],
      },
      clientType: 'client',
      clientId: 'client-1',
      totalDurationSeconds: 600,
      elapsedSeconds: 600,
      createdAt: DateTime(2026, 8, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHttp server;
  late ProviderContainer container;

  Future<void> setUpContainer() async {
    server = FakeHttp()..onJson('POST', ApiEndpoints.intake, {'ok': true});
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authStateProvider.overrideWith((ref) => FakeAuth()),
      // The screen names the client from this list; without the override it
      // would hit the real Dio + secure storage (4s read timeouts).
      clientListProvider.overrideWith((ref) async => const <Client>[]),
      sessionRepositoryProvider.overrideWithValue(_IntakeRepo(server.dio())),
      // No real network anywhere: anything else that reaches for a Dio is
      // recorded here (and answered 404) instead of hanging on the auth
      // interceptor's secure-storage read.
      nodeDioProvider.overrideWithValue(server.dio()),
      djangoDioProvider.overrideWithValue(server.dio()),
    ]);
    addTearDown(container.dispose);
  }

  List<FakeRequest> intakePosts() =>
      server.requestsTo(ApiEndpoints.intake, method: 'POST');

  /// Runs a notifier call under the test's fake clock: Dio's dispatch needs
  /// timers to elapse, so the frames are pumped until the future completes
  /// (bounded, so a stuck request fails instead of hanging the suite).
  Future<void> drive(WidgetTester tester, Future<void> work) async {
    var done = false;
    unawaited(work.whenComplete(() => done = true));
    for (var i = 0; i < 40 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(done, isTrue, reason: 'notifier call did not complete');
  }

  /// Unmount everything and let the fire-and-forget autoLog land.
  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
  }

  Widget host(Widget child) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: child),
      );

  group('[FIX-01] leaving the after-screen auto-logs once', () {
    qaTestWidgets('[FIX-01] unmounting the screen POSTs /intake exactly once',
        (tester) async {
      await setUpContainer();
      await container
          .read(pendingOutcomesProvider.notifier)
          .enqueue(_pending('s-unmount'));

      await tester
          .pumpWidget(host(const SessionAfterScreen(sessionId: 's-unmount')));
      await tester.pumpAndSettle();
      // Answer one question so the auto-log carries it.
      await tester.tap(find.text('Yes'));
      await tester.pump();
      expect(intakePosts(), isEmpty, reason: 'held back while under review');

      await leave(tester);

      expect(intakePosts(), hasLength(1));
      final body = intakePosts().single.json;
      expect(body.toString(), contains('Did your mobility improve?'));
      // Queue entry is dropped after a successful POST.
      expect(
        container.read(pendingOutcomesProvider.notifier).getById('s-unmount'),
        isNull,
      );
    });

    // KNOWN BUG: SessionAfterScreen.dispose (session_after_screen.dart:109)
    // calls autoLog synchronously; PendingOutcomesNotifier.finalize sets
    // `state` before its first await, i.e. during the widget-tree build in
    // which the popped route is unmounted. Riverpod rejects that ("Tried to
    // modify a provider while the widget tree was building") and finalize
    // aborts BEFORE the POST — so in debug a back-navigation never logs the
    // session. The unmount test above passes only because it tears the whole
    // ProviderScope down with the screen.
    qaTestWidgets('[FIX-01] a Navigator pop POSTs /intake exactly once',
        tags: ['qa-known-bug'], (tester) async {
      await setUpContainer();
      await container
          .read(pendingOutcomesProvider.notifier)
          .enqueue(_pending('s-pop'));

      await tester.pumpWidget(host(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SessionAfterScreen(sessionId: 's-pop'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(SessionAfterScreen), findsOneWidget);

      // System / gesture back.
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.pop();
      await tester.pumpAndSettle();
      expect(find.byType(SessionAfterScreen), findsNothing);

      expect(intakePosts(), hasLength(1));
      await leave(tester);
      expect(intakePosts(), hasLength(1), reason: 'no second POST later');
    });

    qaTestWidgets(
        '[FIX-01] "Save & done" POSTs once and the dispose that follows adds none',
        (tester) async {
      await setUpContainer();
      await container
          .read(pendingOutcomesProvider.notifier)
          .enqueue(_pending('s-save'));

      final router = GoRouter(
        initialLocation: RoutePaths.sessionAfter,
        routes: [
          GoRoute(
            path: RoutePaths.sessionAfter,
            builder: (_, __) => const SessionAfterScreen(sessionId: 's-save'),
          ),
          GoRoute(
            path: RoutePaths.home,
            builder: (_, __) => const Scaffold(body: Text('HOME')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Yes'));
      await tester.pump();
      await tester.tap(find.text('Save & done'));
      await tester.pumpAndSettle();

      expect(find.text('HOME'), findsOneWidget);
      expect(intakePosts(), hasLength(1));

      await leave(tester);
      expect(intakePosts(), hasLength(1));
    });
  });

  group('[FIX-02] autoLogUnreviewed', () {
    qaTestWidgets('[FIX-02] POSTs each queued outcome exactly once',
        (tester) async {
      await setUpContainer();
      final notifier = container.read(pendingOutcomesProvider.notifier);
      await notifier.enqueue(_pending('s-a'));
      await notifier.enqueue(_pending('s-b'));

      await drive(tester, notifier.autoLogUnreviewed());

      expect(intakePosts(), hasLength(2));
      String deviceOf(FakeRequest r) =>
          ((r.json['protocols'] as List).single as Map)['deviceName'] as String;
      expect(intakePosts().map(deviceOf), unorderedEquals(['DEV-s-a', 'DEV-s-b']));
      // Both left the queue.
      expect(container.read(pendingOutcomesProvider), isEmpty);

      // Running it again on start finds nothing to send.
      await drive(tester, notifier.autoLogUnreviewed());
      expect(intakePosts(), hasLength(2));
    });

    qaTestWidgets(
        '[FIX-02] "Save & done" after an auto-save makes no second POST',
        (tester) async {
      await setUpContainer();
      final notifier = container.read(pendingOutcomesProvider.notifier);
      await notifier.enqueue(_pending('s-auto'));
      await drive(tester, notifier.autoLogUnreviewed());
      expect(intakePosts(), hasLength(1));

      // The after-screen is opened afterwards (e.g. from a stale card) and the
      // user taps through.
      final router = GoRouter(
        initialLocation: RoutePaths.sessionAfter,
        routes: [
          GoRoute(
            path: RoutePaths.sessionAfter,
            builder: (_, __) => const SessionAfterScreen(sessionId: 's-auto'),
          ),
          GoRoute(
            path: RoutePaths.home,
            builder: (_, __) => const Scaffold(body: Text('HOME')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & done'));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);

      await leave(tester);
      expect(intakePosts(), hasLength(1), reason: 'already logged once');
    });

    qaTestWidgets('[FIX-02] a session under review is skipped, then logged once',
        (tester) async {
      await setUpContainer();
      final notifier = container.read(pendingOutcomesProvider.notifier);
      await notifier.enqueue(_pending('s-review'));

      await tester.pumpWidget(
          host(const SessionAfterScreen(sessionId: 's-review')));
      await tester.pumpAndSettle();

      // App-start sweep while the screen is open: held back.
      await drive(tester, notifier.autoLogUnreviewed());
      expect(intakePosts(), isEmpty);

      await leave(tester);
      expect(intakePosts(), hasLength(1));
    });
  });
}
