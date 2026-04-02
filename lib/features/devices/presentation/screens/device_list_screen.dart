import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/premium.dart';

// ─── Demo data ───

enum _ConnectionType { ble, wifi }

class _DemoDevice {
  final String id, name, serial, version;
  final bool connected;
  final _ConnectionType type;
  final int? battery;
  final int? signalStrength;

  _DemoDevice(
    this.id,
    this.name,
    this.serial,
    this.version, {
    this.connected = false,
    this.type = _ConnectionType.ble,
    this.battery,
    this.signalStrength,
  });
}

final _devices = [
  _DemoDevice(
    'd1',
    'Hydrawav3 Pro',
    'HW3-PRO-A1B2C3',
    'v1.0.2',
    connected: true,
    type: _ConnectionType.ble,
    battery: 85,
    signalStrength: -45,
  ),
  _DemoDevice(
    'd2',
    'Hydrawav3 Mini',
    'HW3-MINI-D4E5F6',
    'v1.1.5',
    type: _ConnectionType.ble,
    signalStrength: -62,
  ),
  _DemoDevice(
    'd3',
    'Hydrawav3 Pro',
    'HW3-PRO-G7H8I9',
    'v1.2.1',
    type: _ConnectionType.wifi,
    signalStrength: -38,
  ),
];

// ─── Screen ───

class DeviceListScreen extends ConsumerStatefulWidget {
  const DeviceListScreen({super.key});

