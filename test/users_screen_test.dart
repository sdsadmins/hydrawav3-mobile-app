import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/core/theme/text_scale_provider.dart';
import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';
import 'package:hydrawav3/features/clients/domain/client_model.dart';
import 'package:hydrawav3/features/clients/presentation/providers/client_providers.dart';
import 'package:hydrawav3/features/clients/presentation/screens/users_screen.dart';
import 'package:hydrawav3/features/devices/presentation/providers/players_provider.dart';
import 'package:hydrawav3/features/history/data/history_repository.dart';
import 'package:hydrawav3/features/notifications/presentation/providers/notification_provider.dart';

import 'helpers/fakes.dart';
import 'helpers/pump_app.dart';
import 'helpers/qa_snap.dart';

/// Users tab (v6 `#scr-players`): title, bell, "Add client / athlete" pill,
/// org chip, segments, search, roster.
///
/// Runs with the real Roboto metrics: the header row used to overflow by
/// ~27px on a phone, and the narrow-phone case pins the fix (the add pill now
/// ellipsizes before the row can overflow).
void main() {
  setUpAll(loadAppFonts);

  // The header row (title, bell, "Add client / athlete" pill) used to
  // overflow when the pill's label outgrew the row: ~27px on a phone with the
  // test font, and on a narrow phone at the largest in-app text size.
  qaTestWidgets('users header fits at the largest text size (smallPhone)',
      (tester) async {
    await _pumpUsers(tester, QaDevice.smallPhone, textScale: kMaxTextScale);
    expect(find.text('Add client / athlete'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // The page title stays whole; the pill's label is what gives way.
    final title =
        tester.renderObject<RenderParagraph>(find.text('Clients').first);
    expect(title.didExceedMaxLines, isFalse);
  });

  for (final device in QaDevice.values) {
    qaTestWidgets('users tab header and roster (${device.name})',
        (tester) async {
      await _pumpUsers(tester, device);

      expect(find.text('Clients'), findsWidgets);
      expect(find.text('Add client / athlete'), findsOneWidget);
      expect(find.text('3 users · Gulf Coast Tarpons'), findsOneWidget);
      expect(find.text('AI Reports'), findsOneWidget);
      expect(find.text('Search clients'), findsOneWidget);
      expect(find.text('Malik Carter'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpUsers(
  WidgetTester tester,
  QaDevice device, {
  double textScale = 1.0,
}) async {
  await pumpApp(
    tester,
    const UsersScreen(),
    device: device,
    textScale: textScale,
    overrides: [
      authStateProvider
          .overrideWith((ref) => FakeAuth(orgName: 'Gulf Coast Tarpons')),
      clientListProvider.overrideWith((ref) async => const [
            Client(id: 'c1', clientName: 'Malik Carter', age: 24),
            Client(id: 'c2', clientName: "D'Andre Cole", gender: 'Male'),
            Client(id: 'c3', clientName: 'Sofia Reyes'),
          ]),
      allSessionsProvider.overrideWith((ref) async => const []),
      orgSportsProvider.overrideWith((ref) async => const []),
      unreadNotificationCountProvider.overrideWith((ref) => 2),
    ],
  );
  await pumpFrames(tester, step: const Duration(milliseconds: 200));
}
