import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../session/presentation/providers/busy_devices_provider.dart';
import '../../domain/client_model.dart';
import 'client_providers.dart';

/// Which client holds an ACTIVE lease on which unit: every MAC variant (the
/// unit's ±1 last-byte neighbours included, see [macAddressVariants]) → the
/// lease holder. A unit loaded with a lease (`setLeaseID`) only runs a session
/// that carries that lease's key, so the app has to know before Start.
///
/// A pending lease (registered, not yet loaded onto the unit) isn't here: the
/// unit doesn't hold it yet and still runs for anyone.
final activeLeasesByMacProvider = Provider.autoDispose<Map<String, Client>>((ref) {
  final clients = ref.watch(clientListProvider).valueOrNull ?? const <Client>[];
  final byMac = <String, Client>{};
  for (final c in clients) {
    final mac = (c.macAddress ?? '').trim();
    if (!c.isLeaseActive || mac.isEmpty) continue;
    for (final v in macAddressVariants(mac)) {
      byMac[v] = c;
    }
  }
  return byMac;
});

/// The lease holder of the unit known by any of [ids] (its Bluetooth id, the
/// firmware-reported MAC…), or null when the unit isn't on lease.
Client? leaseHolderOf(Map<String, Client> leases, Iterable<String?> ids) {
  for (final id in ids) {
    final mac = (id ?? '').trim();
    if (mac.isEmpty) continue;
    for (final v in macAddressVariants(mac)) {
      final holder = leases[v];
      if (holder != null) return holder;
    }
  }
  return null;
}

/// Unit id → the lease key to send with that unit's start command. Session
/// Plan fills it at Start for a unit whose lease holder is the client the
/// session is for, so the unit accepts the run; every other unit gets none.
final sessionLeaseKeysProvider =
    StateProvider<Map<String, String>>((ref) => const {});
