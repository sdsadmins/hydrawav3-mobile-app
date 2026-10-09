import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/ble_constants.dart';
import '../../../../core/constants/theme_constants.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../auth/presentation/widgets/auth_ui.dart';
import '../../../devices/presentation/widgets/device_center_widgets.dart'
    show SignalBars, UnitMark, signalOf;
import '../../../ble/data/ble_repository.dart';
import '../../../ble/services/ble_connector.dart';
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
  final _usernameCtrl = TextEditingController();
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
    _usernameCtrl.dispose();
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
        _usernameCtrl.clear();
        _passwordCtrl.clear();
        _resetPwdCtrl.clear();
      });
    }
  }

  // --- Actions ---

  Future<void> _register() async {
    final mac = _macCtrl.text.trim();
    // Username is space-stripped as you type/paste, but trim defensively too.
    final username = _usernameCtrl.text.trim();
    final pwd = _passwordCtrl.text;
    if (!_macRegex.hasMatch(mac)) {
      _snack('Enter a valid MAC address (AA:BB:CC:DD:EE:FF).');
      return;
    }
    if (username.isEmpty) {
      _snack('Enter a lease username.');
      return;
    }
    if (pwd.length < 6) {
      _snack('Password must be at least 6 characters.');
      return;
    }
    final updated = await _controller.registerLease(
      clientId: widget.clientId,
      macAddress: mac,
      username: username,
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
      backgroundColor: RefPalette.of(context).card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
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
          color: RefPalette.of(context).tanSoft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(step ?? 'Working…',
                  style: TextStyle(color: RefPalette.of(context).ink2))),
        ]),
      );

  Widget _errorBanner(String msg) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ThemeConstants.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
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
              style: TextStyle(color: RefPalette.of(context).ink2)),
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
            style: TextStyle(color: RefPalette.of(context).ink, fontSize: 15),
          ),
          const SizedBox(height: 8),
          // v6 "Pick a unit to hand off" — the same Bluetooth scan sheet,
          // which fills the unit's MAC above.
          _softButton(
            icon: Icons.bluetooth_searching_rounded,
            label: 'Pick a unit to hand off',
            onPressed: flow.busy ? null : _scanFillMac,
          ),
          const SizedBox(height: 14),
          _label('Lease Username'),
          TextField(
            controller: _usernameCtrl,
            enabled: !flow.busy,
            // No spaces allowed — the formatter strips any whitespace whether
            // typed or pasted, so a copied value with spaces lands clean.
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'\s')),
            ],
            keyboardType: TextInputType.text,
            autocorrect: false,
            enableSuggestions: false,
            decoration: _fieldDecoration('No spaces allowed'),
            style: TextStyle(color: RefPalette.of(context).ink, fontSize: 15),
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
            style: TextStyle(color: RefPalette.of(context).ink, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text('Hashed with bcrypt on the server, never shown again.',
              style: TextStyle(
                  color: RefPalette.of(context).ink3, fontSize: 12)),
          const SizedBox(height: 16),
          _primaryButton(
            label: 'Save Lease',
            onPressed: flow.busy ? null : _register,
          ),
          const SizedBox(height: 8),
          Center(
            child: AuthTextLink(
              label: 'Cancel',
              onTap: () {
                if (!flow.busy) setState(() => _formOpen = false);
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- Pending ---

  Widget _pendingCard(Client client, LeaseFlowState flow) {
    return _sectionCard(
      title: 'Lease: Pending',
      badge: _badge('Not Loaded', ThemeConstants.warning),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Connect to the matching device over Bluetooth to load this '
              'lease ID onto it.',
              style: TextStyle(color: RefPalette.of(context).ink2)),
          const SizedBox(height: 14),
          _readonlyRow('Lease ID', client.leaseId ?? '--', copyable: true),
          const SizedBox(height: 10),
          _readonlyRow('Device MAC', client.macAddress ?? '--'),
          const SizedBox(height: 16),
          _primaryButton(
            icon: Icons.bluetooth_connected_rounded,
            label: 'Load Lease ID to Device',
            onPressed: flow.busy ? null : _loadToDevice,
          ),
          const SizedBox(height: 8),
          _outlineButton(
            icon: Icons.edit_rounded,
            label: 'Change device / re-enter details',
            onPressed: flow.busy
                ? null
                : () => _openRegisterForm(mac: client.macAddress),
          ),
        ],
      ),
    );
  }

  // --- Active ---

  Widget _activeCard(Client client, LeaseFlowState flow) {
    return _sectionCard(
      title: 'Lease: Active',
      badge: _badge('Active', ThemeConstants.success),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (client.leaseDate != null) ...[
            _readonlyRow('Lease Date', _fmtDate(client.leaseDate!)),
            const SizedBox(height: 10),
          ],
          _readonlyRow('Lease ID', client.leaseId ?? '--', copyable: true),
          const SizedBox(height: 10),
          _readonlyRow('Device MAC', client.macAddress ?? '--'),
          const SizedBox(height: 16),
          if (_resetMode) ...[
            _label('New Password'),
            TextField(
              controller: _resetPwdCtrl,
              enabled: !flow.busy,
              obscureText: true,
              decoration: _fieldDecoration('Min 6 characters'),
              style: TextStyle(color: RefPalette.of(context).ink, fontSize: 15),
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
              AuthTextLink(
                label: 'Cancel',
                onTap: () {
                  if (!flow.busy) setState(() => _resetMode = false);
                },
              ),
            ]),
          ] else
            Row(children: [
              Expanded(
                child: _outlineButton(
                  icon: Icons.key_rounded,
                  label: 'Reset Password',
                  onPressed:
                      flow.busy ? null : () => setState(() => _resetMode = true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _outlineButton(
                  icon: Icons.power_off_rounded,
                  label: 'Deactivate',
                  danger: true,
                  onPressed: flow.busy ? null : _deactivate,
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
    final p = RefPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.cardline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
            ),
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
                color: color, fontSize: 12, fontWeight: FontWeight.w800)),
      );

  Widget _label(String text) => AuthLabel(text);

  Widget _readonlyRow(String label, String value, {bool copyable = false}) {
    final p = RefPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 96,
          child: Text(label,
              style: TextStyle(
                  color: p.ink2, fontSize: 13.5, fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  color: p.ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ),
        if (copyable && value != '--')
          Semantics(
            button: true,
            label: 'Copy $label',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                _snack('Copied');
              },
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(Icons.copy_rounded, size: 17, color: p.copperInk),
              ),
            ),
          ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String hint) =>
      authInputDecoration(context, hint: hint);

  Widget _primaryButton({
    IconData? icon,
    required String label,
    required VoidCallback? onPressed,
  }) =>
      AuthPrimaryButton(
        label: label,
        icon: icon ?? Icons.check_rounded,
        onTap: onPressed,
      );

  /// v6 tan action ("Pick a unit to hand off").
  Widget _softButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final p = RefPalette.of(context);
    return Opacity(
      opacity: onPressed == null ? .55 : 1,
      child: Material(
        color: p.tanSoft,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: SizedBox(
            height: 50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: p.copperInk),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: p.copperInk)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// White outline action; [danger] for Deactivate.
  Widget _outlineButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool danger = false,
  }) {
    final p = RefPalette.of(context);
    final fg = danger ? p.low : p.ink;
    return Opacity(
      opacity: onPressed == null ? .55 : 1,
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: danger ? p.low : p.cardline),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: fg)),
                ),
              ],
            ),
          ),
        ),
      ),
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
///
/// Already-connected units are folded in alongside the scan results: a BLE
/// peripheral stops advertising the moment it accepts a connection, so a device
/// connected from the Devices list can never appear in a scan and the picker
/// looked empty until the user went back and disconnected it.
class _DevicePickerSheet extends ConsumerStatefulWidget {
  final BleRepository repo;
  const _DevicePickerSheet({required this.repo});

