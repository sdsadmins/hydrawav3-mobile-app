import 'package:flutter_test/flutter_test.dart';
import 'package:hydrawav3/features/clients/domain/client_model.dart';

/// The device-lease fields on [Client] (`leaseId`, `leaseActive`,
/// `macAddress`, `leaseDate`, `isActive`) and the derived lease states the
/// lease card keys off. Mirrors the backend `client.schema.ts`.
void main() {
  group('Client.fromJson lease fields', () {
    test('reads a live lease from the server shape', () {
      final c = Client.fromJson(const {
        '_id': '6a72cf3c2e55905f23f250f9',
        'clientName': 'home-user',
        'leaseId': '6a72cf3c2e55905f23f250f9a4269267',
        'leaseActive': true,
        'macAddress': 'AA:BB:CC:DD:EE:FF',
        'leaseDate': '2026-08-10T04:54:35.000Z',
        'isActive': true,
      });

      expect(c.id, '6a72cf3c2e55905f23f250f9');
      expect(c.leaseId, '6a72cf3c2e55905f23f250f9a4269267');
      expect(c.leaseActive, isTrue);
      expect(c.macAddress, 'AA:BB:CC:DD:EE:FF');
      expect(c.leaseDate, DateTime.utc(2026, 8, 10, 4, 54, 35));
      expect(c.isActive, isTrue);
      expect(c.isLeaseActive, isTrue);
      expect(c.isLeasePending, isFalse);
    });

    test('a client with no lease defaults to inactive with null fields', () {
      final c = Client.fromJson(const {'_id': 'c1', 'clientName': 'Sofia'});

      expect(c.leaseId, isNull);
      expect(c.leaseActive, isFalse);
      expect(c.macAddress, isNull);
      expect(c.leaseDate, isNull);
      expect(c.isActive, isFalse);
      expect(c.isLeaseActive, isFalse);
      expect(c.isLeasePending, isFalse);
    });

    test('leaseActive / isActive accept bool, number and string forms', () {
      bool active(dynamic v) =>
          Client.fromJson({'_id': 'c', 'leaseActive': v}).leaseActive;

      expect(active(true), isTrue);
      expect(active(1), isTrue);
      expect(active('true'), isTrue);
      expect(active('TRUE'), isTrue);
      expect(active(false), isFalse);
      expect(active(0), isFalse);
      expect(active('false'), isFalse);
      expect(active('yes'), isFalse); // only "true" counts
      expect(active(null), isFalse);

      expect(Client.fromJson(const {'_id': 'c', 'isActive': 1}).isActive,
          isTrue);
    });

    test('a non-string leaseId is stringified', () {
      final c = Client.fromJson(const {'_id': 'c', 'leaseId': 12345});
      expect(c.leaseId, '12345');
    });

    test('an unparseable leaseDate reads as null rather than throwing', () {
      final c = Client.fromJson(const {'_id': 'c', 'leaseDate': 'not a date'});
      expect(c.leaseDate, isNull);
    });

    test('id falls back to `id` when `_id` is absent', () {
      expect(Client.fromJson(const {'id': 'c9'}).id, 'c9');
    });
  });

  group('lease state', () {
    test('pending = registered (leaseId + MAC) but not yet active', () {
      const pending = Client(
        id: 'c1',
        clientName: 'x',
        leaseId: 'L1',
        macAddress: 'AA:BB:CC:DD:EE:FF',
      );
      expect(pending.isLeasePending, isTrue);
      expect(pending.isLeaseActive, isFalse);
    });

    test('not pending without both a leaseId and a MAC', () {
      const noMac = Client(id: 'c', clientName: 'x', leaseId: 'L1');
      const noLease =
          Client(id: 'c', clientName: 'x', macAddress: 'AA:BB:CC:DD:EE:FF');
      const blank =
          Client(id: 'c', clientName: 'x', leaseId: '', macAddress: '');
      expect(noMac.isLeasePending, isFalse);
      expect(noLease.isLeasePending, isFalse);
      expect(blank.isLeasePending, isFalse);
    });

    test('an active lease is never also pending', () {
      const live = Client(
        id: 'c',
        clientName: 'x',
        leaseId: 'L1',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        leaseActive: true,
      );
      expect(live.isLeaseActive, isTrue);
      expect(live.isLeasePending, isFalse);
    });
  });

  group('copyWith', () {
    const player = Client(
      id: 'p1',
      clientName: 'Tyreek Hall',
      organizationId: 493,
      memberType: 'Player',
      sport: 'Football',
      jerseyNumber: 10,
      positions: ['pos1'],
    );

    test('a lease update keeps the player fields', () {
      final leased = player.copyWith(
        leaseId: 'L1',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        leaseActive: true,
        leaseDate: DateTime.utc(2026, 8, 10),
      );

      expect(leased.leaseId, 'L1');
      expect(leased.macAddress, 'AA:BB:CC:DD:EE:FF');
      expect(leased.leaseActive, isTrue);
      expect(leased.leaseDate, DateTime.utc(2026, 8, 10));
      // Previously copyWith dropped these and turned a player into a client.
      expect(leased.id, 'p1');
      expect(leased.organizationId, 493);
      expect(leased.isPlayer, isTrue);
      expect(leased.sport, 'Football');
      expect(leased.jerseyNumber, 10);
      expect(leased.positions, ['pos1']);
    });

    test('deactivating keeps the registration so it reads as pending', () {
      final live = player.copyWith(
        leaseId: 'L1',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        leaseActive: true,
      );
      final off = live.copyWith(leaseActive: false);
      expect(off.isLeaseActive, isFalse);
      expect(off.isLeasePending, isTrue);
    });
  });
}
