import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../ble/data/ble_command_service.dart';
import '../../../ble/data/ble_repository.dart';
import '../../../ble/presentation/providers/ble_connection_provider.dart';
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
  bool _isScanning = false;
  List<ScanResult> _discoveredDevices = [];
  String? _selectedDeviceMac;
  bool _isDeviceConnected = false;
  String? _connectedDeviceMac;
  bool _connectingDevice = false;
  String? _connectingDeviceMac;
  StreamSubscription<List<ScanResult>>? _bleScanSubscription;
  StreamSubscription<bool>? _bleIsScanningSubscription;
  DateTime? _lastScanUiUpdateAt;
  static const Duration _scanUiThrottle = Duration(milliseconds: 500);
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
    if (_sheetSetState != null) {
      _sheetSetState!(updates);
      return;
    }
    if (mounted) {
      setState(updates);
    }
  }

  @override
  void dispose() {
    _serialCtrl.dispose();
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    _bleScanSubscription?.cancel();
    _bleIsScanningSubscription?.cancel();
    super.dispose();
  }

  void _clearScanSelection() {
    _discoveredDevices.clear();
    _selectedDeviceMac = null;
    _isDeviceConnected = false;
    _connectedDeviceMac = null;
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
    await FlutterBluePlus.stopScan();
    await _bleScanSubscription?.cancel();
    await _bleIsScanningSubscription?.cancel();
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

  /// Step 2: Start BLE discovery, clear old devices, then listen for nearby devices.
  Future<void> _startBleScan() async {
    _updateSheet(() {
      _isScanning = true;
      _discoveredDevices.clear();
      _selectedDeviceMac = null;
      _isDeviceConnected = false;
      _connectedDeviceMac = null;
    });

    try {
      // Ensure any prior scan is stopped before starting a new one.
      await FlutterBluePlus.stopScan();
      await _bleScanSubscription?.cancel();
      _bleScanSubscription = null;
      _lastScanUiUpdateAt = null;

      bool isOn = await FlutterBluePlus.isOn;
      if (!isOn) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable Bluetooth')),
          );
        }
        _updateSheet(() => _isScanning = false);
        return;
      }

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      _bleScanSubscription = FlutterBluePlus.onScanResults.listen((results) {
        // Avoid mutating the scan list while connecting; it can lead to
        // stale selections and Android GATT instability.
        if (_connectingDevice) return;
        if (mounted) {
          final now = DateTime.now();
          if (_lastScanUiUpdateAt != null &&
              now.difference(_lastScanUiUpdateAt!) < _scanUiThrottle) {
            return;
          }
          _lastScanUiUpdateAt = now;

          _updateSheet(() {
            final unique = <String, ScanResult>{};
            for (final result in results) {
              unique[_normalizeMac(result.device.id.toString())] = result;
            }
            _discoveredDevices = unique.values.toList();
          });
        }
      }, onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Scan error: ${error.toString()}')),
          );
          _updateSheet(() => _isScanning = false);
        }
      });

      _bleIsScanningSubscription?.cancel();
      _bleIsScanningSubscription =
          FlutterBluePlus.isScanning.listen((scanning) {
        if (mounted) {
          _updateSheet(() => _isScanning = scanning);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan error: ${e.toString()}')),
        );
        _updateSheet(() => _isScanning = false);
      }
    }
  }

  List<ScanResult> _getFilteredDevices() {
    if (_isHydrawav3Only) {
      return _discoveredDevices
          .where((device) =>
              device.advertisementData.localName
                  .toLowerCase()
                  .contains('hydrawav') ||
              device.device.name.toLowerCase().contains('hydrawav'))
          .toList();
    }
    return _discoveredDevices;
  }

  Future<bool> _connectToSelectedDevice() async {
    if (_selectedDeviceMac == null) return false;
    // Stop scanning before connecting. (Android BLE is very unstable when
    // scanning + connecting simultaneously.)
    try {
      await FlutterBluePlus.stopScan();
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

      for (final candidate in preferredOrder) {
        final didConnect = await ref.read(bleRepositoryProvider).connectDevice(
              BluetoothDevice(remoteId: DeviceIdentifier(candidate)),
              cachePairedDevice: false,
            );
        if (didConnect) {
          connected = true;
          connectedCandidate = candidate;
          break;
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

  Future<void> _handleLocate(DeviceInfo device) async {
    try {
      await ref.read(deviceRepositoryProvider).locateDevice(device.macAddress);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Locate command sent')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Locate failed: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _handleDiagnostics(DeviceInfo device) async {
    try {
      await ref
          .read(deviceRepositoryProvider)
          .runDiagnostics(device.macAddress);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Diagnostics requested')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Diagnostics failed: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _openWifiModal(DeviceInfo device) async {
    final ssidCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    try {
      final res = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          var step = 0; // 0=bt-handshake, 1=wifi-config
          var connecting = true;
          var connectError = '';
          var showPassword = false;
          var started = false;

          return StatefulBuilder(
            builder: (context, setModalState) {
              // Start handshake exactly once when dialog mounts.
              if (!started) {
                started = true;
                Future.microtask(() async {
                  setModalState(() {
                    connecting = true;
                    connectError = '';
                    step = 0;
                  });
                  final ok = await _activateRegisteredDevice(device);
                  if (!mounted) return;
                  if (ok) {
                    setModalState(() {
                      connecting = false;
                      step = 1;
                    });
                  } else {
                    setModalState(() {
                      connecting = false;
                      connectError =
                          'Failed to establish Bluetooth connection. Please try again.';
                      step = 0;
                    });
                  }
                });
              }

              return AlertDialog(
                title:
                    Text(step == 0 ? 'Bluetooth handshake' : 'Configure WiFi'),
                content: step == 0
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Establishing secure connection to device…',
                          ),
                          const SizedBox(height: 16),
                          if (connecting) const LinearProgressIndicator(),
                          if (!connecting && connectError.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              connectError,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: ssidCtrl,
                            decoration:
                                const InputDecoration(labelText: 'SSID'),
                          ),
                          TextField(
                            controller: passCtrl,
                            obscureText: !showPassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              suffixIcon: IconButton(
                                onPressed: () => setModalState(() {
                                  showPassword = !showPassword;
                                }),
                                icon: Icon(
                                  showPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop(false);
                    },
                    child: const Text('Cancel'),
                  ),
                  if (step == 1)
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop(true);
                      },
                      child: const Text('Send'),
                    ),
                  if (step == 0 && !connecting)
                    TextButton(
                      onPressed: () {
                        // Retry handshake like web's "Start handshake".
                        setModalState(() {
                          started = false;
                        });
                      },
                      child: const Text('Retry'),
                    ),
                ],
              );
            },
          );
        },
      );

      if (res == true) {
        if (_connectedDeviceMac == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Bluetooth connection lost. Please reconnect and try again.',
                ),
              ),
            );
          }
          return;
        }

        final success =
            await ref.read(bleCommandServiceProvider).sendWifiCredentials(
                  _connectedDeviceMac!,
                  ssid: ssidCtrl.text.trim(),
                  password: passCtrl.text,
                );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    success ? 'WiFi credentials sent' : 'WiFi send failed')),
          );
        }
      }
    } finally {
      ssidCtrl.dispose();
      passCtrl.dispose();
    }
  }

  Future<void> _editNameFlow({DeviceInfo? registeredDevice}) async {
    final targetMac = _normalizeMac(
        registeredDevice?.macAddress ?? _connectedDeviceMac ?? '');
    if (targetMac.isEmpty) return;

    final editCtrl = TextEditingController(
      text: registeredDevice?.name ?? _nameCtrl.text.trim(),
    );
    try {
      final res = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Edit Device Name'),
          content: TextField(
              controller: editCtrl,
              decoration: const InputDecoration(labelText: 'Device Name')),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Save')),
          ],
        ),
      );

      if (res != true) return;

      final newName = editCtrl.text.trim();
      if (newName.isEmpty) return;
      _nameCtrl.text = newName;
      final prevSelected = _selectedDeviceMac;
      _selectedDeviceMac = targetMac;

      final synced = await _syncSelectedDeviceName();
      if (synced) {
        await ref
            .read(bleRepositoryProvider)
            .renamePairedDevice(targetMac, newName);
      }

      var backendUpdated = false;
      if (registeredDevice?.id != null) {
        try {
          await ref
              .read(deviceRepositoryProvider)
              .renameDevice(registeredDevice!.id!, newName);
          backendUpdated = true;
          ref.refresh(wifiDevicesByOrgProvider);
        } catch (_) {}
      }

      if (mounted) {
        final message = backendUpdated && synced
            ? 'Name updated on hardware and backend'
            : backendUpdated
                ? 'Backend updated, but hardware rename failed'
                : synced
                    ? 'Hardware updated, but backend rename failed'
                    : 'Name update failed';

        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
      _selectedDeviceMac = prevSelected;
    } finally {
      editCtrl.dispose();
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            _sheetSetState = setModalState;
            _sheetContext = context;
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
                                onTap: () => setModalState(() {
                                  _isAutoScan = true;
                                  _clearScanSelection();
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: _isAutoScan
                                        ? ThemeConstants.accent
                                            .withValues(alpha: 0.18)
                                        : ThemeConstants.surfaceVariant
                                            .withValues(alpha: 0.28),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _isAutoScan
                                          ? ThemeConstants.accent
                                          : ThemeConstants.border,
                                    ),
                                  ),
                                  child: Text('AUTO SCAN (BLE)',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: _isAutoScan
                                              ? ThemeConstants.accent
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
                                        ? ThemeConstants.accent
                                            .withValues(alpha: 0.18)
                                        : ThemeConstants.surfaceVariant
                                            .withValues(alpha: 0.28),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: !_isAutoScan
                                          ? ThemeConstants.accent
                                          : ThemeConstants.border,
                                    ),
                                  ),
                                  child: Text('MANUAL ENTRY',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: !_isAutoScan
                                              ? ThemeConstants.accent
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
                          // BLE Discovery - Devices List or Discovery State
                          if (_isScanning)
                            SizedBox(
                              height: 200,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          ThemeConstants.accent),
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Scanning for devices...',
                                      style: TextStyle(
                                        color: ThemeConstants.textSecondary,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else if (_getFilteredDevices().isEmpty)
                            Center(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 40),
                                child: Column(
                                  children: [
                                    Icon(Icons.bluetooth,
                                        size: 60,
                                        color: ThemeConstants.textTertiary
                                            .withValues(alpha: 0.55)),
                                    const SizedBox(height: 24),
                                    Text(
                                      'NO DEVICES DETECTED IN IMMEDIATE RANGE.',
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: ThemeConstants.textSecondary,
                                          fontWeight: FontWeight.w500),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else if (_isDeviceConnected &&
                              _connectedDeviceMac != null)
                            _buildSelectedPairingCard(context)
                          else
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
                            ),
                          const SizedBox(height: 16),
                          if (!_isScanning && _getFilteredDevices().isNotEmpty)
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: OutlinedButton(
                                onPressed: () => _startBleScan(),
                                style: OutlinedButton.styleFrom(
                                  side:
                                      BorderSide(color: ThemeConstants.border),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Text('RESCAN AREA',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: ThemeConstants.textSecondary)),
                              ),
                            ),
                          if (!_isScanning && _getFilteredDevices().isEmpty)
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: () => _startBleScan(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: ThemeConstants.accent,
                                  disabledBackgroundColor:
                                      ThemeConstants.surfaceVariant,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                ),
                                child: Text('INITIALIZE DISCOVERY',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: _onAccent(context))),
                              ),
                            )
                          else if (_isScanning)
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: ThemeConstants.accent,
                                  disabledBackgroundColor:
                                      ThemeConstants.surfaceVariant,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                ),
                                child: Text('INITIALIZE DISCOVERY',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: ThemeConstants.textTertiary)),
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
                                  'MANUAL ENTRY IS RESTRICTED TO VERIFIED CLINICAL MAC IDENTIFIERS ONLY.',
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
                                  hintText: 'e.g. Clinical_Sun_A',
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
                const SizedBox(width: 10),
                InkWell(
                  onTap: () async {
                    await _removeRegisteredDevice(device);
                  },
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: ThemeConstants.error.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: ThemeConstants.error.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                          color: ThemeConstants.error,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Remove',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: ThemeConstants.error,
                          ),
                        ),
                      ],
                    ),
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
          ],
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
                          'Manage your registered clinical hardware',
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
                child: devicesAsync.when(
                  data: (devices) {
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
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            _searchText.isEmpty
                                ? 'No registered devices found.'
                                : 'No devices match your search.',
                            style:
                                TextStyle(color: ThemeConstants.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: filteredDevices.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) =>
                          _buildDeviceCard(filteredDevices[index]),
                    );
                  },
                  loading: () => Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: ThemeConstants.accent)),
                  error: (error, stack) => Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('Unable to load devices: ${error.toString()}',
                          style: TextStyle(color: ThemeConstants.textSecondary),
                          textAlign: TextAlign.center),
                    ),
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