  @override
  ConsumerState<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends ConsumerState<DeviceListScreen>
    with SingleTickerProviderStateMixin {
  _ConnectionType _scanType = _ConnectionType.ble;
  bool _isScanning = false;
  late AnimationController _scanAnimController;

  bool get _hasConnected => _devices.any((d) => d.connected);
  List<_DemoDevice> get _connectedDevices =>
      _devices.where((d) => d.connected).toList();
  List<_DemoDevice> get _availableDevices =>
      _devices.where((d) => !d.connected).toList();

  @override
  void initState() {
    super.initState();
    _scanAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _scanAnimController.dispose();
    super.dispose();
  }

  void _startScan() {
    if (_isScanning) return;
    setState(() => _isScanning = true);
    _scanAnimController.repeat();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _scanAnimController.stop();
        _scanAnimController.reset();
        setState(() => _isScanning = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(RoutePaths.deviceRegister),
        backgroundColor: ThemeConstants.accentDark,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Header ──
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1E3040), ThemeConstants.background],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: AnimatedEntrance(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Devices',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: ThemeConstants.textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (_hasConnected)
                          GestureDetector(
                            onTap: () => context.pop(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: ThemeConstants.accentDark,
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: [
                                  BoxShadow(
                                    color: ThemeConstants.accentDark
                                        .withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Text(
                                'Done',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── BLE / WiFi Toggle ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            sliver: SliverToBoxAdapter(
              child: AnimatedEntrance(
                index: 1,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: ThemeConstants.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ThemeConstants.border),
                  ),
                  child: Row(
                    children: [
                      _ToggleButton(
                        label: 'Bluetooth',
                        icon: Icons.bluetooth_rounded,
                        active: _scanType == _ConnectionType.ble,
                        onTap: () =>
                            setState(() => _scanType = _ConnectionType.ble),
                      ),
                      _ToggleButton(
                        label: 'WiFi',
                        icon: Icons.wifi_rounded,
                        active: _scanType == _ConnectionType.wifi,
                        onTap: () =>
                            setState(() => _scanType = _ConnectionType.wifi),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Scan Button ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            sliver: SliverToBoxAdapter(
              child: AnimatedEntrance(
                index: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: _startScan,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: ThemeConstants.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: ThemeConstants.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: _scanAnimController,
                            builder: (context, child) {
                              return Transform.rotate(
                                angle: _scanAnimController.value * 2 * math.pi,
                                child: child,
                              );
                            },
                            child: Icon(
                              Icons.refresh_rounded,
                              size: 16,
                              color: _isScanning
                                  ? ThemeConstants.accent
                                  : ThemeConstants.metallic400,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isScanning ? 'Scanning...' : 'Scan for Devices',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _isScanning
                                  ? ThemeConstants.accent
                                  : ThemeConstants.metallic400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Connected Section ──
          if (_connectedDevices.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              sliver: SliverToBoxAdapter(
                child: AnimatedEntrance(
                  index: 3,
                  child: const _SectionLabel(title: 'Connected'),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    return AnimatedEntrance(
                      index: i + 4,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ConnectedDeviceCard(
                          device: _connectedDevices[i],
                        ),
                      ),
                    );
                  },
                  childCount: _connectedDevices.length,
                ),
              ),
            ),
          ],

          // ── Available Devices Section ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            sliver: SliverToBoxAdapter(
              child: AnimatedEntrance(
                index: 5,
                child: _SectionLabel(
                  title: _scanType == _ConnectionType.ble
                      ? 'Available Bluetooth Devices'
                      : 'Available WiFi Devices',
                ),
              ),
            ),
          ),
          if (_availableDevices.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              sliver: SliverToBoxAdapter(
                child: AnimatedEntrance(
                  index: 6,
                  child: _EmptyDevicesCard(
                    scanType: _scanType,
                    onRetry: _startScan,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    return AnimatedEntrance(
                      index: i + 6,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _AvailableDeviceCard(
                          device: _availableDevices[i],
                        ),
                      ),
                    );
                  },
                  childCount: _availableDevices.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Toggle Button ───

class _ToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? ThemeConstants.accentDark : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: ThemeConstants.accentDark.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: active
                    ? Colors.white
                    : ThemeConstants.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: active
                      ? Colors.white
                      : ThemeConstants.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Section Label ───

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: ThemeConstants.textSecondary,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

// ─── Connected Device Card (full-width gradient) ───

class _ConnectedDeviceCard extends StatelessWidget {
  final _DemoDevice device;
  const _ConnectedDeviceCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final isBle = device.type == _ConnectionType.ble;
    final typeIcon = isBle ? Icons.bluetooth_rounded : Icons.wifi_rounded;
    final typeLabel = isBle ? 'Bluetooth' : 'WiFi';

    return GestureDetector(
      onTap: () => context.push('/devices/${device.id}'),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [ThemeConstants.accentDark, ThemeConstants.accent],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: ThemeConstants.accentLight.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2C1810).withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Large background icon
            Positioned(
              right: -10,
              bottom: -10,
              child: Icon(
                typeIcon,
                size: 100,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: type label + battery
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Device type label
                      Row(
                        children: [
                          Icon(typeIcon, size: 14, color: Colors.white.withValues(alpha: 0.8)),
                          const SizedBox(width: 6),
                          Text(
                            typeLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                      // Battery badge
                      if (device.battery != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            color: Colors.black.withValues(alpha: 0.2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _batteryIcon(device.battery!),
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${device.battery}%',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Device name
                  Text(
                    device.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Serial number
                  Text(
                    device.serial,
                    style: TextStyle(
                      fontSize: 13,
                      color: const Color(0xFFE8C9A0).withValues(alpha: 0.8),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Action buttons row
                  Row(
                    children: [
                      // Disconnect button
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Disconnecting...'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Text(
                                'Disconnect',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Settings gear button
                      GestureDetector(
                        onTap: () => context.push('/devices/${device.id}'),
                        child: Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.settings_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _batteryIcon(int level) {
    if (level >= 90) return Icons.battery_full_rounded;
    if (level >= 60) return Icons.battery_5_bar_rounded;
    if (level >= 30) return Icons.battery_3_bar_rounded;
    return Icons.battery_1_bar_rounded;
  }
}

// ─── Available Device Card ───

class _AvailableDeviceCard extends StatefulWidget {
  final _DemoDevice device;
  const _AvailableDeviceCard({required this.device});

  @override
  State<_AvailableDeviceCard> createState() => _AvailableDeviceCardState();
}

class _AvailableDeviceCardState extends State<_AvailableDeviceCard>
    with SingleTickerProviderStateMixin {
  bool _connecting = false;
  late AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  void _connect() {
    if (_connecting) return;
    setState(() => _connecting = true);
    _spinController.repeat();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _spinController.stop();
        _spinController.reset();
        setState(() => _connecting = false);
        context.push('/devices/${widget.device.id}');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isBle = widget.device.type == _ConnectionType.ble;
    final typeIcon = isBle ? Icons.bluetooth_rounded : Icons.wifi_rounded;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeConstants.border),
      ),
      child: Row(
        children: [
          // Icon circle
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: ThemeConstants.background,
              shape: BoxShape.circle,
              border: Border.all(color: ThemeConstants.border),
            ),
            child: Icon(
              typeIcon,
              size: 22,
              color: ThemeConstants.metallic400,
            ),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.device.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ThemeConstants.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    // Signal strength
                    if (widget.device.signalStrength != null) ...[
                      const Icon(
                        Icons.signal_cellular_alt_rounded,
                        size: 12,
                        color: ThemeConstants.success,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.device.signalStrength} dBm',
                        style: const TextStyle(
                          fontSize: 11,
                          color: ThemeConstants.success,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    // Firmware version
                    Text(
                      widget.device.version,
                      style: const TextStyle(
                        fontSize: 11,
                        color: ThemeConstants.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Connect button
          GestureDetector(
            onTap: _connect,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(
                horizontal: _connecting ? 14 : 18,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: _connecting
                    ? ThemeConstants.accentDark
                    : ThemeConstants.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: _connecting
                  ? AnimatedBuilder(
                      animation: _spinController,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _spinController.value * 2 * math.pi,
                          child: child,
                        );
                      },
                      child: const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : const Text(
                      'Connect',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ThemeConstants.textPrimary,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty Devices Card ───

class _EmptyDevicesCard extends StatelessWidget {
  final _ConnectionType scanType;
  final VoidCallback onRetry;

  const _EmptyDevicesCard({
    required this.scanType,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isBle = scanType == _ConnectionType.ble;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ThemeConstants.border,
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Icon(
            isBle ? Icons.bluetooth_disabled_rounded : Icons.wifi_off_rounded,
            size: 48,
            color: ThemeConstants.textTertiary,
          ),
          const SizedBox(height: 16),
          const Text(
            'No devices found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: ThemeConstants.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isBle
                ? 'Make sure your device is powered on and in pairing mode'
                : 'Ensure your device is connected to the same network',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: ThemeConstants.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onRetry,
            child: const Text(
              'Try Again',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ThemeConstants.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
