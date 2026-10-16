import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/features/auth/domain/auth_models.dart';
import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';
import 'package:hydrawav3/features/clients/domain/client_model.dart';
import 'package:hydrawav3/features/clients/presentation/providers/client_providers.dart';
import 'package:hydrawav3/features/clients/presentation/screens/users_screen.dart';
import 'package:hydrawav3/features/devices/presentation/providers/players_provider.dart';
import 'package:hydrawav3/features/history/data/history_repository.dart';
import 'package:hydrawav3/features/notifications/presentation/providers/notification_provider.dart';

class _FakeAuth extends StateNotifier<AuthState> implements AuthNotifier {
  _FakeAuth()
      : super(const AuthState(
          isAuthenticated: true,
          isInitialized: true,
          selectedOrgId: '1',
          selectedOrgName: 'Gulf Coast Tarpons',
          user: UserProfile(id: '7', firstName: 'Marcus'),
        ));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Users tab (v6 `#scr-players`): title, bell, "Add client / athlete" pill,
/// org chip, segments, search, roster.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [const Size(390, 844), const Size(1024, 1366)]) {
    final tag = size.width > 600 ? 'tablet' : 'phone';

    testWidgets('users tab header and roster ($tag)', (tester) async {
      final fonts = Platform.environment['ROBOTO_DIR'];
      if (fonts != null) {
        final l = FontLoader('Roboto');
        for (final f in ['regular', 'medium', 'bold', 'black']) {
          l.addFont(Future.value(ByteData.view(
              File('$fonts/roboto-$f.ttf').readAsBytesSync().buffer)));
        }
        await l.load();
        await (FontLoader('MaterialIcons')
              ..addFont(Future.value(ByteData.view(
                  File('$fonts/materialicons-regular.otf')
                      .readAsBytesSync()
                      .buffer))))
            .load();
      }
      final prefs = await SharedPreferences.getInstance();
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authStateProvider.overrideWith((ref) => _FakeAuth()),
          clientListProvider.overrideWith((ref) async => const [
                Client(id: 'c1', clientName: 'Malik Carter', age: 24),
                Client(id: 'c2', clientName: "D'Andre Cole", gender: 'Male'),
                Client(id: 'c3', clientName: 'Sofia Reyes'),
              ]),
          allSessionsProvider.overrideWith((ref) async => const []),
          orgSportsProvider.overrideWith((ref) async => const []),
          unreadNotificationCountProvider.overrideWith((ref) => 2),
        ],
        child: MaterialApp(
          builder: (context, child) => RepaintBoundary(child: child),
          home: const UsersScreen(),
        ),
      ));
      for (var k = 0; k < 4; k++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(find.text('Clients'), findsWidgets);
      expect(find.text('Add client / athlete'), findsOneWidget);
      expect(find.text('3 users · Gulf Coast Tarpons'), findsOneWidget);
      expect(find.text('AI Reports'), findsOneWidget);
      expect(find.text('Search clients'), findsOneWidget);
      expect(find.text('Malik Carter'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final dir = Platform.environment['SHOTS'];
      if (dir != null) {
        final ro = tester.renderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary).first);
        await tester.runAsync(() async {
          final img = await ro.toImage(pixelRatio: 1);
          final d = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$dir/users_$tag.png')
              .writeAsBytesSync(d!.buffer.asUint8List());
        });
      }
    });
  }
}
