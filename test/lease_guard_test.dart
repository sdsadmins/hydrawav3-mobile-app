import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/clients/domain/client_model.dart';
import 'package:hydrawav3/features/clients/presentation/providers/client_providers.dart';
import 'package:hydrawav3/features/clients/presentation/providers/lease_guard.dart';

/// Which unit is on lease to whom — what Session Plan checks at Start.
void main() {
  const malik = Client(
    id: 'malik',
    clientName: 'Malik Carter',
    leaseId: 'L-malik',
    leaseActive: true,
    macAddress: '74:4D:BD:A0:A3:ED',
  );
  const dandre = Client(
    id: 'dandre',
    clientName: "D'Andre Cole",
    leaseId: 'L-dandre',
    macAddress: '74:4D:BD:A0:A3:10', // pending: not on the unit yet
  );
  const sofia = Client(id: 'sofia', clientName: 'Sofia Reyes');

  Future<Map<String, Client>> leases() async {
    final c = ProviderContainer(overrides: [
      clientListProvider.overrideWith((ref) async => [malik, dandre, sofia]),
    ]);
    addTearDown(c.dispose);
    c.listen(activeLeasesByMacProvider, (_, __) {});
    await c.read(clientListProvider.future);
    return c.read(activeLeasesByMacProvider);
  }

  test('an active lease is found by the unit\'s MAC', () async {
    final l = await leases();
    expect(leaseHolderOf(l, ['74:4D:BD:A0:A3:ED'])?.id, 'malik');
  });

  test('…and by its ±1 Bluetooth neighbours, any case', () async {
    final l = await leases();
    expect(leaseHolderOf(l, ['74:4d:bd:a0:a3:ee'])?.id, 'malik');
    expect(leaseHolderOf(l, ['74:4D:BD:A0:A3:EC'])?.id, 'malik');
  });

  test('the firmware MAC is checked when the Bluetooth id is not a MAC',
      () async {
    final l = await leases();
    // iOS: an opaque UUID, then the firmware-reported MAC
    expect(
        leaseHolderOf(l, ['3F2A9C1E-0000-4B1C-9A11-77D1C0FFEE00', '74:4D:BD:A0:A3:ED'])
            ?.id,
        'malik');
  });

  test('a pending lease or no lease does not block the unit', () async {
    final l = await leases();
    expect(leaseHolderOf(l, ['74:4D:BD:A0:A3:10']), isNull); // pending
    expect(leaseHolderOf(l, ['11:22:33:44:55:66']), isNull); // no lease
    expect(leaseHolderOf(l, [null, '']), isNull);
  });
}
