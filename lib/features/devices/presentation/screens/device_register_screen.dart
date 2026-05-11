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

  Color _onAccent(BuildContext context) =>
      Theme.of(context).colorScheme.onPrimary;

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
                    border: Border.all(
                      color: ThemeConstants.border.withValues(alpha: 0.85),
                    ),
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
                              onTap: () =>
                                  setModalState(() => _isAutoScan = false),
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
                              padding: const EdgeInsets.symmetric(vertical: 40),
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
                                backgroundColor: ThemeConstants.accent,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                              ),
                              child: Text('REGISTER ASSET',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: _onAccent(context))),
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
                                      color: _isScanning
                                          ? ThemeConstants.textTertiary
                                          : _onAccent(context))),
                            ),
                          ),
                      ] else ...[
                        // Manual Entry Form
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 20),
                          decoration: BoxDecoration(
                            color: ThemeConstants.accent.withValues(alpha: 0.1),
                            border: Border.all(
                              color:
                                  ThemeConstants.accent.withValues(alpha: 0.22),
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
                        Form(
                          key: _formKey,
                          child: Column(
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
                                style:
                                    TextStyle(color: ThemeConstants.textPrimary),
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
                                style:
                                    TextStyle(color: ThemeConstants.textPrimary),
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
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
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
              style: TextStyle(
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
                    color: ThemeConstants.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.memory,
                      size: 24, color: ThemeConstants.accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    device.name,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: ThemeConstants.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: ThemeConstants.surfaceVariant.withValues(alpha: 0.48),
                border: Border.all(color: ThemeConstants.border),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('HARDWARE MAC',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: ThemeConstants.textTertiary)),
                  const SizedBox(height: 8),
                  Text(device.macAddress,
                      style: TextStyle(
                          fontSize: 14,
                          color: ThemeConstants.textPrimary,
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
                      children: [
                        Text('DEVICES FLEET',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: ThemeConstants.textPrimary)),
                        SizedBox(height: 8),
                        Text(
                            'Manage clinical hardware connections and firmware protocols.',
                            style:
                                TextStyle(color: ThemeConstants.textSecondary)),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _showCreateSheet,
                      icon: Icon(Icons.add),
                      label: Text('Register Device'),
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
