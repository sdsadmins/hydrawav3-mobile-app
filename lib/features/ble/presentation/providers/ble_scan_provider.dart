import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ble_repository.dart';

final bleScanResultsProvider = StreamProvider<List<ScanResult>>((ref) async* {
  final repo = ref.read(bleRepositoryProvider);
  // Seed with the latest known results so a screen that subscribes between scan
  // ticks (e.g. during the auto-restart gap) immediately reflects devices the
  // background scan already found, instead of an empty list until the next tick.
  yield repo.currentScanResults;
  yield* repo.scanResults;
});

final isScanningProvider = Provider<bool>((ref) {
  return ref.read(bleRepositoryProvider).isScanning;
});

/// Reactive scanning state sourced directly from the BLE adapter so UI can
/// reflect start/stop transitions live (unlike [isScanningProvider], which is
/// read once).
final bleIsScanningProvider = StreamProvider<bool>((ref) {
  return FlutterBluePlus.isScanning;
});

final startScanProvider = Provider<Future<void> Function()>((ref) {
  return () => ref.read(bleRepositoryProvider).startScan();
});

final stopScanProvider = Provider<Future<void> Function()>((ref) {
  return () => ref.read(bleRepositoryProvider).stopScan();
});
