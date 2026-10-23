// [FIX-24] Insufficient tokens on session start.
//
// A backend 400 whose `message` says "insufficient token" / "no remaining
// token" is the token/subscription rejection
// (lib/features/session/services/session_sync_service.dart):
//   - isTokenOrSubscriptionError(e) is true;
//   - SessionSyncService.startServerSession THROWS InsufficientTokensException
//     (instead of the tolerant `null`), which the launch path catches so the
//     engine is never started;
//   - the user sees "Start failed: Insufficient tokens. Please top up your
//     subscription to start a session." (`'Start failed: $e'`, the exception's
//     toString is its message).
//
// The full launch (device_list_screen → launchSession → engine) needs BLE and
// a live SessionEngine, so the "engine not started" half is pinned at the
// service boundary: the start call throws before a sessionId can be returned,
// and no second request follows.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/core/network/dio_client.dart';
import 'package:hydrawav3/core/storage/secure_storage.dart';
import 'package:hydrawav3/features/ble/data/ble_repository.dart';
import 'package:hydrawav3/features/devices/presentation/providers/wifi_devices_provider.dart';
import 'package:hydrawav3/features/session/services/session_sync_service.dart';

import '../helpers/fake_http.dart';

DioException _dio(int status, Object? body) => DioException(
      requestOptions: RequestOptions(path: '/sessions/start'),
      response: Response(
        requestOptions: RequestOptions(path: '/sessions/start'),
        statusCode: status,
        data: body,
      ),
      type: DioExceptionType.badResponse,
    );

class _FakeStorage implements SecureStorageService {
  @override
  Future<String?> getAccessToken() async => 'Bearer t';
  @override
  Future<String?> getUserId() async => '7';
  @override
  Future<String?> getSelectedOrgId() async => '1';
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _FakeBle implements BleRepository {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

const kExpectedMessage =
    'Insufficient tokens. Please top up your subscription to start a session.';

void main() {
  group('[FIX-24] isTokenOrSubscriptionError', () {
    test('[FIX-24] a 400 mentioning "insufficient token" is a token error', () {
      expect(
        isTokenOrSubscriptionError(_dio(400, {
          'statusCode': 400,
          'message': 'Insufficient tokens for this organization',
          'error': 'Bad Request',
        })),
        isTrue,
      );
      // Case-insensitive, and Nest's List<String> message shape.
      expect(
        isTokenOrSubscriptionError(_dio(400, {
          'message': ['INSUFFICIENT TOKEN balance'],
        })),
        isTrue,
      );
    });

    test('[FIX-24] a 400 mentioning "no remaining token" is a token error', () {
      expect(
        isTokenOrSubscriptionError(
          _dio(400, {'message': 'No remaining tokens for the session'}),
        ),
        isTrue,
      );
      // Plain string body too.
      expect(
        isTokenOrSubscriptionError(_dio(400, 'no remaining token')),
        isTrue,
      );
    });

    test('[FIX-24] other 400s and non-400s are NOT token errors', () {
      expect(
        isTokenOrSubscriptionError(
          _dio(400, {'message': 'devices must contain at least 1 element'}),
        ),
        isFalse,
      );
      expect(
        isTokenOrSubscriptionError(_dio(500, {'message': 'insufficient token'})),
        isFalse,
      );
      expect(
        isTokenOrSubscriptionError(_dio(401, {'message': 'no remaining token'})),
        isFalse,
      );
    });
  });

  group('[FIX-24] InsufficientTokensException', () {
    test('[FIX-24] carries the top-up message and reads as "Start failed: …"',
        () {
      const e = InsufficientTokensException();
      expect(e.message, kExpectedMessage);
      expect(e.toString(), kExpectedMessage);
      // The screens surface it as `'Start failed: $e'`.
      expect(
        'Start failed: $e',
        'Start failed: Insufficient tokens. Please top up your subscription '
        'to start a session.',
      );
    });
  });

  group('[FIX-24] startServerSession', () {
    late FakeHttp server;
    late ProviderContainer container;

    setUp(() {
      server = FakeHttp();
      container = ProviderContainer(overrides: [
        nodeDioProvider.overrideWithValue(server.dio()),
        secureStorageProvider.overrideWithValue(_FakeStorage()),
        bleRepositoryProvider.overrideWithValue(_FakeBle()),
        wifiDevicesByOrgProvider.overrideWith((ref) async => const []),
      ]);
      addTearDown(container.dispose);
    });

    const spec = NormalDeviceSpec(
      localMac: 'AA:BB:CC:DD:EE:01',
      protocolId: 'p1',
      protocolName: 'Recovery Flush',
      advancedSettings: {},
      totalDurationSeconds: 600,
    );

    test('[FIX-24] a token 400 throws InsufficientTokensException, once', () async {
      server.on(
        'POST',
        'sessions/start',
        (_) => FakeReply.json(400, {
          'statusCode': 400,
          'message': 'Insufficient tokens. No remaining token for this org.',
          'error': 'Bad Request',
        }),
      );

      final sync = container.read(sessionSyncServiceProvider);
      await expectLater(
        sync.startServerSession(devices: [spec], transport: 'wifi'),
        throwsA(isA<InsufficientTokensException>()
            .having((e) => e.message, 'message', kExpectedMessage)),
      );
      // Exactly one start attempt; nothing else was sent for this device.
      expect(server.requestsTo('sessions/start', method: 'POST'), hasLength(1));
      expect(server.requests, hasLength(1));
    });

    test('[FIX-24] any other failure stays tolerant (null, no throw)', () async {
      server.onJson('POST', 'sessions/start', {'message': 'boom'}, status: 500);
      final sync = container.read(sessionSyncServiceProvider);
      final id = await sync.startServerSession(
        devices: [spec],
        transport: 'wifi',
      );
      expect(id, isNull);
    });
  });
}
