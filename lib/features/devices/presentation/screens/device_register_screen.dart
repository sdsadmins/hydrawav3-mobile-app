import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Organization not available')));
      }
      return;
    }

    final orgId = int.tryParse(orgIdRaw);
    if (orgId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid organization id')));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device registered successfully')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Register failed: ${e.toString()}')));
      }
    } finally {
      setState(() => _submitting = false);
    }
  }

  void _showCreateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: ThemeConstants.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                  const Text('Create new device', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: _serialCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Serial Number / MAC Address',
                            prefixIcon: Icon(Icons.qr_code_rounded, color: ThemeConstants.textTertiary, size: 20),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _nameCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Device Name',
                            prefixIcon: Icon(Icons.label_outline_rounded, color: ThemeConstants.textTertiary, size: 20),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _submitting ? null : () => _registerDevice(context),
                            child: _submitting
                                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Create device'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
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
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(DeviceInfo device) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      color: Colors.white,
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
                  child: Icon(Icons.memory, size: 24, color: ThemeConstants.accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    device.name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87),
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
                  const Text('HARDWARE MAC', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Colors.black45)),
                  const SizedBox(height: 8),
                  Text(device.macAddress, style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w600)),
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
                        Text('DEVICES FLEET', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
                        SizedBox(height: 8),
                        Text('Manage clinical hardware connections and firmware protocols.', style: TextStyle(color: Colors.white70)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (value) => setState(() => _searchText = value.trim()),
                  decoration: InputDecoration(
                    hintText: 'Filter by hardware name, MAC ID or protocol type...',
                    hintStyle: const TextStyle(color: Colors.black38),
                    prefixIcon: const Icon(Icons.search, color: Colors.black38),
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
                            final normalized = '${device.name} ${device.macAddress}'.toLowerCase();
                            return normalized.contains(_searchText.toLowerCase());
                          }).toList();

                    if (filteredDevices.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            _searchText.isEmpty ? 'No registered devices found.' : 'No devices match your search.',
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
                      itemBuilder: (context, index) => _buildDeviceCard(filteredDevices[index]),
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
                  error: (error, stack) => Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('Unable to load devices: ${error.toString()}', style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
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
