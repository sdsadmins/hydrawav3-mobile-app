import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
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
  bool _isHydrawav3Only = true;
  bool _isScanning = false;
  List<ScanResult> _discoveredDevices = [];
  String? _selectedDeviceMac;

  @override
  void dispose() {
    _serialCtrl.dispose();
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _registerDevice(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    final auth = ref.read(authStateProvider);
    final orgIdRaw = auth.user?.organizationId;
    if (orgIdRaw == null || orgIdRaw.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Organization not available')));
      }
      return;
    }

    final orgId = int.tryParse(orgIdRaw);
    if (orgId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid organization id')));
      }
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(deviceRepositoryProvider).registerDevice(
        name: _nameCtrl.text.trim(),
        macAddress: _serialCtrl.text.trim(),
        organizationIds: [orgId],
      );

      ref.refresh(wifiDevicesByOrgProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Device registered successfully')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Register failed: ${e.toString()}')));
      }
    } finally {
      setState(() => _submitting = false);
    }
  }

  Future<void> _startBleScan() async {
    setState(() {
      _isScanning = true;
      _discoveredDevices.clear();
    });

    try {
      // Check if Bluetooth is on
      bool isOn = await FlutterBluePlus.isOn;
      if (!isOn) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable Bluetooth')),
          );
        }
        setState(() => _isScanning = false);
        return;
      }

      // Start scanning
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      // Listen to scan results
      FlutterBluePlus.scanResults.listen((results) {
        if (mounted) {
          setState(() {
            _discoveredDevices = results;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan error: ${e.toString()}')),
        );
      }
    } finally {
      // Scan will auto stop after 15 seconds timeout
      Future.delayed(const Duration(seconds: 16), () {
        if (mounted) {
          setState(() => _isScanning = false);
        }
      });
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

  Widget _buildDeviceItem(ScanResult device) {
    final deviceName = device.advertisementData.localName.isEmpty
        ? device.device.name
        : device.advertisementData.localName;
    final macAddress = device.device.id.toString();
    final isSelected = _selectedDeviceMac == macAddress;

    return GestureDetector(
      onTap: () {
        _serialCtrl.text = macAddress;
        if (_nameCtrl.text.trim().isEmpty) {
          _nameCtrl.text = deviceName.isEmpty ? 'Device' : deviceName;
        }
        setState(() => _selectedDeviceMac = macAddress);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? ThemeConstants.accent.withOpacity(0.2)
              : Colors.white.withOpacity(0.05),
          border: Border.all(
            color: isSelected
                ? ThemeConstants.accent
                : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.bluetooth_connected,
              color: isSelected ? ThemeConstants.accent : Colors.white60,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deviceName.isEmpty ? 'Unknown Device' : deviceName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    macAddress,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle,
                  color: ThemeConstants.accent, size: 20),
          ],
        ),
      ),
    );
  }

  void _showCreateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom),
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: ThemeConstants.surface,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header with title and close button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text('Register New Hardware',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white),
                                textAlign: TextAlign.center),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
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
                              onTap: () =>
                                  setModalState(() => _isAutoScan = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: _isAutoScan
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _isAutoScan
                                        ? Colors.transparent
                                        : Colors.white12,
                                  ),
                                ),
                                child: Text('AUTO SCAN (BLE)',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _isAutoScan
                                            ? Colors.black
                                            : Colors.white60),
                                    textAlign: TextAlign.center),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () =>
                                  setModalState(() => _isAutoScan = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: !_isAutoScan
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: !_isAutoScan
                                        ? Colors.transparent
                                        : Colors.white12,
                                  ),
                                ),
                                child: Text('MANUAL ENTRY',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: !_isAutoScan
                                            ? Colors.black
                                            : Colors.white60),
                                    textAlign: TextAlign.center),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Content based on selected tab
                      if (_isAutoScan) ...[
                        // Filter buttons
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setModalState(
                                    () => _isHydrawav3Only = true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: _isHydrawav3Only
                                        ? const Color(0xFF2A3F5F)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _isHydrawav3Only
                                          ? const Color(0xFF2A3F5F)
                                          : Colors.white12,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.shield_rounded,
                                          size: 16,
                                          color: _isHydrawav3Only
                                              ? Colors.white
                                              : Colors.white60),
                                      const SizedBox(width: 6),
                                      Text('Hydrawav3',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: _isHydrawav3Only
                                                  ? Colors.white
                                                  : Colors.white60),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setModalState(
                                    () => _isHydrawav3Only = false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: !_isHydrawav3Only
                                        ? const Color(0xFF2A3F5F)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: !_isHydrawav3Only
                                          ? const Color(0xFF2A3F5F)
                                          : Colors.white12,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.signal_cellular_alt,
                                          size: 16,
                                          color: !_isHydrawav3Only
                                              ? Colors.white
                                              : Colors.white60),
                                      const SizedBox(width: 6),
                                      Text('All Devices',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: !_isHydrawav3Only
                                                  ? Colors.white
                                                  : Colors.white60),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        // BLE Discovery - Devices List or Discovery State
                        if (_isScanning)
                          const SizedBox(
                            height: 200,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
                                            Colors.white),
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'Scanning for devices...',
                                    style: TextStyle(
                                      color: Colors.white70,
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
                                      color: Colors.white.withOpacity(0.3)),
                                  const SizedBox(height: 24),
                                  const Text(
                                    'NO DEVICES DETECTED IN IMMEDIATE RANGE.',
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.white54,
                                        fontWeight: FontWeight.w500),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            height: 240,
                            child: SingleChildScrollView(
                              child: Column(
                                children: _getFilteredDevices()
                                    .map((device) => _buildDeviceItem(device))
                                    .toList(),
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),
                        // Initialize Discovery button or Register button
                        if (!_isScanning && _selectedDeviceMac != null)
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () {
                                if (_nameCtrl.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Please enter device name')),
                                  );
                                  return;
                                }
                                _registerDevice(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1F3A52),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                              ),
                              child: const Text('REGISTER ASSET',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                            ),
                          )
                        else
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed:
                                  _isScanning ? null : () => _startBleScan(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1F3A52),
                                disabledBackgroundColor: Colors.white12,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                              ),
                              child: Text('INITIALIZE DISCOVERY',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: _isScanning
                                          ? Colors.white54
                                          : Colors.white)),
                            ),
                          ),
                      ] else ...[
                        // Manual Entry Form
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 20),
                          decoration: BoxDecoration(
                            color: ThemeConstants.background.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'MANUAL ENTRY IS RESTRICTED TO VERIFIED CLINICAL MAC IDENTIFIERS ONLY.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFFF9500),
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('HARDWARE FRIENDLY NAME',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white54,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.3)),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _nameCtrl,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'e.g. Clinical_Sun_A',
                                  hintStyle: const TextStyle(
                                      color: Colors.white30, fontSize: 14),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.05),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                        color: Colors.white.withOpacity(0.1)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                        color: Colors.white.withOpacity(0.1)),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                ),
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null,
                              ),
                              const SizedBox(height: 20),
                              const Text('MAC IDENTIFIER (XX:XX:XX:XX:XX:XX)',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white54,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.3)),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _serialCtrl,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: '00:00:00:00:00:00',
                                  hintStyle: const TextStyle(
                                      color: Colors.white30, fontSize: 14),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.05),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                        color: Colors.white.withOpacity(0.1)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                        color: Colors.white.withOpacity(0.1)),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                ),
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null,
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
                                    backgroundColor: const Color(0xFF1F3A52),
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
                                              color: Colors.white))
                                      : const Text('REGISTER ASSET',
                                          style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActionButton(IconData icon, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: ThemeConstants.textSecondary),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: ThemeConstants.textTertiary,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(DeviceInfo device) {
    return GradientCard(
      borderRadius: 24,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: ThemeConstants.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.memory,
                      size: 24, color: ThemeConstants.accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    device.name,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: ThemeConstants.background.withOpacity(0.08),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('HARDWARE MAC',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: ThemeConstants.textTertiary)),
                  const SizedBox(height: 8),
                  Text(device.macAddress,
                      style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _buildActionButton(Icons.gps_fixed, 'Locate'),
                _buildActionButton(Icons.show_chart, 'Report'),
                _buildActionButton(Icons.wifi, 'Edit WiFi'),
                _buildActionButton(Icons.edit, 'Edit Name'),
                _buildActionButton(Icons.delete_outline, 'Remove'),
              ],
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('DEVICES FLEET',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                        SizedBox(height: 8),
                        Text(
                            'Manage clinical hardware connections and firmware protocols.',
                            style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _showCreateSheet,
                      icon: const Icon(Icons.add),
                      label: const Text('Register Device'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (value) =>
                      setState(() => _searchText = value.trim()),
                  decoration: InputDecoration(
                    hintText:
                        'Filter by hardware name, MAC ID or protocol type...',
                    hintStyle:
                        const TextStyle(color: ThemeConstants.textTertiary),
                    prefixIcon: const Icon(Icons.search,
                        color: ThemeConstants.textTertiary),
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
                            style: const TextStyle(color: Colors.white70),
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
                  loading: () => const Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white70)),
                  error: (error, stack) => Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('Unable to load devices: ${error.toString()}',
                          style: const TextStyle(color: Colors.white70),
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
