import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/features/protocols/domain/protocol_model.dart';
import 'package:hydrawav3/features/session/domain/pending_session_outcome_model.dart';
import 'package:hydrawav3/features/session/presentation/providers/pending_outcomes_provider.dart';
import 'package:hydrawav3/features/session/presentation/screens/session_after_screen.dart';

/// The post-session screen must ask EVERY question the admin configured, with
/// EVERY answer option — not a single hardcoded YES / NO.
///
/// Shaped on the real backend record for "PNF Active Training 3"
/// (`69870a44b817549cad1e1968`): two questions, the first with three options
/// including one ("fd") that is neither a yes nor a no. The old screen showed
/// question 1 only, as two guessed buttons, so question 2 was never asked and
/// "fd" could not be selected at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const protocolName = 'PNF Active Training 3';

  PendingSessionOutcome pending({bool stoppedEarly = false}) =>
      PendingSessionOutcome(
        sessionId: 'session-1',
        protocolId: 'p1',
        protocolName: protocolName,
        deviceIds: const ['AA:BB:CC:DD:EE:FF'],
        protocolNamesByDeviceId: const {
          'AA:BB:CC:DD:EE:FF': [protocolName],
        },
        questionsByProtocolName: const {
          protocolName: [
            ProtocolQuestion(
              text: 'Did your mobility improve?',
              answers: [
                ProtocolAnswerOption(answer: 'Yes', rank: 5),
                ProtocolAnswerOption(answer: 'No', rank: 1),
                ProtocolAnswerOption(answer: 'fd', rank: 3),
              ],
            ),
            ProtocolQuestion(
              text: 'Did your health improve?',
              answers: [
                ProtocolAnswerOption(answer: 'Yes', rank: 1),
                ProtocolAnswerOption(answer: 'No', rank: 2),
              ],
            ),
          ],
        },
        clientType: 'client',
        clientId: 'client-1',
        totalDurationSeconds: 600,
        elapsedSeconds: 600,
        createdAt: DateTime(2026, 8, 1),
        stoppedEarly: stoppedEarly,
      );

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    bool stoppedEarly = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await container
        .read(pendingOutcomesProvider.notifier)
        .enqueue(pending(stoppedEarly: stoppedEarly));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SessionAfterScreen(sessionId: 'session-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// Leaving the screen is what triggers the automatic log, so every test has to
  /// unmount deliberately — otherwise that work is still in flight at teardown
  /// and the binding fails on a pending timer.
  Future<void> leaveScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
  }

  testWidgets('asks every configured question, not just the first',
      (tester) async {
    await pumpScreen(tester);

    expect(find.textContaining('Did your mobility improve?'), findsOneWidget);
    expect(find.textContaining('Did your health improve?'), findsOneWidget);
    expect(find.text('2 questions'), findsOneWidget);

    await leaveScreen(tester);
  });

  testWidgets('renders every answer option, including non yes/no ones',
      (tester) async {
    await pumpScreen(tester);

    // "fd" was unreachable on the old yes/no pulse.
    expect(find.text('fd'), findsOneWidget);
    // One Yes + one No per question.
    expect(find.text('Yes'), findsNWidgets(2));
    expect(find.text('No'), findsNWidgets(2));

    await leaveScreen(tester);
  });

  testWidgets('offers a remarks field', (tester) async {
    await pumpScreen(tester);
    expect(find.text('REMARKS'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Practitioner notes (optional)…'),
      findsOneWidget,
    );

    await leaveScreen(tester);
  });

  testWidgets('records each answer against its own question, with its rank',
      (tester) async {
    final container = await pumpScreen(tester);

    await tester.tap(find.text('fd'));
    await tester.pump();
    // The second question's "No" — the second occurrence in layout order.
    await tester.tap(find.text('No').last);
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Practitioner notes (optional)…'),
      'Client reported mild tingling.',
    );
    await tester.pump();

    // Leaving the screen by any route logs the session with what was answered.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    final entry =
        container.read(pendingOutcomesProvider.notifier).getById('session-1');
    final answers = entry?.answers;
    expect(answers, isNotNull);
    expect(answers!.notes, 'Client reported mild tingling.');

    final recorded = answers.answersByProtocol[protocolName];
    expect(recorded, isNotNull);
    expect(recorded!.length, 2);

    final mobility =
        recorded.firstWhere((a) => a.question == 'Did your mobility improve?');
    expect(mobility.answer, 'fd');
    expect(mobility.rank, 3);

    final health =
        recorded.firstWhere((a) => a.question == 'Did your health improve?');
    expect(health.answer, 'No');
    expect(health.rank, 2);
  });

  testWidgets('a stopped-early session records no outcome, but keeps remarks',
      (tester) async {
    final container = await pumpScreen(tester, stoppedEarly: true);

    expect(find.textContaining('Did your mobility improve?'), findsNothing);
    expect(find.text('REMARKS'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Practitioner notes (optional)…'),
      'Stopped on request.',
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    final answers =
        container.read(pendingOutcomesProvider.notifier).getById('session-1')?.answers;
    expect(answers?.answersByProtocol, isEmpty);
    expect(answers?.notes, 'Stopped on request.');
  });
}