  @override
  ConsumerState<_DevicePickerSheet> createState() => _DevicePickerSheetState();
}

class _DevicePickerSheetState extends ConsumerState<_DevicePickerSheet> {
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

  /// Units this app is already connected to, as scan-result entries. The
  /// synthesised advertisement declares the Hydra service UUID so [_isHydra]
  /// keeps them — the connector only ever connects to Hydra units, so that is
  /// an accurate claim, not a filter bypass.
  List<ScanResult> _connectedResults() {
    final ids = ref.read(bleConnectorProvider).connectedDeviceIds.toSet();
    if (ids.isEmpty) return const <ScanResult>[];

    const expected = BleConstants.preferredServiceUuid;
    final serviceUuids = <Guid>[
      if (expected != null && expected.isNotEmpty) Guid(expected),
    ];

    final now = DateTime.now();
    return [
      for (final device in FlutterBluePlus.connectedDevices)
        if (ids.contains(device.remoteId.str))
          ScanResult(
            device: device,
            advertisementData: AdvertisementData(
              advName: device.platformName,
              txPowerLevel: null,
              appearance: null,
              connectable: true,
              manufacturerData: const {},
              serviceData: const {},
              serviceUuids: serviceUuids,
            ),
            rssi: 0,
            timeStamp: now,
          ),
    ];
  }

