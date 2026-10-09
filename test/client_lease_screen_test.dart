import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/auth/domain/auth_models.dart';
import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';
import 'package:hydrawav3/features/clients/data/client_repository.dart';
import 'package:hydrawav3/features/clients/domain/client_model.dart';
import 'package:hydrawav3/features/clients/presentation/providers/lease_controller.dart';
import 'package:hydrawav3/features/clients/presentation/screens/client_lease_screen.dart';

class _FakeAuth extends StateNotifier<AuthState> implements AuthNotifier {
  _FakeAuth(String orgType)
      : super(AuthState(
          isAuthenticated: true,
          isInitialized: true,
          selectedOrgId: '1',
          user: UserProfile(
              id: '7', firstName: 'Marcus', organizationType: orgType),
        ));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeClientRepo implements ClientRepository {
  final Client client;
  _FakeClientRepo(this.client);
  @override
  Future<Client> getById(String clientId) async => client;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeLease extends StateNotifier<LeaseFlowState>
    implements LeaseController {
  _FakeLease() : super(const LeaseFlowState());
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _inactive = Client(id: 'c1', clientName: 'Tyreek Hall');
const _pending = Client(
    id: 'c1',
    clientName: 'Tyreek Hall',
    leaseId: 'LS-4821',
    macAddress: '48:CA:43:B0:02:B1');
final _active = Client(
    id: 'c1',
    clientName: 'Tyreek Hall',
    leaseId: 'LS-4821',
    macAddress: '48:CA:43:B0:02:B1',
    leaseActive: true,
    leaseDate: DateTime(2026, 9, 28));

/// "Player hand-off" / "Client hand-off": the v6 header + "What a lease does"
/// card over the unchanged lease flow, on phone and tablet.
void main() {
  Future<void> pump(WidgetTester tester, Size size, Client client,
      {String org = 'UNIVERSITY'}) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        authStateProvider.overrideWith((ref) => _FakeAuth(org)),
        clientRepositoryProvider.overrideWithValue(_FakeClientRepo(client)),
        leaseControllerProvider.overrideWith((ref) => _FakeLease()),
      ],
      child: const MaterialApp(
        home: RepaintBoundary(
          child: ClientLeaseScreen(clientId: 'c1', title: 'Tyreek Hall'),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  for (final size in [const Size(320, 800), const Size(834, 1112)]) {
    final tag = size.width > 600 ? 'tablet' : 'phone';

    testWidgets('header + explainer, register form ($tag)', (tester) async {
      await pump(tester, size, _inactive);
      expect(find.text('Player hand-off'), findsOneWidget);
      expect(find.text('Tyreek Hall · device lease'), findsOneWidget);
      expect(find.text('What a lease does'), findsOneWidget);
      expect(find.text('Client mode'), findsOneWidget);
      expect(find.textContaining('so Tyreek Hall can take it home'),
          findsOneWidget);
      expect(find.text('No lease registered for this client yet.'),
          findsOneWidget);

      await tester.tap(find.text('Activate Lease'));
      await tester.pump();
      for (final t in ['Pick a unit to hand off', 'Save Lease', 'Cancel']) {
        await tester.ensureVisible(find.text(t));
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('pending and active states keep every action ($tag)',
        (tester) async {
      await pump(tester, size, _pending);
      for (final t in [
        'Lease: Pending',
        'LS-4821',
        '48:CA:43:B0:02:B1',
        'Load Lease ID to Device',
        'Change device / re-enter details',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      await pump(tester, size, _active);
      for (final t in [
        'Lease: Active',
        'Lease ID',
        'Reset Password',
        'Deactivate',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('clinic accounts read Client hand-off', (tester) async {
    await pump(tester, const Size(390, 844), _inactive, org: 'CLINIC');
    expect(find.text('Client hand-off'), findsOneWidget);
    expect(find.text('Player hand-off'), findsNothing);
  });

  // Screenshots for review: LEASE_SHOTS=<dir> flutter test test/client_lease_screen_test.dart
  final shots = Platform.environment['LEASE_SHOTS'];
  if (shots != null) {
    testWidgets('render', (tester) async {
      final fonts = Platform.environment['ROBOTO_DIR']!;
      final loader = FontLoader('Roboto');
      for (final f in ['regular', 'medium', 'bold', 'black']) {
        final bytes = File('$fonts/roboto-$f.ttf').readAsBytesSync();
        loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      }
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(
            File('$fonts/materialicons-regular.otf').readAsBytesSync().buffer)));
      await icons.load();

      Future<void> shoot(String name, Size size, Client c,
          {bool openForm = false}) async {
        await pump(tester, size, c);
        if (openForm) {
          await tester.tap(find.text('Activate Lease'));
          await tester.pump();
        }
        final ro = tester.renderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary).first);
        await tester.runAsync(() async {
          final img = await ro.toImage(pixelRatio: 2);
          final data = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$shots/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
        });
      }

      await shoot('lease_form_390', const Size(390, 900), _inactive,
          openForm: true);
      await shoot('lease_form_834', const Size(834, 1112), _inactive,
          openForm: true);
      await shoot('lease_active_390', const Size(390, 900), _active);
      await shoot('lease_pending_834', const Size(834, 1112), _pending);
    });
  }
}
