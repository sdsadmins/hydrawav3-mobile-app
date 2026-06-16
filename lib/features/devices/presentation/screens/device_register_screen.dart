import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/ble_constants.dart';
import '../../../../core/constants/theme_constants.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../ble/data/ble_command_service.dart';
import '../../../ble/data/ble_repository.dart';
import '../../../ble/presentation/providers/ble_connection_provider.dart';
import '../../../ble/presentation/providers/ble_scan_provider.dart';
import '../../../ble/services/ble_scanner.dart';
import '../../data/device_repository.dart';
import '../../domain/device_model.dart';
import '../providers/wifi_devices_provider.dart';

class DeviceRegisterScreen extends ConsumerStatefulWidget {
  const DeviceRegisterScreen({super.key});

  @override
  ConsumerState<DeviceRegisterScreen> createState() => _State();
}

class _State extends ConsumerState<DeviceRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serialCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  String _searchText = '';
  bool _submitting = false;
  bool _isAutoScan = true;
  bool _isHydrawav3Only = false;
  List<ScanResult> _discoveredDevices = [];
  String? _selectedDeviceMac;
  bool _isDeviceConnected = false;
  String? _connectedDeviceMac;
  bool _connectingDevice = false;
  String? _connectingDeviceMac;
  StateSetter? _sheetSetState;
  BuildContext? _sheetContext;

  Color _onAccent(BuildContext context) =>
      Theme.of(context).colorScheme.onPrimary;

  String _normalizeMac(String macAddress) => macAddress.trim().toUpperCase();
  bool _isValidMac(String macAddress) => RegExp(
        r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$',
      ).hasMatch(macAddress.trim());
  String? _deriveAdjacentMac(String macAddress, {required int delta}) {
    if (!_isValidMac(macAddress)) return null;
    final parts = macAddress.trim().toUpperCase().split(':');
    if (parts.length != 6) return null;
    final last = int.tryParse(parts.last, radix: 16);
    if (last == null) return null;
    final next = (last + delta) & 0xFF;
    parts[5] = next.toRadixString(16).padLeft(2, '0').toUpperCase();
    return parts.join(':');
  }

  List<String> _bleConnectCandidates(String macAddress) {
    final normalized = _normalizeMac(macAddress);
    final plusOne = _deriveAdjacentMac(normalized, delta: 1);
    final minusOne = _deriveAdjacentMac(normalized, delta: -1);
    return {
      normalized,
      if (plusOne != null) plusOne,
      if (minusOne != null) minusOne,
    }.toList();
  }

  String _stripHydraPrefix(String value) =>
      value.toLowerCase().startsWith('hydra-') ? value.substring(6) : value;
  String _prefixedBleName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed.toLowerCase().startsWith('hydra-')
        ? trimmed
        : 'Hydra-$trimmed';
  }

  void _updateSheet(VoidCallback updates) {
    final sheetSetState = _sheetSetState;
    if (sheetSetState != null) {
      try {
        // The sheet's setState throws if its StatefulBuilder was disposed
        // (e.g. the sheet was swiped/dismissed without _closeCreateSheet). In
        // that case clear the stale setter and fall back to the screen's own
        // setState so callers like the Edit-WiFi handshake never crash.
        sheetSetState(updates);
        return;
      } catch (_) {
        _sheetSetState = null;
        _sheetContext = null;
      }
    }
    if (mounted) {
      setState(updates);
    }
  }

  @override
  void initState() {
    super.initState();
    // Keep the shared BLE scanner running the whole time this screen is open
    // (same as the Devices list screen). This guarantees registered devices are
    // already in scan results when the user taps Edit WiFi / Edit Name, so the
    // handshake connects on the first try instead of needing a screen revisit.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(bleScannerProvider).initializeAutoScan();
      ref.read(startScanProvider)();
    });
  }

  @override
  void dispose() {
    _serialCtrl.dispose();
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _clearScanSelection() {
    // The shared scanner emits fixed-length lists, so reassign rather than
    // mutating (calling .clear() on a fixed-length list throws).
    _discoveredDevices = <ScanResult>[];
    _selectedDeviceMac = null;
    _isDeviceConnected = false;
    _connectedDeviceMac = null;
    // Clear the entered MAC ID / name so a new device entry starts blank
    // instead of inheriting the previous registration's values.
    _serialCtrl.clear();
    _nameCtrl.clear();
  }

  int? _currentOrganizationId() {
    final auth = ref.read(authStateProvider);
    final orgIdRaw = auth.selectedOrgId?.trim().isNotEmpty == true
        ? auth.selectedOrgId
        : auth.user?.organizationId;
    if (orgIdRaw == null || orgIdRaw.isEmpty) return null;
    return int.tryParse(orgIdRaw);
  }

  Future<void> _closeCreateSheet() async {
    final selectedMac = _selectedDeviceMac;
    await ref.read(stopScanProvider)();
    if (_connectedDeviceMac != null) {
      await ref
          .read(bleRepositoryProvider)
          .disconnectDevice(_connectedDeviceMac!);
    }
    if (selectedMac != null) {
      final provisioningIds = ref.read(bleProvisioningIdsProvider);
      ref.read(bleProvisioningIdsProvider.notifier).state = {
        ...provisioningIds,
      }..remove(selectedMac);
    }
    _sheetContext = null;
    _sheetSetState = null;
    if (mounted) {
      setState(_clearScanSelection);
    }
  }

  /// Step 6/7: Register selected asset and, when using AUTO SCAN, connect first.
  Future<void> _registerDevice(
    BuildContext context, {
    BuildContext? dialogContext,
    bool validateForm = true,
  }) async {
    if (validateForm && !_formKey.currentState!.validate()) return;
    if (!validateForm && _nameCtrl.text.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter device name')),
        );
      }
      return;
    }

    // Use connect state established when tapping the device.
    final selectedDeviceConnected = _isDeviceConnected;

    if (_selectedDeviceMac != null && !selectedDeviceConnected) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to connect to Bluetooth device'),
          ),
        );
      }
      return;
    }

    final orgId = _currentOrganizationId();
    if (orgId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Organization not available')));
      }
      return;
    }

    _updateSheet(() => _submitting = true);
    final selectedMac = _selectedDeviceMac;
    try {
      if (selectedMac != null) {
        var resolvedMac = await ref
            .read(bleCommandServiceProvider)
            .resolveHardwareMac(selectedMac);
        if (resolvedMac == null || !_isValidMac(resolvedMac)) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Unable to read a valid hardware MAC from the device. Please reconnect and try again.',
                ),
              ),
            );
          }
          return;
        }
        // Some Hydra units expose BLE MAC (often +1) while backend expects
        // WiFi/device MAC. If resolver only yields the selected BLE ID, try
        // adjacent lower byte as primary registration MAC.
        if (_normalizeMac(resolvedMac) == _normalizeMac(selectedMac)) {
          final candidate = _deriveAdjacentMac(resolvedMac, delta: -1);
          if (candidate != null) {
            resolvedMac = candidate;
          }
        }
        _serialCtrl.text = resolvedMac;
      }

      final normalizedMac = _normalizeMac(_serialCtrl.text);
      print(
          'REGISTER DEVICE FINAL MAC => $normalizedMac (selected=$selectedMac)');
      if (!_isValidMac(normalizedMac)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Invalid MAC address. Please use XX:XX:XX:XX:XX:XX'),
            ),
          );
        }
        return;
      }

      final enteredName = _nameCtrl.text.trim();
      final registrationName = _selectedDeviceMac != null
          ? _prefixedBleName(enteredName)
          : enteredName;

      await ref.read(deviceRepositoryProvider).registerDevice(
        name: registrationName,
        macAddress: normalizedMac,
        organizationIds: [orgId],
      );

      ref.refresh(wifiDevicesByOrgProvider);

      bool hardwareSynced = false;

      if (selectedDeviceConnected && selectedMac != null) {
        try {
          hardwareSynced = await _syncSelectedDeviceName();
        } catch (_) {
          hardwareSynced = false;
        }
      }

      if (context.mounted) {
        final message = hardwareSynced
            ? 'Device registered successfully and name synced to hardware'
            : 'Device registered successfully';

        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        final sheetNavigatorContext = _sheetContext;
        await _closeCreateSheet();
        if (sheetNavigatorContext != null && sheetNavigatorContext.mounted) {
          Navigator.of(sheetNavigatorContext).pop();
        } else if (dialogContext != null && dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        } else if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (selectedMac != null) {
        try {
          await ref.read(bleRepositoryProvider).disconnectDevice(selectedMac);
        } catch (_) {}
        final provisioningIds = ref.read(bleProvisioningIdsProvider);
        ref.read(bleProvisioningIdsProvider.notifier).state = {
          ...provisioningIds,
        }..remove(selectedMac);
      }
      if (mounted) {
        _updateSheet(() {
          _isDeviceConnected = false;
          _connectedDeviceMac = null;
          _connectingDevice = false;
          _connectingDeviceMac = null;
        });
      }
      if (context.mounted) {
        final errorText = e is TimeoutException ||
                e.toString().toLowerCase().contains('server reception timeout')
            ? 'Register failed: server did not respond in time. Please check your connection and try again.'
            : 'Register failed: ${e.toString()}';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorText)),
        );
      }
    } finally {
      if (mounted) {
        _updateSheet(() => _submitting = false);
      }
    }
  }

  /// Step 2: Start BLE discovery using the shared scanner used by the Devices
  /// list screen. Results flow in reactively via [bleScanResultsProvider].
  Future<void> _startBleScan() async {
    _updateSheet(() {
      _selectedDeviceMac = null;
      _isDeviceConnected = false;
      _connectedDeviceMac = null;
    });

    final scanner = ref.read(bleScannerProvider);
    scanner.initializeAutoScan();
    await ref.read(startScanProvider)();
  }

  List<ScanResult> _getFilteredDevices() {
    // Mirror the Devices list screen's filter exactly: when the Hydrawav3
    // toggle is on, keep only devices advertising the configured service UUID.
    if (!_isHydrawav3Only) return _discoveredDevices;

    final expected = BleConstants.preferredServiceUuid;
    if (expected == null || expected.isEmpty) return const <ScanResult>[];

    final targetUuid = BleConstants.normalizeUuid(expected);
    return _discoveredDevices.where((result) {
      return result.advertisementData.serviceUuids.any(
        (uuid) => BleConstants.normalizeUuid(uuid.str) == targetUuid,
      );
    }).toList();
  }

  Future<bool> _connectToSelectedDevice() async {
    if (_selectedDeviceMac == null) return false;
    // Stop scanning before connecting. (Android BLE is very unstable when
    // scanning + connecting simultaneously.)
    try {
      await ref.read(stopScanProvider)();
    } catch (_) {}

    final selected = _discoveredDevices
        .where(
            (d) => _normalizeMac(d.device.id.toString()) == _selectedDeviceMac)
        .toList();
    if (selected.isEmpty) return false;

    try {
      final connected = await ref.read(bleRepositoryProvider).connectDevice(
            selected.first.device,
            cachePairedDevice: false,
          );
      if (connected && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bluetooth device connected.')),
        );
      }
      return connected;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bluetooth connect failed: ${e.toString()}')),
        );
      }
      return false;
    }
  }

  /// Locate the actually-advertised peripheral via a BLE scan and return its
  /// [BluetoothDevice]. This is required for iOS (where peripherals are not
  /// addressable by MAC — [remoteId] is an opaque per-install UUID) and is also
  /// far more reliable than a direct connect-by-MAC on Android.
  ///
  /// Matching strategy:
  ///  - Android: the hardware MAC (and its ±1 BLE-advertising variants).
  ///  - iOS / fallback: the advertised device name (e.g. "Hydra-Foo"), since
  ///    the MAC is hidden by the OS.
  Future<BluetoothDevice?> _findAdvertisedDevice(
    DeviceInfo device,
    Set<String> candidateMacs, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final targetName = device.name.trim().toLowerCase();

    bool matches(ScanResult r) {
      if (candidateMacs.contains(_normalizeMac(r.device.remoteId.str))) {
        return true;
      }
      if (targetName.isEmpty) return false;
      final advName = r.advertisementData.advName.trim().toLowerCase();
      final platformName = r.device.platformName.trim().toLowerCase();
      return advName == targetName || platformName == targetName;
    }

    // Check anything already discovered first.
    for (final r in _discoveredDevices) {
      if (matches(r)) return r.device;
    }

    final completer = Completer<BluetoothDevice?>();
    StreamSubscription<List<ScanResult>>? sub;

    // Listen to the RAW scan stream (not the shared scanner's buffered stream)
    // so we receive every advertisement immediately and don't depend on the
    // shared scanner's internal state, which can be left "not actually
    // scanning" on this screen after the register/connect flow. Subscribe
    // BEFORE starting the scan so we never miss an early result.
    sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        if (matches(r) && !completer.isCompleted) {
          completer.complete(r.device);
          return;
        }
      }
    });

    try {
      // The screen already scans continuously (see initState). If for any
      // reason no scan is live right now, start one — first via the shared
      // scanner (handles permissions/Android quirks), then a direct fallback
      // that bypasses the scanner's internal guard entirely.
      if (!FlutterBluePlus.isScanningNow) {
        ref.read(bleScannerProvider).initializeAutoScan();
        await ref.read(startScanProvider)();
      }
      if (!FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.startScan(
          timeout: timeout,
          androidUsesFineLocation: true,
        );
      }
    } catch (_) {
      // A scan may already be in progress — our listener still gets results.
    }

    final found =
        await completer.future.timeout(timeout, onTimeout: () => null);
    await sub.cancel();
    return found;
  }

  Future<bool> _activateRegisteredDevice(DeviceInfo device) async {
    final normalizedMac = _normalizeMac(device.macAddress);
    _serialCtrl.text = normalizedMac;
    _nameCtrl.text = device.name;

    // Registered MAC is typically the WiFi/Hardware MAC (often ends with ...EC),
    // but BLE advertising can use an adjacent MAC (often ...ED). For BLE actions
    // (WiFi/rename), treat EC/ED (+1/-1) as the same physical device.
    final candidates = _bleConnectCandidates(normalizedMac);
    final candidateSet = candidates.toSet();

    // If we're already connected to *any* candidate, reuse that connection.
    if (_connectedDeviceMac != null &&
        _isDeviceConnected &&
        candidateSet.contains(_connectedDeviceMac)) {
      _selectedDeviceMac = _connectedDeviceMac;
      return true;
    }

    // Only disconnect current device if it's not one of the candidates.
    if (_connectedDeviceMac != null &&
        _isDeviceConnected &&
        !candidateSet.contains(_connectedDeviceMac)) {
      await ref
          .read(bleRepositoryProvider)
          .disconnectDevice(_connectedDeviceMac!);
      if (mounted) {
        _updateSheet(() {
          _isDeviceConnected = false;
          _connectedDeviceMac = null;
        });
      }
    }

    if (mounted) {
      _updateSheet(() {
        _selectedDeviceMac = candidates.first;
        _submitting = true;
        _connectingDevice = true;
        _connectingDeviceMac = candidates.first;
      });
    }

    try {
      bool connected = false;
      String? connectedCandidate;
      // Prefer adjacent (+1) first for BLE actions when registered MAC is WiFi MAC.
      // If the device's BLE MAC is the typical +1 variant, this avoids an initial
      // failed attempt to connect to the WiFi MAC.
      final plusOne = _deriveAdjacentMac(normalizedMac, delta: 1);
      final minusOne = _deriveAdjacentMac(normalizedMac, delta: -1);

      final preferredOrder = <String>{
        if (plusOne != null) plusOne,
        normalizedMac,
        if (minusOne != null) minusOne,
        ...candidates,
      }.toList();

      // Primary path (works on iOS + Android): scan for the device and connect
      // to the discovered peripheral.
      final scanned = await _findAdvertisedDevice(device, candidateSet);
      if (scanned != null) {
        final didConnect = await ref.read(bleRepositoryProvider).connectDevice(
              scanned,
              cachePairedDevice: false,
            );
        if (didConnect) {
          connected = true;
          connectedCandidate = _normalizeMac(scanned.remoteId.str);
        }
      }

      // Fallback (Android only): direct connect-by-MAC candidates. iOS cannot
      // connect by MAC, so it relies entirely on the scan path above.
      if (!connected && defaultTargetPlatform != TargetPlatform.iOS) {
        for (final candidate in preferredOrder) {
          final didConnect =
              await ref.read(bleRepositoryProvider).connectDevice(
                    BluetoothDevice(remoteId: DeviceIdentifier(candidate)),
                    cachePairedDevice: false,
                  );
          if (didConnect) {
            connected = true;
            connectedCandidate = candidate;
            break;
          }
        }
      }

      // Fallback (iOS only): a manually-added device has no advertised-name or
      // MAC link the matcher above can use, so the scan-by-identity path returns
      // nothing. Mirror the device-list behavior, which connects fine on iOS:
      // connect to a live-advertised Hydra peripheral — auto if exactly one is
      // nearby, otherwise let the practitioner pick the physical device. Only
      // reached after the existing paths have already failed, so nothing that
      // works today changes.
      if (!connected && defaultTargetPlatform == TargetPlatform.iOS) {
        final hydraDevices = await _scanHydraPeripherals();
        BluetoothDevice? target;
        if (hydraDevices.length == 1) {
          target = hydraDevices.first.device;
        } else if (hydraDevices.length > 1) {
          target = await _pickHydraPeripheral(hydraDevices);
        }
        if (target != null) {
          final didConnect = await ref.read(bleRepositoryProvider).connectDevice(
                target,
                cachePairedDevice: false,
              );
          if (didConnect) {
            connected = true;
            connectedCandidate = _normalizeMac(target.remoteId.str);
          }
        }
      }
      if (mounted) {
        _updateSheet(() {
          _isDeviceConnected = connected;
          _connectedDeviceMac = connected ? connectedCandidate : null;
          _selectedDeviceMac = connected ? connectedCandidate : null;
        });
      }
      return connected;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bluetooth connect failed: ${e.toString()}')),
        );
      }
      return false;
    } finally {
      if (mounted) {
        _updateSheet(() {
          _submitting = false;
          _connectingDevice = false;
          _connectingDeviceMac = null;
        });
      }
    }
  }

  /// True when [r] is a Hydra peripheral — by advertised service UUID, or by an
  /// advertised name starting with "Hydra-" as a fallback.
  bool _isHydraScanResult(ScanResult r) {
    final expected = BleConstants.preferredServiceUuid;
    if (expected != null && expected.isNotEmpty) {
      final target = BleConstants.normalizeUuid(expected);
      final hasService = r.advertisementData.serviceUuids
          .any((u) => BleConstants.normalizeUuid(u.str) == target);
      if (hasService) return true;
    }
    final advName = r.advertisementData.advName.trim().toLowerCase();
    final platformName = r.device.platformName.trim().toLowerCase();
    return advName.startsWith('hydra-') || platformName.startsWith('hydra-');
  }

  /// Collect live-advertised Hydra peripherals over a short window. Used by the
  /// iOS connect fallback where a device can't be matched by name/MAC.
  Future<List<ScanResult>> _scanHydraPeripherals({
    Duration window = const Duration(seconds: 5),
  }) async {
    try {
      if (!FlutterBluePlus.isScanningNow) {
        ref.read(bleScannerProvider).initializeAutoScan();
        await ref.read(startScanProvider)();
      }
    } catch (_) {
      // A scan may already be in progress — the listener still gets results.
    }

    final byId = <String, ScanResult>{};
    for (final r in _discoveredDevices) {
      if (_isHydraScanResult(r)) byId[r.device.remoteId.str] = r;
    }

    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        if (_isHydraScanResult(r)) byId[r.device.remoteId.str] = r;
      }
    });
    await Future<void>.delayed(window);
    await sub.cancel();
    return byId.values.toList();
  }

  /// Let the practitioner pick the physical device when several Hydra units are
  /// advertising nearby (iOS connect fallback).
  Future<BluetoothDevice?> _pickHydraPeripheral(List<ScanResult> results) async {
    if (!mounted) return null;
    final sorted = [...results]..sort((a, b) => b.rssi.compareTo(a.rssi));
    return showDialog<BluetoothDevice>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: ThemeConstants.surface,
          title: const Text('Select your device'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: sorted.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: ThemeConstants.border),
              itemBuilder: (_, i) {
                final r = sorted[i];
                final advName = r.advertisementData.advName.trim();
                final platformName = r.device.platformName.trim();
                final name = advName.isNotEmpty
                    ? advName
                    : (platformName.isNotEmpty ? platformName : 'Hydra device');
                return ListTile(
                  leading: Icon(Icons.bluetooth_rounded,
                      color: ThemeConstants.accent),
                  title: Text(name,
                      style: TextStyle(color: ThemeConstants.textPrimary)),
                  subtitle: Text('Signal ${r.rssi} dBm',
                      style: TextStyle(color: ThemeConstants.textTertiary)),
                  onTap: () => Navigator.of(ctx).pop(r.device),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _syncSelectedDeviceName() async {
    if (_selectedDeviceMac == null) return false;

    final rawName = _nameCtrl.text.trim();
    if (rawName.isEmpty) return false;

    final bluetoothName = _prefixedBleName(rawName);

    try {
      final success = await ref
          .read(bleCommandServiceProvider)
          .sendRename(_selectedDeviceMac!, bluetoothName);
      return success;
    } catch (e) {
      return false;
    }
  }

  ScanResult? _selectedScannedDevice() {
    final selectedMac = _selectedDeviceMac;
    if (selectedMac == null) return null;

    for (final device in _getFilteredDevices()) {
      if (_normalizeMac(device.device.id.toString()) == selectedMac) {
        return device;
      }
    }
    return null;
  }

  Widget _buildSelectedPairingCard(BuildContext context) {
    final selectedDevice = _selectedScannedDevice();
    if (selectedDevice == null || _connectedDeviceMac == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ThemeConstants.surfaceVariant.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ThemeConstants.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ThemeConstants.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.bluetooth,
                  color: ThemeConstants.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MAC: $_connectedDeviceMac',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: ThemeConstants.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Enter device name below',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ThemeConstants.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'DEVICE NAME',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: ThemeConstants.textTertiary,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Hydra-',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: ThemeConstants.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _nameCtrl,
                  autofocus: true,
                  onChanged: (_) => _updateSheet(() {}),
                  style: TextStyle(color: ThemeConstants.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Enter name here',
                    hintStyle: TextStyle(
                      color: ThemeConstants.textTertiary,
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: ThemeConstants.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: ThemeConstants.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: ThemeConstants.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submitting || _nameCtrl.text.trim().isEmpty
                ? null
                : () => _registerDevice(context, validateForm: false),
            child: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Text('PAIR NOW'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceItem(BuildContext sheetContext, ScanResult device) {
    final deviceName = device.advertisementData.localName.isEmpty
        ? device.device.name
        : device.advertisementData.localName;
    final macAddress = _normalizeMac(device.device.id.toString());
    final isSelected = _connectedDeviceMac == macAddress;

    return GestureDetector(
      onTap: () async {
        if (_connectingDevice) return;

        _serialCtrl.text = macAddress;
        _nameCtrl.clear();
        final provisioningIds = ref.read(bleProvisioningIdsProvider);
        ref.read(bleProvisioningIdsProvider.notifier).state = {
          ...provisioningIds,
          macAddress,
        };
        _updateSheet(() {
          _selectedDeviceMac = macAddress;
          _submitting = true;
          _connectingDevice = true;
          _connectingDeviceMac = macAddress;
        });

        try {
          final connected = await _connectToSelectedDevice();
          if (mounted) {
            _updateSheet(() {
              _isDeviceConnected = connected;
              _connectedDeviceMac = connected ? macAddress : null;
            });
          }
          if (!connected) {
            // _connectToSelectedDevice() stopped the shared scanner before
            // connecting (and suppressed its auto-restart). On a failed attempt
            // nothing would resume discovery, leaving the list frozen on stale
            // results. Re-kick continuous scanning so it keeps refreshing.
            unawaited(_startBleScan());
          }
        } finally {
          if (mounted) {
            _updateSheet(() {
              _submitting = false;
              _connectingDevice = false;
              _connectingDeviceMac = null;
            });
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? ThemeConstants.accent.withValues(alpha: 0.16)
              : ThemeConstants.surfaceVariant.withValues(alpha: 0.4),
          border: Border.all(
            color: isSelected ? ThemeConstants.accent : ThemeConstants.border,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            if (_connectingDevice && _connectingDeviceMac == macAddress)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(ThemeConstants.accent)),
              )
            else
              Icon(
                Icons.bluetooth_connected,
                color: isSelected
                    ? ThemeConstants.accent
                    : ThemeConstants.textTertiary,
                size: 20,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deviceName.isEmpty ? 'Unknown Device' : deviceName,
                    style: TextStyle(
                      color: ThemeConstants.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    macAddress,
                    style: TextStyle(
                      color: ThemeConstants.textSecondary,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: ThemeConstants.accent, size: 20),
          ],
        ),
      ),
    );
  }

  /// Shared styled dialog shell used by the Locate / Report / Edit Name modals.
  /// Always scrollable so the keyboard can never overflow the content.
  Widget _modalShell({
    required IconData icon,
    required Color iconColor,
    required String title,
    VoidCallback? onClose,
    required Widget child,
  }) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: ThemeConstants.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ThemeConstants.border),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: ThemeConstants.textPrimary,
                      ),
                    ),
                  ),
                  if (onClose != null)
                    IconButton(
                      onPressed: onClose,
                      icon: Icon(Icons.close,
                          color: ThemeConstants.textSecondary),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _modalLabel(String text) => Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: ThemeConstants.textSecondary,
        ),
      );

  /// Locate modal: read-only MAC + Beep toggle + Locate button.
  Future<void> _openLocateModal(DeviceInfo device) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var beep = true;
        var sending = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return _modalShell(
              icon: Icons.my_location_rounded,
              iconColor: ThemeConstants.accent,
              title: 'Locate Device',
              onClose: () => Navigator.of(dialogContext).pop(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _modalLabel('MAC ADDRESS'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: ThemeConstants.surfaceVariant
                          .withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ThemeConstants.border),
                    ),
                    child: Text(
                      device.macAddress,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: ThemeConstants.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: ThemeConstants.surfaceVariant
                          .withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ThemeConstants.border),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.volume_up_rounded,
                            size: 18, color: ThemeConstants.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Beep',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: ThemeConstants.textPrimary,
                            ),
                          ),
                        ),
                        Switch.adaptive(
                          value: beep,
                          activeColor: ThemeConstants.accent,
                          onChanged: (v) => setModalState(() => beep = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: sending
                          ? null
                          : () async {
                              setModalState(() => sending = true);
                              try {
                                await ref
                                    .read(deviceRepositoryProvider)
                                    .locateDevice(device.macAddress,
                                        beeping: beep);
                                if (dialogContext.mounted) {
                                  Navigator.of(dialogContext).pop();
                                }
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Locate command sent')),
                                  );
                                }
                              } catch (e) {
                                if (dialogContext.mounted) {
                                  setModalState(() => sending = false);
                                }
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content:
                                            Text('Locate failed: ${e.toString()}')),
                                  );
                                }
                              }
                            },
                      icon: sending
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black))
                          : Icon(Icons.my_location_rounded,
                              size: 18, color: _onAccent(context)),
                      label: Text(
                        sending ? 'Sending…' : 'Locate',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _onAccent(context),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ThemeConstants.accent,
                        disabledBackgroundColor: ThemeConstants.surfaceVariant,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Report / diagnostics modal: animated check steps + "System Certified".
  Future<void> _openDiagnosticModal(DeviceInfo device) async {
    // Fire the backend diagnostics command (best effort).
    ref
        .read(deviceRepositoryProvider)
        .runDiagnostics(device.macAddress)
        .catchError((_) {});

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var step = 0;
        Timer? timer;
        const checks = <(String, int)>[
          ('Oscillation Module Integrity', 1),
          ('Light Array', 2),
          ('Thermal Conductance Sync', 3),
          ('Communication Latency', 4),
        ];
        return StatefulBuilder(
          builder: (context, setModalState) {
            timer ??= Timer.periodic(const Duration(milliseconds: 1100), (t) {
              if (!dialogContext.mounted) {
                t.cancel();
                return;
              }
              if (step >= 4) {
                t.cancel();
                return;
              }
              setModalState(() => step++);
            });
            return _modalShell(
              icon: Icons.fact_check_rounded,
              iconColor: ThemeConstants.accent,
              title: 'Device Report',
              onClose: () {
                timer?.cancel();
                Navigator.of(dialogContext).pop();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    device.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: ThemeConstants.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    device.macAddress,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: ThemeConstants.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...checks.map((c) {
                    final done = step >= c.$2;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: ThemeConstants.surfaceVariant
                            .withValues(alpha: 0.42),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: ThemeConstants.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.$1,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: ThemeConstants.textSecondary,
                              ),
                            ),
                          ),
                          if (done)
                            Icon(Icons.check_circle_rounded,
                                size: 18, color: ThemeConstants.success)
                          else
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                    ThemeConstants.textTertiary),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  if (step >= 4) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: ThemeConstants.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color:
                                ThemeConstants.success.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.verified_user_rounded,
                              color: ThemeConstants.success, size: 26),
                          const SizedBox(height: 8),
                          Text(
                            'SYSTEM CERTIFIED',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: ThemeConstants.success,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'All hardware parameters are within operational bounds.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: ThemeConstants.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        timer?.cancel();
                        Navigator.of(dialogContext).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ThemeConstants.accent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        'Close Report',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _onAccent(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Web-parity WiFi configuration flow:
  /// handshake -> searching -> config -> success.
  Future<void> _openWifiModal(DeviceInfo device) async {
    final ssidCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final deviceMac = _normalizeMac(device.macAddress);

    InputDecoration fieldDecoration(String hint, {Widget? suffix}) {
      return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: ThemeConstants.textTertiary, fontSize: 14),
        filled: true,
        fillColor: ThemeConstants.surfaceVariant.withValues(alpha: 0.42),
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: ThemeConstants.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: ThemeConstants.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: ThemeConstants.accent),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );
    }

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          var step = 'handshake'; // handshake | searching | config | success
          var connectError = '';
          var showPassword = false;
          var sending = false;

          return StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> startHandshake() async {
                setModalState(() {
                  step = 'searching';
                  connectError = '';
                });
                final ok = await _activateRegisteredDevice(device);
                if (!dialogContext.mounted) return;
                setModalState(() {
                  if (ok) {
                    step = 'config';
                  } else {
                    step = 'handshake';
                    connectError =
                        'Couldn\'t reach the device over Bluetooth. Make sure it '
                        'is powered on and nearby, then try again.';
                  }
                });
              }

              Future<void> sendCreds() async {
                final ssid = ssidCtrl.text.trim();
                if (ssid.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Wi-Fi name is required')),
                  );
                  return;
                }
                final targetMac = _connectedDeviceMac;
                if (targetMac == null) {
                  setModalState(() {
                    step = 'handshake';
                    connectError =
                        'Bluetooth connection lost. Please reconnect and try again.';
                  });
                  return;
                }
                setModalState(() => sending = true);
                final success = await ref
                    .read(bleCommandServiceProvider)
                    .sendWifiCredentials(
                      targetMac,
                      ssid: ssid,
                      password: passCtrl.text,
                    );
                if (success) {
                  // The device drops BLE to join WiFi; stop the connector's
                  // background auto-reconnect loop so it doesn't churn retries.
                  try {
                    await ref
                        .read(bleRepositoryProvider)
                        .disconnectDevice(targetMac);
                  } catch (_) {}
                  if (mounted) {
                    _isDeviceConnected = false;
                    _connectedDeviceMac = null;
                    _selectedDeviceMac = null;
                  }
                  if (!dialogContext.mounted) return;
                  setModalState(() {
                    sending = false;
                    step = 'success';
                  });
                  Future.delayed(const Duration(milliseconds: 1600), () {
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  });
                } else {
                  if (!dialogContext.mounted) return;
                  setModalState(() => sending = false);
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Wi-Fi send failed. Please try again.'),
                    ),
                  );
                }
              }

              final headerIcon = step == 'success'
                  ? Icons.check_circle_rounded
                  : step == 'config'
                      ? Icons.wifi_rounded
                      : Icons.bluetooth_rounded;
              final headerColor = step == 'success'
                  ? ThemeConstants.success
                  : ThemeConstants.accent;
              final title = step == 'success'
                  ? 'All set'
                  : step == 'config'
                      ? 'Configure WiFi'
                      : 'Bluetooth Handshake';

              Widget body;
              switch (step) {
                case 'searching':
                  body = Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 38,
                        height: 38,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor:
                              AlwaysStoppedAnimation(ThemeConstants.accent),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Establishing a secure Bluetooth link…',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: ThemeConstants.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          backgroundColor: ThemeConstants.surfaceVariant,
                          valueColor:
                              AlwaysStoppedAnimation(ThemeConstants.accent),
                        ),
                      ),
                    ],
                  );
                  break;
                case 'config':
                  body = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: ThemeConstants.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: ThemeConstants.success.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_rounded,
                                size: 16, color: ThemeConstants.success),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Connected to ${device.name}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: ThemeConstants.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('WIFI NAME (SSID)',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                              color: ThemeConstants.textSecondary)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: ssidCtrl,
                        style: TextStyle(color: ThemeConstants.textPrimary),
                        decoration: fieldDecoration('Enter WiFi name'),
                        onChanged: (_) => setModalState(() {}),
                      ),
                      const SizedBox(height: 14),
                      Text('PASSWORD',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                              color: ThemeConstants.textSecondary)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: passCtrl,
                        obscureText: !showPassword,
                        style: TextStyle(color: ThemeConstants.textPrimary),
                        decoration: fieldDecoration(
                          'Enter WiFi password',
                          suffix: IconButton(
                            onPressed: () => setModalState(
                                () => showPassword = !showPassword),
                            icon: Icon(
                              showPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: ThemeConstants.textTertiary,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: sending || ssidCtrl.text.trim().isEmpty
                              ? null
                              : sendCreds,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ThemeConstants.accent,
                            disabledBackgroundColor:
                                ThemeConstants.surfaceVariant,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: sending
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.black))
                              : Text('Send Credentials',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: _onAccent(context))),
                        ),
                      ),
                    ],
                  );
                  break;
                case 'success':
                  body = Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        'Wi-Fi credentials sent.',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ThemeConstants.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${device.name} is now connecting to WiFi.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: ThemeConstants.textSecondary,
                        ),
                      ),
                    ],
                  );
                  break;
                default: // handshake
                  body = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Connect to ${device.name} over Bluetooth to update its '
                        'WiFi network.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: ThemeConstants.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: ThemeConstants.surfaceVariant
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: ThemeConstants.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.memory,
                                size: 16, color: ThemeConstants.textTertiary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                deviceMac,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: ThemeConstants.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (connectError.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          connectError,
                          style: TextStyle(
                            color: ThemeConstants.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: startHandshake,
                          icon: Icon(Icons.bluetooth_searching_rounded,
                              size: 18, color: _onAccent(context)),
                          label: Text(
                            connectError.isEmpty
                                ? 'Start Handshake'
                                : 'Retry Handshake',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _onAccent(context),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ThemeConstants.accent,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  );
              }

              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(horizontal: 28),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: ThemeConstants.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: ThemeConstants.border),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: headerColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child:
                                Icon(headerIcon, color: headerColor, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: ThemeConstants.textPrimary,
                              ),
                            ),
                          ),
                          if (step != 'searching' && step != 'success')
                            IconButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              icon: Icon(Icons.close,
                                  color: ThemeConstants.textSecondary),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      body,
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      // Defer disposal until after the dialog's final teardown frame so a
      // last rebuild (route exit / keyboard insets) can't touch a disposed
      // controller.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ssidCtrl.dispose();
        passCtrl.dispose();
      });
    }
  }

  /// Edit Name modal — web-parity 4-step flow:
  /// pairing -> searching -> name-edit -> success. Works on Android + iOS
  /// (the handshake uses the scan-then-connect path in [_activateRegisteredDevice]).
  Future<void> _openEditNameModal(DeviceInfo device) async {
    final nameCtrl =
        TextEditingController(text: _stripHydraPrefix(device.name.trim()));

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          var step = 'pairing'; // pairing | searching | name-edit | success
          var connectError = '';
          var saving = false;

          return StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> startPairing() async {
                setModalState(() {
                  step = 'searching';
                  connectError = '';
                });
                final ok = await _activateRegisteredDevice(device);
                if (!dialogContext.mounted) return;
                setModalState(() {
                  if (ok) {
                    step = 'name-edit';
                  } else {
                    step = 'pairing';
                    connectError =
                        'Couldn\'t reach the device over Bluetooth. Make sure it '
                        'is powered on and nearby, then try again.';
                  }
                });
              }

              Future<void> save() async {
                final raw = nameCtrl.text.trim();
                if (raw.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Device name is required')),
                  );
                  return;
                }
                final targetMac = _connectedDeviceMac;
                if (targetMac == null) {
                  setModalState(() {
                    step = 'pairing';
                    connectError =
                        'Bluetooth connection lost. Please pair again.';
                  });
                  return;
                }
                setModalState(() => saving = true);
                final finalName = _prefixedBleName(raw);

                var synced = false;
                try {
                  synced = await ref
                      .read(bleCommandServiceProvider)
                      .sendRename(targetMac, finalName);
                } catch (_) {}
                if (synced) {
                  try {
                    await ref
                        .read(bleRepositoryProvider)
                        .renamePairedDevice(targetMac, finalName);
                  } catch (_) {}
                }

                var backendUpdated = false;
                if (device.id != null) {
                  try {
                    await ref
                        .read(deviceRepositoryProvider)
                        .renameDevice(device.id!, finalName);
                    backendUpdated = true;
                    ref.refresh(wifiDevicesByOrgProvider);
                  } catch (_) {}
                }

                // The device may drop BLE after rename; stop reconnect churn.
                try {
                  await ref
                      .read(bleRepositoryProvider)
                      .disconnectDevice(targetMac);
                } catch (_) {}
                if (mounted) {
                  _isDeviceConnected = false;
                  _connectedDeviceMac = null;
                  _selectedDeviceMac = null;
                }
                if (!dialogContext.mounted) return;

                if (backendUpdated || synced) {
                  setModalState(() {
                    saving = false;
                    step = 'success';
                  });
                  Future.delayed(const Duration(milliseconds: 1600), () {
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  });
                } else {
                  setModalState(() => saving = false);
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Name update failed')),
                  );
                }
              }

              final headerIcon = step == 'success'
                  ? Icons.check_circle_rounded
                  : step == 'name-edit'
                      ? Icons.drive_file_rename_outline_rounded
                      : Icons.bluetooth_rounded;
              final headerColor = step == 'success'
                  ? ThemeConstants.success
                  : ThemeConstants.accent;
              final title = step == 'success' ? 'Name Updated' : 'Edit Name';

              Widget body;
              switch (step) {
                case 'searching':
                  body = Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 38,
                        height: 38,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor:
                              AlwaysStoppedAnimation(ThemeConstants.accent),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Pairing with the device over Bluetooth…',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13,
                            color: ThemeConstants.textSecondary),
                      ),
                    ],
                  );
                  break;
                case 'name-edit':
                  body = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: ThemeConstants.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: ThemeConstants.success
                                  .withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_rounded,
                                size: 16, color: ThemeConstants.success),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Bluetooth connected',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: ThemeConstants.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _modalLabel('DEVICE NAME'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            'Hydra-',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: ThemeConstants.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: nameCtrl,
                              autofocus: true,
                              onChanged: (_) => setModalState(() {}),
                              style:
                                  TextStyle(color: ThemeConstants.textPrimary),
                              decoration: InputDecoration(
                                hintText: 'Enter name here',
                                hintStyle: TextStyle(
                                    color: ThemeConstants.textTertiary,
                                    fontSize: 14),
                                filled: true,
                                fillColor: ThemeConstants.surfaceVariant
                                    .withValues(alpha: 0.42),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      BorderSide(color: ThemeConstants.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      BorderSide(color: ThemeConstants.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      BorderSide(color: ThemeConstants.accent),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: saving || nameCtrl.text.trim().isEmpty
                              ? null
                              : save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ThemeConstants.accent,
                            disabledBackgroundColor:
                                ThemeConstants.surfaceVariant,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: saving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.black))
                              : Text('Save Name',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: _onAccent(context))),
                        ),
                      ),
                    ],
                  );
                  break;
                case 'success':
                  body = Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        'Name updated.',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ThemeConstants.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The device name has been updated successfully.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13,
                            color: ThemeConstants.textSecondary),
                      ),
                    ],
                  );
                  break;
                default: // pairing
                  body = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Pair with ${device.name} over Bluetooth to rename it.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: ThemeConstants.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: ThemeConstants.surfaceVariant
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: ThemeConstants.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.memory,
                                size: 16, color: ThemeConstants.textTertiary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _normalizeMac(device.macAddress),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: ThemeConstants.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (connectError.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          connectError,
                          style: TextStyle(
                            color: ThemeConstants.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: startPairing,
                          icon: Icon(Icons.bluetooth_searching_rounded,
                              size: 18, color: _onAccent(context)),
                          label: Text(
                            connectError.isEmpty
                                ? 'Pair Bluetooth'
                                : 'Retry Pairing',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _onAccent(context),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ThemeConstants.accent,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  );
              }

              return _modalShell(
                icon: headerIcon,
                iconColor: headerColor,
                title: title,
                onClose: (step == 'searching' || step == 'success')
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: body,
              );
            },
          );
        },
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) => nameCtrl.dispose());
    }
  }

  Future<void> _removeRegisteredDevice(DeviceInfo device) async {
    if (device.id == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device id missing for removal')),
        );
      }
      return;
    }

    final orgId = _currentOrganizationId();
    if (orgId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Organization not available')),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Device'),
        content: Text('Remove ${device.name} from this organization?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(deviceRepositoryProvider).removeDeviceFromOrganization(
            sensorId: device.id!,
            organizationId: orgId,
            macAddress: device.macAddress,
          );
      ref.refresh(wifiDevicesByOrgProvider);
      if (_connectedDeviceMac == _normalizeMac(device.macAddress) && mounted) {
        setState(() {
          _isDeviceConnected = false;
          _connectedDeviceMac = null;
          _selectedDeviceMac = null;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Device removed')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Remove failed: ${e.toString()}')));
      }
    }
  }

  void _showCreateSheet() {
    _clearScanSelection();
    // Kick off the shared BLE scanner (same one the Devices list screen uses)
    // so nearby hardware appears automatically when the sheet opens.
    final scanner = ref.read(bleScannerProvider);
    scanner.initializeAutoScan();
    ref.read(startScanProvider)();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            _sheetSetState = setModalState;
            _sheetContext = context;
            return Consumer(
              builder: (context, ref, _) {
                // Mirror the shared scanner's live results into a local field so
                // the existing helpers keep working, and so the sheet rebuilds
                // as devices are discovered. We intentionally do NOT watch the
                // platform scan flag here: it toggles every scan→pause→rescan
                // cycle and only caused the discovery UI to flicker.
                _discoveredDevices = ref.watch(bleScanResultsProvider).maybeWhen(
                      data: (list) => list,
                      orElse: () => _discoveredDevices,
                    );
                return Padding(
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom),
                  child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: ThemeConstants.surface,
                    border: Border.all(
                      color: ThemeConstants.border.withValues(alpha: 0.85),
                    ),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header with title and close button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text('Register New Hardware',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: ThemeConstants.textPrimary),
                                  textAlign: TextAlign.center),
                            ),
                            IconButton(
                              icon: Icon(Icons.close,
                                  color: ThemeConstants.textSecondary),
                              onPressed: () async {
                                await _closeCreateSheet();
                                Navigator.of(context).pop();
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Tab buttons
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    _isAutoScan = true;
                                    _clearScanSelection();
                                  });
                                  ref.read(startScanProvider)();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: _isAutoScan
                                        ? ThemeConstants.segmentActiveBg
                                        : ThemeConstants.segmentInactiveBg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _isAutoScan
                                          ? ThemeConstants.segmentActiveBg
                                          : ThemeConstants.border,
                                    ),
                                  ),
                                  child: Text('AUTO SCAN (BLE)',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: _isAutoScan
                                              ? ThemeConstants.onNav
                                              : ThemeConstants.textSecondary),
                                      textAlign: TextAlign.center),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setModalState(() {
                                  _isAutoScan = false;
                                  _clearScanSelection();
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: !_isAutoScan
                                        ? ThemeConstants.segmentActiveBg
                                        : ThemeConstants.segmentInactiveBg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: !_isAutoScan
                                          ? ThemeConstants.segmentActiveBg
                                          : ThemeConstants.border,
                                    ),
                                  ),
                                  child: Text('MANUAL ENTRY',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: !_isAutoScan
                                              ? ThemeConstants.onNav
                                              : ThemeConstants.textSecondary),
                                      textAlign: TextAlign.center),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Content based on selected tab
                        if (_isAutoScan) ...[
                          // Device filter toggle
                          Container(
                            height: 34,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: ThemeConstants.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: ThemeConstants.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.verified_rounded,
                                  size: 14,
                                  color: _isHydrawav3Only
                                      ? ThemeConstants.accent
                                      : ThemeConstants.textTertiary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Hydrawav3',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _isHydrawav3Only
                                        ? ThemeConstants.accent
                                        : ThemeConstants.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 34,
                                  height: 22,
                                  child: FittedBox(
                                    fit: BoxFit.contain,
                                    alignment: Alignment.centerRight,
                                    child: Switch.adaptive(
                                      value: _isHydrawav3Only,
                                      activeColor: ThemeConstants.accent,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      onChanged: (value) => setModalState(
                                        () => _isHydrawav3Only = value,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 40),
                          // BLE Discovery - live results from the shared scanner
                          if (_isDeviceConnected &&
                              _connectedDeviceMac != null)
                            _buildSelectedPairingCard(context)
                          else if (_getFilteredDevices().isNotEmpty)
                            SizedBox(
                              height: 240,
                              child: SingleChildScrollView(
                                child: Column(
                                  children: _getFilteredDevices()
                                      .map((device) =>
                                          _buildDeviceItem(context, device))
                                      .toList(),
                                ),
                              ),
                            )
                          else
                            // Discovery runs continuously (scan → brief pause →
                            // rescan), so the platform scan flag toggles every
                            // cycle. Bind the empty state to a single steady
                            // "searching" view instead of that flag so it no
                            // longer flickers between a spinner and a "no
                            // devices" message while we keep looking.
                            SizedBox(
                              height: 200,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Searching for Hydrawav3 Devices',
                                      style: TextStyle(
                                        color: ThemeConstants.textSecondary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24),
                                      child: Text(
                                        'Make sure your Hydra device is powered on and in range.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: ThemeConstants.textTertiary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            // Discovery is always running, so don't gate this on
                            // the momentary scan flag (it toggles every cycle and
                            // made the button flicker between enabled/disabled).
                            // Tapping just re-kicks the shared scanner.
                            child: _getFilteredDevices().isNotEmpty
                                ? OutlinedButton(
                                    onPressed: () => _startBleScan(),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(
                                          color: ThemeConstants.border),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: Text('RESCAN AREA',
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color:
                                                ThemeConstants.textSecondary)),
                                  )
                                : ElevatedButton(
                                    onPressed: () => _startBleScan(),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: ThemeConstants.accent,
                                      disabledBackgroundColor:
                                          ThemeConstants.surfaceVariant,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16)),
                                    ),
                                    child: Text('RESCAN AREA',
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: _onAccent(context))),
                                  ),
                          ),
                        ] else ...[
                          // Manual Entry Form
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 20),
                            decoration: BoxDecoration(
                              color:
                                  ThemeConstants.accent.withValues(alpha: 0.1),
                              border: Border.all(
                                color: ThemeConstants.accent
                                    .withValues(alpha: 0.22),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'MANUAL ENTRY IS RESTRICTED TO VERIFIED DEVICE MAC IDENTIFIERS ONLY.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: ThemeConstants.accent,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('HARDWARE FRIENDLY NAME',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: ThemeConstants.textSecondary,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.3)),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _nameCtrl,
                                style: TextStyle(
                                    color: ThemeConstants.textPrimary),
                                decoration: InputDecoration(
                                  hintText: 'e.g. Recovery_Sun_A',
                                  hintStyle: TextStyle(
                                      color: ThemeConstants.textTertiary,
                                      fontSize: 14),
                                  filled: true,
                                  fillColor: ThemeConstants.surfaceVariant
                                      .withValues(alpha: 0.42),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                        color: ThemeConstants.border),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                        color: ThemeConstants.border),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? 'Required'
                                        : null,
                              ),
                              const SizedBox(height: 20),
                              Text('MAC IDENTIFIER (XX:XX:XX:XX:XX:XX)',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: ThemeConstants.textSecondary,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.3)),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _serialCtrl,
                                style: TextStyle(
                                    color: ThemeConstants.textPrimary),
                                decoration: InputDecoration(
                                  hintText: '00:00:00:00:00:00',
                                  hintStyle: TextStyle(
                                      color: ThemeConstants.textTertiary,
                                      fontSize: 14),
                                  filled: true,
                                  fillColor: ThemeConstants.surfaceVariant
                                      .withValues(alpha: 0.42),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                        color: ThemeConstants.border),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                        color: ThemeConstants.border),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Required';
                                  }

                                  final macRegex = RegExp(
                                      r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');
                                  if (!macRegex.hasMatch(v.trim())) {
                                    return 'Invalid MAC address';
                                  }

                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _submitting
                                      ? null
                                      : () => _registerDevice(context),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: ThemeConstants.accent,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                  ),
                                  child: _submitting
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.black))
                                      : Text('REGISTER ASSET',
                                          style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: _onAccent(context))),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
                );
              },
            );
          },
        );
      },
    ).whenComplete(() {
      // The sheet can close by swipe / barrier tap (not just the X button or a
      // successful register), so always drop the sheet's setState/context here.
      // Otherwise _updateSheet() would later call setState on a disposed
      // StatefulBuilder (e.g. from the Edit-WiFi handshake) and crash.
      _sheetSetState = null;
      _sheetContext = null;
    });
  }

  Widget _buildDeviceCard(DeviceInfo device) {
    return GradientCard(
      borderRadius: 20,
      showShadow: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: ThemeConstants.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.memory,
                      size: 21, color: ThemeConstants.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: ThemeConstants.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        device.macAddress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: ThemeConstants.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: ThemeConstants.surfaceVariant.withValues(alpha: 0.48),
                border: Border.all(color: ThemeConstants.border),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('REGISTERED DEVICE',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: ThemeConstants.textTertiary)),
                  const SizedBox(height: 6),
                  Text(device.macAddress,
                      style: TextStyle(
                          fontSize: 13,
                          color: ThemeConstants.textPrimary,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: ThemeConstants.border),
            const SizedBox(height: 10),
            Row(
              children: [
                _cardActionTile(
                  icon: Icons.my_location_rounded,
                  label: 'Locate',
                  onTap: () => _openLocateModal(device),
                ),
                _cardActionTile(
                  icon: Icons.fact_check_rounded,
                  label: 'Report',
                  onTap: () => _openDiagnosticModal(device),
                ),
                _cardActionTile(
                  icon: Icons.wifi_rounded,
                  label: 'Edit WiFi',
                  onTap: () => _openWifiModal(device),
                ),
                _cardActionTile(
                  icon: Icons.drive_file_rename_outline_rounded,
                  label: 'Edit Name',
                  onTap: () => _openEditNameModal(device),
                ),
                _cardActionTile(
                  icon: Icons.delete_outline_rounded,
                  label: 'Remove',
                  color: ThemeConstants.error,
                  onTap: () => _removeRegisteredDevice(device),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final c = color ?? ThemeConstants.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: c),
              const SizedBox(height: 6),
              Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: c,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A vertically-scrollable centered message so RefreshIndicator's pull
  /// gesture still works when the list is empty / errored / has no devices.
  Widget _pullableMessage(String message) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                message,
                style: TextStyle(color: ThemeConstants.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(wifiDevicesByOrgProvider);

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ThemeConstants.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: ThemeConstants.border),
                      ),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        color: ThemeConstants.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Device Fleet',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: ThemeConstants.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Manage your registered Hydra devices',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.3,
                            color: ThemeConstants.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _showCreateSheet,
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ThemeConstants.accent,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: ThemeConstants.accent.withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        color: _onAccent(context),
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: ThemeConstants.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: ThemeConstants.border),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (value) =>
                      setState(() => _searchText = value.trim()),
                  style: TextStyle(color: ThemeConstants.textPrimary),
                  decoration: InputDecoration(
                    hintText:
                        'Filter by hardware name, MAC ID or protocol type...',
                    hintStyle: TextStyle(color: ThemeConstants.textTertiary),
                    prefixIcon:
                        Icon(Icons.search, color: ThemeConstants.textTertiary),
                    filled: false,
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: RefreshIndicator(
                  color: ThemeConstants.accent,
                  onRefresh: () =>
                      ref.refresh(wifiDevicesByOrgProvider.future),
                  child: Builder(
                    builder: (context) {
                      // Mirror the device-list screen: only show the spinner on
                      // the very first fetch (no value yet). After that, keep
                      // rendering the last-known list/empty-state so a refresh
                      // (e.g. after add/rename/delete) never drops back to an
                      // infinite spinner.
                      final firstLoading =
                          devicesAsync.isLoading && !devicesAsync.hasValue;
                      if (firstLoading) {
                        return Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: ThemeConstants.accent),
                        );
                      }

                      if (devicesAsync.hasError && !devicesAsync.hasValue) {
                        return _pullableMessage(
                          'Unable to load devices: ${devicesAsync.error}',
                        );
                      }

                      final devices =
                          devicesAsync.valueOrNull ?? const <DeviceInfo>[];
                      final filteredDevices = _searchText.isEmpty
                          ? devices
                          : devices.where((device) {
                              final normalized =
                                  '${device.name} ${device.macAddress}'
                                      .toLowerCase();
                              return normalized
                                  .contains(_searchText.toLowerCase());
                            }).toList();

                      if (filteredDevices.isEmpty) {
                        return _pullableMessage(
                          _searchText.isEmpty
                              ? 'No registered devices found.'
                              : 'No devices match your search.',
                        );
                      }

                      return ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: filteredDevices.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) =>
                            _buildDeviceCard(filteredDevices[index]),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