  /// Live scan results plus the already-connected units, de-duped by remote id.
  List<ScanResult> _merge(List<ScanResult> scanned) {
    final byId = <String, ScanResult>{};
    for (final r in scanned) {
      byId[r.device.remoteId.str] = r;
    }
    for (final r in _connectedResults()) {
      byId.putIfAbsent(r.device.remoteId.str, () => r);
    }
    return byId.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4.5,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: p.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text('Pick a unit to hand off',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 19,
                          fontWeight: FontWeight.w800)),
                ),
                Text('Hydrawav only',
                    style: TextStyle(color: p.ink3, fontSize: 12)),
                Switch(
                  value: _hydraOnly,
                  activeThumbColor: Colors.white,
                  activeTrackColor: p.copper,
                  onChanged: (v) => setState(() => _hydraOnly = v),
                ),
              ],
            ),
            Text(
              'Connect to the matching unit to load its MAC ID.',
              style: TextStyle(color: p.ink3, fontSize: 13),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 340,
              child: StreamBuilder<List<ScanResult>>(
                stream: widget.repo.scanResults,
                initialData: widget.repo.currentScanResults,
                builder: (context, snapshot) {
                  final results =
                      _merge(snapshot.data ?? const <ScanResult>[])
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
                          SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(p.copper))),
                          const SizedBox(height: 12),
                          Text(
                              _hydraOnly
                                  ? 'Scanning for Hydrawav devices…'
                                  : 'Scanning for devices…',
                              style: TextStyle(color: p.ink2)),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final r = results[i];
                      final rawName = _nameOf(r);
                      final name =
                          rawName.isEmpty ? 'Unknown device' : rawName;
                      // Already-connected units are folded in with rssi 0.
                      final connected = r.rssi == 0;
                      return _UnitRow(
                        name: name,
                        id: r.device.remoteId.str,
                        rssi: connected ? null : r.rssi,
                        connected: connected,
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

/// v6 hand-off unit row: the unit tile, name, how it's reached + signal, and
/// "Available".
class _UnitRow extends StatelessWidget {
  final String name;
  final String id;
  final int? rssi;
  final bool connected;
  final VoidCallback onTap;
  const _UnitRow({
    required this.name,
    required this.id,
    required this.rssi,
    required this.connected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final meta = TextStyle(fontSize: 13, color: p.ink3);
    return Semantics(
      button: true,
      label: '$name, ${connected ? 'connected' : 'available'}',
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: p.cardline),
            ),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  const UnitMark(connected: true, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: p.ink)),
                        const SizedBox(height: 2),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 5,
                          children: [
                            Text(connected ? 'Bluetooth · connected' : id,
                                style: meta),
                            if (rssi != null) ...[
                              Text('·', style: meta),
                              SignalBars(signalOf(rssi!).bars),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: p.goodSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('Available',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: p.good)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
