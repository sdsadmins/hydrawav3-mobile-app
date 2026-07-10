import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/ble_constants.dart';
import '../../../../core/constants/theme_constants.dart';
import '../../../ble/data/ble_repository.dart';
import '../../data/client_repository.dart';
import '../../domain/client_model.dart';
import '../providers/lease_controller.dart';

/// Device-lease management for a single client (parity with the web
/// `clientDetails.tsx` lease card). Renders three states — Inactive (register),
/// Pending (load the lease ID onto the device), and Active (reset password /
/// deactivate) — and drives the BLE + API handshake via [leaseControllerProvider].
///
/// This is a non-Scaffold section so it can be embedded either as the whole
/// body of [ClientLeaseScreen] or above the reports on the combined client
/// detail screen.
class ClientLeaseSection extends ConsumerStatefulWidget {
  final String clientId;

  const ClientLeaseSection({super.key, required this.clientId});

  @override
  ConsumerState<ClientLeaseSection> createState() => _ClientLeaseSectionState();
}

class _ClientLeaseSectionState extends ConsumerState<ClientLeaseSection> {
  static final RegExp _macRegex =
      RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$');

  Client? _client;
  bool _loading = true;
  String? _loadError;

  // Register-form state.
  bool _formOpen = false;
  final _macCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _showPassword = false;

  // Reset-password state.
  bool _resetMode = false;
  final _resetPwdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _macCtrl.dispose();
    _passwordCtrl.dispose();
    _resetPwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final c = await ref.read(clientRepositoryProvider).getById(widget.clientId);
      if (mounted) setState(() => _client = c);
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  LeaseController get _controller => ref.read(leaseControllerProvider.notifier);

  void _applyResult(Client? updated) {
    if (updated != null && mounted) {
      setState(() {
        _client = updated;
        _formOpen = false;
        _resetMode = false;
        _macCtrl.clear();
        _passwordCtrl.clear();
        _resetPwdCtrl.clear();
      });
    }
  }

  // --- Actions ---

  Future<void> _register() async {
    final mac = _macCtrl.text.trim();
    final pwd = _passwordCtrl.text;
    if (!_macRegex.hasMatch(mac)) {
      _snack('Enter a valid MAC address (AA:BB:CC:DD:EE:FF).');
      return;
    }
    if (pwd.length < 6) {
      _snack('Password must be at least 6 characters.');
      return;
    }
    final updated = await _controller.registerLease(
      clientId: widget.clientId,
      macAddress: mac,
      password: pwd,
    );
    _applyResult(updated);
  }

  Future<void> _loadToDevice() async {
    final client = _client;
    if (client == null) return;
    final device = await _pickDevice();
    if (device == null) return;
    final updated =
        await _controller.loadLeaseToDevice(client: client, device: device);
    _applyResult(updated);
  }

  Future<void> _deactivate() async {
    final client = _client;
    if (client == null) return;
    final device = await _pickDevice();
    if (device == null) return;
    final updated =
        await _controller.deactivateLease(client: client, device: device);
    _applyResult(updated);
  }

  Future<void> _resetPassword() async {
    if (_resetPwdCtrl.text.length < 6) {
      _snack('Password must be at least 6 characters.');
      return;
    }
    final updated = await _controller.resetPassword(
      clientId: widget.clientId,
      password: _resetPwdCtrl.text,
    );
    _applyResult(updated);
  }

  Future<void> _scanFillMac() async {
    final device = await _pickDevice();
    if (device == null) return;
    final mac = await _controller.readDeviceMac(device);
    if (mac != null && mounted) setState(() => _macCtrl.text = mac);
  }

  // --- Device picker ---

  Future<BluetoothDevice?> _pickDevice() async {
    final repo = ref.read(bleRepositoryProvider);
    unawaitedStart(repo);
    final result = await showModalBottomSheet<BluetoothDevice>(
      context: context,
      backgroundColor: ThemeConstants.surface,
      isScrollControlled: true,
      builder: (_) => _DevicePickerSheet(repo: repo),
    );
    await repo.stopScan();
    return result;
  }

