import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ble_repository.dart';

final bleScanResultsProvider = StreamProvider<List<ScanResult>>((ref) {
  final repo = ref.read(bleRepositoryProvider);
  return repo.scanResults;
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
