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

final startScanProvider = Provider<Future<void> Function()>((ref) {
  return () => ref.read(bleRepositoryProvider).startScan();
});

final stopScanProvider = Provider<Future<void> Function()>((ref) {
  return () => ref.read(bleRepositoryProvider).stopScan();
});