  void unawaitedStart(BleRepository repo) {
    // Fire-and-forget scan start; the sheet renders results as they arrive.
    repo.startScan();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(leaseControllerProvider);

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Failed to load client: $_loadError',
            textAlign: TextAlign.center,
            style: TextStyle(color: ThemeConstants.error)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (flow.busy) _busyBanner(flow.step),
        if (flow.error != null) _errorBanner(flow.error!),
        _leaseCard(flow),
      ],
    );
  }

  Widget _busyBanner(String? step) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ThemeConstants.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ThemeConstants.border),
        ),
        child: Row(children: [
          const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(step ?? 'Working…',
                  style: TextStyle(color: ThemeConstants.textSecondary))),
        ]),
      );

  Widget _errorBanner(String msg) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ThemeConstants.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ThemeConstants.error.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(Icons.error_outline_rounded, color: ThemeConstants.error, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: TextStyle(color: ThemeConstants.error))),
        ]),
      );

  Widget _leaseCard(LeaseFlowState flow) {
    final client = _client!;
    // The register form takes precedence in any state, so it doubles as
    // "change device / re-enter details" for a pending or active lease.
    if (_formOpen) return _registerForm(flow);
    if (client.isLeaseActive) return _activeCard(client, flow);
    if (client.isLeasePending) return _pendingCard(client, flow);
    return _inactiveCard(flow);
  }

  /// Open the register form, optionally prefilling the MAC (used by "Change
  /// device / re-enter details" so the practitioner can correct a wrong MAC or
  /// swap to another unit). Re-saving re-runs `registerLease`, which updates the
  /// MAC/password on the server while keeping the same lease.
  void _openRegisterForm({String? mac}) {
    setState(() {
      _macCtrl.text = mac ?? '';
      _passwordCtrl.clear();
      _formOpen = true;
    });
    ref.read(leaseControllerProvider.notifier).clearError();
  }

  // --- Inactive / register ---

  Widget _inactiveCard(LeaseFlowState flow) {
    return _sectionCard(
      title: 'Device Lease',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No lease registered for this client yet.',
              style: TextStyle(color: ThemeConstants.textSecondary)),
          const SizedBox(height: 14),
          _primaryButton(
            icon: Icons.power_settings_new_rounded,
            label: 'Activate Lease',
            onPressed: flow.busy ? null : () => _openRegisterForm(),
          ),
        ],
      ),
    );
  }

  Widget _registerForm(LeaseFlowState flow) {
    return _sectionCard(
      title: 'Register Lease',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label('Device MAC'),
          TextField(
            controller: _macCtrl,
            enabled: !flow.busy,
            textCapitalization: TextCapitalization.characters,
            decoration: _fieldDecoration('AA:BB:CC:DD:EE:FF'),
            style: TextStyle(color: ThemeConstants.textPrimary),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: flow.busy ? null : _scanFillMac,
            icon: const Icon(Icons.bluetooth_searching_rounded, size: 18),
            label: const Text('Scan device to fill MAC'),
          ),
          const SizedBox(height: 14),
          _label('Lease Password'),
          TextField(
            controller: _passwordCtrl,
            enabled: !flow.busy,
            obscureText: !_showPassword,
            decoration: _fieldDecoration('Min 6 characters').copyWith(
              suffixIcon: IconButton(
                icon: Icon(_showPassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            style: TextStyle(color: ThemeConstants.textPrimary),
          ),
          const SizedBox(height: 6),
          Text('Hashed with bcrypt on the server — never shown again.',
              style: TextStyle(
                  color: ThemeConstants.textTertiary, fontSize: 12)),
          const SizedBox(height: 16),
          _primaryButton(
            label: 'Save Lease',
            onPressed: flow.busy ? null : _register,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed:
                flow.busy ? null : () => setState(() => _formOpen = false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  // --- Pending ---

  Widget _pendingCard(Client client, LeaseFlowState flow) {
    return _sectionCard(
      title: 'Lease — Pending',
      badge: _badge('Not Loaded', ThemeConstants.warning),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Connect to the matching device over Bluetooth to load this '
              'lease ID onto it.',
              style: TextStyle(color: ThemeConstants.textSecondary)),
          const SizedBox(height: 14),
          _readonlyRow('Lease ID', client.leaseId ?? '—', copyable: true),
          const SizedBox(height: 10),
          _readonlyRow('Device MAC', client.macAddress ?? '—'),
          const SizedBox(height: 16),
          _primaryButton(
            icon: Icons.bluetooth_connected_rounded,
            label: 'Load Lease ID to Device',
            onPressed: flow.busy ? null : _loadToDevice,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: flow.busy
                ? null
                : () => _openRegisterForm(mac: client.macAddress),
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const Text('Change device / re-enter details'),
          ),
        ],
      ),
    );
  }

  // --- Active ---

  Widget _activeCard(Client client, LeaseFlowState flow) {
    return _sectionCard(
      title: 'Lease — Active',
      badge: _badge('Active', ThemeConstants.success),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (client.leaseDate != null) ...[
            _readonlyRow('Lease Date', _fmtDate(client.leaseDate!)),
            const SizedBox(height: 10),
          ],
          _readonlyRow('Lease ID', client.leaseId ?? '—', copyable: true),
          const SizedBox(height: 10),
          _readonlyRow('Device MAC', client.macAddress ?? '—'),
          const SizedBox(height: 16),
          if (_resetMode) ...[
            _label('New Password'),
            TextField(
              controller: _resetPwdCtrl,
              enabled: !flow.busy,
              obscureText: true,
              decoration: _fieldDecoration('Min 6 characters'),
              style: TextStyle(color: ThemeConstants.textPrimary),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _primaryButton(
                  label: 'Save',
                  onPressed: flow.busy ? null : _resetPassword,
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed:
                    flow.busy ? null : () => setState(() => _resetMode = false),
                child: const Text('Cancel'),
              ),
            ]),
          ] else
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      flow.busy ? null : () => setState(() => _resetMode = true),
                  icon: const Icon(Icons.key_rounded, size: 18),
                  label: const Text('Reset Password'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: flow.busy ? null : _deactivate,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ThemeConstants.error,
                    side: BorderSide(color: ThemeConstants.error),
                  ),
                  icon: const Icon(Icons.power_off_rounded, size: 18),
                  label: const Text('Deactivate'),
                ),
              ),
            ]),
        ],
      ),
    );
  }

  // --- Shared building blocks ---

  Widget _sectionCard({
    required String title,
    required Widget child,
    Widget? badge,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ThemeConstants.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text(title,
                style: TextStyle(
                    color: ThemeConstants.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            const Spacer(),
            if (badge != null) badge,
          ]),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                color: ThemeConstants.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      );

  Widget _readonlyRow(String label, String value, {bool copyable = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(label,
              style: TextStyle(
                  color: ThemeConstants.textSecondary, fontSize: 13)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  color: ThemeConstants.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
        if (copyable && value != '—')
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              _snack('Copied');
            },
            child: Icon(Icons.copy_rounded,
                size: 16, color: ThemeConstants.textTertiary),
          ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: ThemeConstants.textTertiary),
        filled: true,
        fillColor: ThemeConstants.surfaceVariant.withValues(alpha: 0.7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: ThemeConstants.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: ThemeConstants.border),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );

  Widget _primaryButton({
    IconData? icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: ThemeConstants.navBackground,
        foregroundColor: ThemeConstants.onNav,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        minimumSize: const Size.fromHeight(48),
      ),
      icon: Icon(icon ?? Icons.check_rounded, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  String _fmtDate(DateTime d) {
    final local = d.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '${local.year}-$mm-$dd';
  }
}

/// Bluetooth device picker sheet. Streams live scan results and returns the
/// chosen [BluetoothDevice] to the caller. A "Hydrawav only" toggle (on by
/// default) hides unrelated Bluetooth devices by name prefix.
class _DevicePickerSheet extends StatefulWidget {
  final BleRepository repo;
  const _DevicePickerSheet({required this.repo});

  @override
  State<_DevicePickerSheet> createState() => _DevicePickerSheetState();
}

class _DevicePickerSheetState extends State<_DevicePickerSheet> {
  bool _hydraOnly = true;

  /// Normalized Hydra GATT service UUID advertised by the firmware. Null/empty
  /// disables UUID filtering (defensive — the constant is set in practice).
  static final String? _hydraServiceUuid =
      (BleConstants.preferredServiceUuid == null ||
              BleConstants.preferredServiceUuid!.isEmpty)
          ? null
          : BleConstants.normalizeUuid(BleConstants.preferredServiceUuid!);

  /// A scan result is a Hydra unit when it advertises the Hydra service UUID.
  /// Matches [autoConnectManager]'s scan filter exactly (normalize both sides,
  /// compare against [BleConstants.preferredServiceUuid]) — UUID, not name.
  bool _isHydra(ScanResult r) {
    final target = _hydraServiceUuid;
    if (target == null) return true; // no UUID configured → don't filter
    return r.advertisementData.serviceUuids
        .any((u) => BleConstants.normalizeUuid(u.str) == target);
  }

  String _nameOf(ScanResult r) => r.device.platformName.isNotEmpty
      ? r.device.platformName
      : r.advertisementData.advName;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Select a device',
                      style: TextStyle(
                          color: ThemeConstants.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                ),
                Text('Hydrawav only',
                    style: TextStyle(
                        color: ThemeConstants.textSecondary, fontSize: 12)),
                Switch(
                  value: _hydraOnly,
                  activeThumbColor: ThemeConstants.accent,
                  onChanged: (v) => setState(() => _hydraOnly = v),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 320,
              child: StreamBuilder<List<ScanResult>>(
                stream: widget.repo.scanResults,
                initialData: widget.repo.currentScanResults,
                builder: (context, snapshot) {
                  final results = (snapshot.data ?? const <ScanResult>[])
                      .where((r) {
                    if (_hydraOnly) return _isHydra(r);
                    // Unfiltered view still hides nameless junk devices.
                    return _nameOf(r).isNotEmpty;
                  }).toList();
                  if (results.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(height: 12),
                          Text(
                              _hydraOnly
                                  ? 'Scanning for Hydrawav devices…'
                                  : 'Scanning for devices…',
                              style: TextStyle(
                                  color: ThemeConstants.textSecondary)),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final r = results[i];
                      final rawName = _nameOf(r);
                      final name =
                          rawName.isEmpty ? 'Unknown device' : rawName;
                      return ListTile(
                        leading: Icon(Icons.bluetooth_rounded,
                            color: ThemeConstants.accent),
                        title: Text(name,
                            style:
                                TextStyle(color: ThemeConstants.textPrimary)),
                        subtitle: Text(r.device.remoteId.str,
                            style: TextStyle(
                                color: ThemeConstants.textTertiary,
                                fontSize: 12)),
                        onTap: () => Navigator.of(context).pop(r.device),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
