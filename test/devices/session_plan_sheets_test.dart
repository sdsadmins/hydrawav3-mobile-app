/// The three Session Plan sheets (client picker, intake forms, protocol
/// picker) on phone and tablet: same choices and results, no overflow.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrawav3/features/clients/domain/client_model.dart';
import 'package:hydrawav3/features/clients/presentation/providers/client_providers.dart';
import 'package:hydrawav3/features/clients/presentation/widgets/new_client_sheet.dart';
import 'package:hydrawav3/features/devices/presentation/providers/players_provider.dart';
import 'package:hydrawav3/features/devices/presentation/screens/device_list_screen.dart';
import 'package:hydrawav3/features/devices/presentation/widgets/players_section.dart';
import 'package:hydrawav3/features/protocols/domain/protocol_model.dart';
import 'package:hydrawav3/features/protocols/presentation/providers/protocol_provider.dart';

class _FakeRecents extends StateNotifier<List<String>> implements RecentProtocolIdsController {
  _FakeRecents() : super(['p2', 'p5', 'p3']);
  @override
  Future<void> recordUsed(String protocolId) async {}
}

void main() {
  final clients = [
    const Client(id: 'c1', clientName: 'Malik Carter', age: 24, gender: 'Male', nickname: 'MC'),
    const Client(id: 'c2', clientName: 'Dana Whitfield-Oyelaran', age: 41, gender: 'Female'),
    const Client(id: 'c3', clientName: 'Jaylen Brooks', age: 19),
  ];
  const protos = [
    ProtocolSelectionOption(id: 'p1', templateName: 'Post-Workout Recovery Stack', description: 'Flush → Restore → Settle', goalTagName: 'Recovery', durationSeconds: 1680),
    ProtocolSelectionOption(id: 'p2', templateName: 'Performance Activation', description: 'Wake the system before training', goalTagName: 'Performance & Readiness', durationSeconds: 540),
    ProtocolSelectionOption(id: 'p3', templateName: 'Deep Relaxation', description: 'Long, slow parasympathetic settle', goalTagName: 'Calm', durationSeconds: 1200),
    ProtocolSelectionOption(id: 'p4', templateName: 'Elite Lymphatic Protocol', description: 'Included in a higher plan', goalTagName: 'Recovery', durationSeconds: 900, active: false),
    ProtocolSelectionOption(id: 'p5', templateName: 'SensoryGentle 9', description: 'Ultra-gentle intensity', goalTagName: 'Mobility', durationSeconds: 540),
  ];
  const goals = [GoalTagOption(id: 'g1', name: 'Recovery'), GoalTagOption(id: 'g2', name: 'Performance & Readiness'), GoalTagOption(id: 'g3', name: 'Calm'), GoalTagOption(id: 'g4', name: 'Mobility')];
  const sports = [OrgSport(mappingId: 'm', sportId: 's1', name: 'Football', isActive: true, positions: [Position(id: 'a', name: 'Quarterback'), Position(id: 'b', name: 'Running Back'), Position(id: 'c', name: 'Wide Receiver'), Position(id: 'd', name: 'Tight End'), Position(id: 'e', name: 'Linebacker')])];


  Future<(BuildContext, WidgetRef)> host(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    late BuildContext ctx;
    late WidgetRef wref;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        clientListProvider.overrideWith((ref) async => clients),
        selectedClientProvider.overrideWith((ref) => clients[0]),
        sessionClientModeProvider.overrideWith((ref) => ClientMode.client),
        orgSportsProvider.overrideWith((ref) async => sports),
        goalTagListProvider.overrideWith((ref) async => goals),
        protocolSelectionOptionsProvider.overrideWith((ref, g) async => g == null
            ? protos
            : protos.where((p) => p.goalTagName == goals.firstWhere((x) => x.id == g).name).toList()),
        recentProtocolIdsProvider.overrideWith((ref) => _FakeRecents()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (c, r, _) {
            ctx = c;
            wref = r;
            return const SizedBox.expand();
          }),
        ),
      ),
    ));
    return (ctx, wref);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  for (final size in [const Size(320, 700), const Size(834, 1112)]) {
    final label = size.width > 600 ? 'tablet' : 'phone';

    testWidgets('client picker searches and picks ($label)', (tester) async {
      final (ctx, ref) = await host(tester, size);
      showClientSelectSheet(ctx, ref);
      await settle(tester);
      expect(find.text('Guest'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'dana');
      await settle(tester);
      expect(find.text('Guest'), findsNothing);
      expect(find.text('Jaylen Brooks'), findsNothing);
      await tester.tap(find.text('Dana Whitfield-Oyelaran'));
      await settle(tester);
      expect(ref.read(selectedClientProvider)?.id, 'c2');
      expect(tester.takeException(), isNull);
    });

    testWidgets('intake forms lay out ($label)', (tester) async {
      final (ctx, ref) = await host(tester, size);
      showNewClientSheet(ctx, ref);
      await settle(tester);
      expect(find.text('Create client'), findsOneWidget);
      expect(tester.takeException(), isNull);
      Navigator.of(ctx).pop();
      await settle(tester);
      showAddPlayerSheet(ctx, ref);
      await settle(tester);
      expect(find.text('Quarterback'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('protocol picker filters and picks ($label)', (tester) async {
      final (ctx, _) = await host(tester, size);
      final result = debugShowProtocolPicker(ctx, currentId: 'p2', unitName: 'Unit 1');
      await settle(tester);
      expect(find.text('Unit 1 · protocol'), findsOneWidget);
      expect(find.text('SELECTED'), findsOneWidget);
      expect(find.textContaining('Deep Relaxation  ·  20 min', findRichText: true),
          findsOneWidget);
      await tester.ensureVisible(find.text('Calm'));
      await tester.pump();
      await tester.tap(find.text('Calm'));
      await settle(tester);
      expect(find.textContaining('Post-Workout Recovery Stack', findRichText: true), findsNothing);
      await tester.ensureVisible(find.text('All'));
      await tester.pump();
      await tester.tap(find.text('All'));
      await settle(tester);
      // locked stays open
      await tester.ensureVisible(find.textContaining('Elite Lymphatic Protocol', findRichText: true));
      await tester.tap(find.textContaining('Elite Lymphatic Protocol', findRichText: true));
      await settle(tester);
      expect(find.text('Unit 1 · protocol'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'sensory');
      await settle(tester);
      await tester.tap(find.text('SELECT').first);
      await settle(tester);
      expect(await result, 'p5');
      expect(tester.takeException(), isNull);
    });
  }
}
