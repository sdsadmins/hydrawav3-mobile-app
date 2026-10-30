import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/features/ai_report/data/ai_report_repository.dart';
import 'package:hydrawav3/features/clients/data/client_repository.dart';
import 'package:hydrawav3/features/clients/domain/client_model.dart';
import 'package:hydrawav3/features/clients/presentation/providers/client_providers.dart';
import 'package:hydrawav3/features/clients/presentation/screens/client_detail_screen.dart';
import 'package:hydrawav3/features/history/data/history_repository.dart';

class _FakeClientRepo implements ClientRepository {
  final Client client;
  _FakeClientRepo(this.client);

  @override
  Future<Client> getById(String clientId) async => client;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeReportRepo implements AiReportRepository {
  @override
  Future<List<Map<String, dynamic>>> list({
    String? userId,
    int? organizationId,
    int page = 1,
    int limit = 10,
  }) async =>
      [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The detail screen's device lease: only a client without a lease is
/// offered "Hand off a unit"; one with a lease sees it — active or pending —
/// and manages it.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, Client client) async {
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        clientListProvider.overrideWith((ref) async => [client]),
        clientHistoryProvider('c1').overrideWith((ref) async => const []),
        clientRepositoryProvider.overrideWithValue(_FakeClientRepo(client)),
        aiReportRepositoryProvider.overrideWithValue(_FakeReportRepo()),
      ],
      child: const MaterialApp(
        home: ClientDetailScreen(clientId: 'c1', title: 'Tyreek Hall'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('no lease: offered a hand-off', (tester) async {
    await pump(tester, const Client(id: 'c1', clientName: 'Tyreek Hall'));
    expect(find.text('Hand off a unit'), findsOneWidget);
    expect(find.text('Device lease'), findsNothing);
  });

  testWidgets('active lease: shown with its unit, managed — no hand-off',
      (tester) async {
    await pump(
        tester,
        Client(
          id: 'c1',
          clientName: 'Tyreek Hall',
          leaseId: 'L1',
          leaseActive: true,
          macAddress: '74:4D:BD:A0:A3:ED',
          leaseDate: DateTime(2026, 10, 20),
        ));
    expect(find.text('Hand off a unit'), findsNothing);
    expect(find.text('Device lease'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Unit 74:4D:BD:A0:A3:ED · since Oct 20, 2026'),
        findsOneWidget);
    expect(find.text('Manage lease'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending lease: shown as pending, finish the hand-off',
      (tester) async {
    await pump(
        tester,
        const Client(
          id: 'c1',
          clientName: 'Tyreek Hall',
          leaseId: 'L1',
          macAddress: '74:4D:BD:A0:A3:ED',
        ));
    expect(find.text('Hand off a unit'), findsNothing);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Registered to unit 74:4D:BD:A0:A3:ED — not on the unit yet'),
        findsOneWidget);
    expect(find.text('Finish hand-off'), findsOneWidget);
  });
}
