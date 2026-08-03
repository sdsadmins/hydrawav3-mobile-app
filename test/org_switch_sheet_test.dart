import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/features/auth/presentation/screens/select_organization_page.dart'
    show organizationProvider;
import 'package:hydrawav3/features/auth/presentation/widgets/org_switch_sheet.dart';

/// The Hub's org chip switches organization in place via a sheet — the spec
/// deliberately keeps the practitioner on the Hub instead of sending them to
/// another tab (`orgSwitchSheet()`, app.js:2010).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpSheet(
    WidgetTester tester,
    List<Map<String, dynamic>> orgs,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          organizationProvider.overrideWith((ref) async => orgs),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showOrgSwitchSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('lists every organization and marks the active one',
      (tester) async {
    await pumpSheet(tester, [
      {'id': 1, 'name': 'Miami Dolphins', 'description': 'NFL team'},
      {'id': 2, 'name': 'Ellison Recovery', 'description': 'Private practice'},
    ]);

    expect(tester.takeException(), isNull);
    expect(find.text('Switch organization'), findsOneWidget);
    expect(find.text('Miami Dolphins'), findsOneWidget);
    expect(find.text('Ellison Recovery'), findsOneWidget);
    expect(find.text('NFL team'), findsOneWidget);
    expect(find.text('Add organization'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // No org selected in this harness, so nothing claims to be active.
    expect(find.text('Active'), findsNothing);
  });

  testWidgets('offers a way out when the practitioner has no organization',
      (tester) async {
    await pumpSheet(tester, []);

    expect(tester.takeException(), isNull);
    expect(find.text('You are not part of an organization yet.'),
        findsOneWidget);
    // Never a dead end — Principles §7.
    expect(find.text('Create one'), findsOneWidget);
  });

  testWidgets('Cancel dismisses the sheet', (tester) async {
    await pumpSheet(tester, [
      {'id': 1, 'name': 'Miami Dolphins'},
    ]);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Switch organization'), findsNothing);
  });
}
