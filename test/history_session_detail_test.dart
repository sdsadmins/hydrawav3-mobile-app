import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/clients/presentation/providers/client_providers.dart';
import 'package:hydrawav3/features/history/domain/session_history_model.dart';
import 'package:hydrawav3/features/history/presentation/screens/session_detail_screen.dart';
import 'package:hydrawav3/features/session_coach/domain/session_coach_models.dart';

void main() {
  testWidgets('Session Coach details appear before the restore action',
      (tester) async {
    final session = SessionHistoryItem(
      id: 'session-1',
      clientType: 'client',
      clientId: 'client-1',
      sessionType: 'session_coach',
      sessionCoach: const SessionCoachRun(
        sessionCoachId: 'coach-1',
        bodyPartId: 'body-1',
        bodyPartName: 'Knee',
        supportType: 'Support recovery',
        sets: [
          SessionCoachRunSet(
            index: 0,
            setId: 'set-1',
            name: 'Calf',
            protocolId: 'protocol-1',
            protocolName: 'Recovery',
            macAddress: 'AA:BB:CC',
            startDelay: 5,
          ),
          SessionCoachRunSet(
            index: 1,
            setId: 'set-2',
            name: 'Above knee',
            // A Plus coach selection keeps the template ID while the intake
            // protocol metadata stores protocol[0]'s ID.
            protocolId: 'plus-template-2',
            protocolName: 'Activation',
            macAddress: 'DD:EE:FF',
            startDelay: 20,
          ),
        ],
      ),
      protocols: const [
        HistoryProtocol(
          protocol: 'Recovery',
          protocolId: 'protocol-1',
          macAddress: 'AA:BB:CC',
          advancedSettings: {
            'vibrationMode': 'Sweep',
            'lights': true,
          },
        ),
        HistoryProtocol(
          protocol: 'Activation',
          protocolId: 'protocol-2',
          macAddress: 'DD:EE:FF',
          advancedSettings: {
            'vibrationMode': 'Single',
            'hotPercent': 70,
          },
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [clientListProvider.overrideWith((ref) async => [])],
      child: MaterialApp(
        home: SessionDetailScreen(sessionId: 'session-1', item: session),
      ),
    ));
    await tester.pumpAndSettle();

    for (final detail in [
      'SESSION COACH DETAILS',
      'Body area',
      'Knee',
      'Support recovery',
      'Set 1 · Calf',
      'Set 2 · Above knee',
      'protocol-1',
      'AA:BB:CC',
      '5s',
      'plus-template-2',
      'DD:EE:FF',
      '20s',
    ]) {
      expect(find.text(detail), findsOneWidget);
    }
    expect(find.text('Recovery'), findsNWidgets(2));
    expect(find.text('Sweep'), findsNothing);
    expect(find.text('Single'), findsNothing);

    final loadButton = find.text('Load in Session Coach');
    expect(loadButton, findsOneWidget);
    expect(
      tester.getTopLeft(loadButton).dy,
      greaterThan(tester.getTopLeft(find.text('Set 1 · Calf')).dy),
    );

    final settingsChips = find.widgetWithText(ActionChip, 'Advanced settings');
    expect(settingsChips, findsNWidgets(2));
    await tester.ensureVisible(settingsChips.first);
    await tester.tap(settingsChips.first);
    await tester.pumpAndSettle();
    expect(find.text('Sweep'), findsOneWidget);
    expect(find.text('On'), findsOneWidget);
    expect(find.text('Single'), findsNothing);
    expect(find.text('70'), findsNothing);

    await tester.ensureVisible(settingsChips.last);
    await tester.tap(settingsChips.last);
    await tester.pumpAndSettle();
    expect(find.text('Sweep'), findsOneWidget);
    expect(find.text('Single'), findsOneWidget);
    expect(find.text('70'), findsOneWidget);
  });
}
