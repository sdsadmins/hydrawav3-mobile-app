import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/features/clients/domain/client_model.dart';
import 'package:hydrawav3/features/clients/presentation/providers/client_providers.dart';
import 'package:hydrawav3/features/clients/presentation/screens/client_detail_screen.dart';
import 'package:hydrawav3/features/ai_report/data/ai_report_repository.dart';
import 'package:hydrawav3/features/clients/data/client_repository.dart';
import 'package:hydrawav3/features/history/data/history_repository.dart';
import 'package:hydrawav3/features/history/domain/session_history_model.dart';

/// The player portfolio — the spec's `openPlayer(id)` (app.js:1756). This was
/// a 51-line stub (AppBar + lease + reports) before; these pin the parts that
/// close the gap.
/// The portfolio embeds the lease card and the report list, both of which
/// fetch on mount. Stub them so the tests measure the portfolio and leave no
/// request in flight.
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const client = Client(
    id: 'c1',
    clientName: 'Tyreek Hall',
    sport: 'Football',
    jerseyNumber: 10,
    age: 27,
    memberType: 'Player',
  );

  Future<void> pump(
    WidgetTester tester, {
    List<SessionHistoryItem> history = const [],
  }) async {
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          clientListProvider.overrideWith((ref) async => [client]),
          clientHistoryProvider('c1').overrideWith((ref) async => history),
          clientRepositoryProvider
              .overrideWithValue(_FakeClientRepo(client)),
          aiReportRepositoryProvider.overrideWithValue(_FakeReportRepo()),
        ],
        child: const MaterialApp(
          home: ClientDetailScreen(clientId: 'c1', title: 'Tyreek Hall'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('shows who the person is and the two placement actions',
      (tester) async {
    await pump(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Tyreek Hall'), findsOneWidget);
    // Sport · #jersey · age — none of which the old screen displayed.
    expect(find.text('Football · #10 · 27 yrs'), findsOneWidget);
    expect(find.text('⚡ Performance'), findsOneWidget);
    expect(find.text('〰 Recovery'), findsOneWidget);
    expect(find.text('Sessions'), findsOneWidget);
  });

  testWidgets('an unassessed client reads em-dash, not a fabricated 0%',
      (tester) async {
    await pump(tester, history: [
      SessionHistoryItem(id: 's1', clientId: 'c1', createdAt: DateTime.now()),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.text('1'), findsWidgets); // one session
    expect(find.text('—'), findsOneWidget); // improvement unknown
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('computes the improvement rate from before/after scores',
      (tester) async {
    await pump(tester, history: [
      SessionHistoryItem(
        id: 's1',
        clientId: 'c1',
        createdAt: DateTime.now(),
        protocols: const [HistoryProtocol(protocol: 'Short Session')],
        discomfortAreas: const [
          HistoryDiscomfort(
              bodyPart: 'Hamstring', discomfortBefore: 6, discomfortAfter: 3),
          HistoryDiscomfort(
              bodyPart: 'Calf', discomfortBefore: 4, discomfortAfter: 4),
        ],
      ),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.text('50%'), findsOneWidget); // 1 of 2 areas improved
    expect(find.text('Short Session'), findsOneWidget);
    expect(find.text('improved ✓'), findsOneWidget);
  });

  testWidgets('says so when there is no history yet', (tester) async {
    await pump(tester);

    expect(
      find.textContaining('No sessions logged yet'),
      findsOneWidget,
    );
  });

  test('copyWith keeps roster fields', () {
    // Regression: copyWith used to carry only lease fields, so copying a
    // player silently erased memberType/sport/jerseyNumber/positions.
    final copied = client.copyWith(leaseActive: true);
    expect(copied.memberType, 'Player');
    expect(copied.sport, 'Football');
    expect(copied.jerseyNumber, 10);
    expect(copied.age, 27);
    expect(copied.leaseActive, isTrue);
  });
}
