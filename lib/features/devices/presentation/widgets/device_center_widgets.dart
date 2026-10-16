import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_tablet.dart';
import '../../../ble/domain/ble_device_model.dart';
import '../../../ble/presentation/providers/ble_connection_provider.dart';
import '../../../session/presentation/providers/busy_devices_provider.dart';
import '../../domain/device_model.dart';
import '../providers/wifi_devices_provider.dart';
import '../screens/device_list_screen.dart' show pairedDevicesProvider;

/// How a registered unit is reachable right now. Only a Bluetooth link is
/// known to the app; anything else reads as "not connected".
class UnitLink {
  /// The connected Bluetooth peripheral id (MAC on Android, UUID on iOS).
  final String? bleId;
  final bool busy;
  const UnitLink({this.bleId, this.busy = false});
  bool get connected => bleId != null;
}

String _norm(String mac) => mac.trim().toUpperCase().replaceAll('-', ':');

/// [candidates] are the MACs the unit may advertise (its own and ±1 — the
/// firmware's BLE MAC is off by one, see `_bleConnectCandidates`).
UnitLink watchUnitLink(WidgetRef ref, DeviceInfo d, List<String> candidates) {
  final paired = ref.watch(pairedDevicesProvider).valueOrNull ?? const [];
  final wanted = {for (final c in candidates) _norm(c)};
  String? id;
  for (final p in paired) {
    final pm = _norm(p.macAddress);
    if (!wanted.contains(pm) && !wanted.contains(_norm(p.id))) continue;
    if (ref.watch(bleDeviceStatusProvider(p.id)) ==
        BleConnectionStatus.connected) {
      id = p.id;
      break;
    }
  }
  final busy = macAddressVariants(d.macAddress)
      .any((v) => ref.watch(isDeviceBusyProvider(v)));
  return UnitLink(bleId: id, busy: busy);
}

/// Live signal of a connected unit, in dBm (null when it can't be read).
final unitRssiProvider =
    FutureProvider.autoDispose.family<int?, String>((ref, bleId) async {
  try {
    return await BluetoothDevice.fromId(bleId).readRssi();
  } catch (_) {
    return null;
  }
});

({int bars, String word}) signalOf(int rssi) {
  if (rssi >= -60) return (bars: 3, word: 'Strong signal');
  if (rssi >= -75) return (bars: 2, word: 'Good signal');
  return (bars: 1, word: 'Weak signal');
}

/// `.sigbars` — three rising bars, green / amber / red by strength.
class SignalBars extends StatelessWidget {
  final int bars;
  const SignalBars(this.bars, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final c = bars >= 3 ? p.good : (bars == 2 ? p.mid : p.low);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            margin: const EdgeInsets.only(right: 1.5),
            width: 3,
            height: 5.0 + i * 3,
            decoration: BoxDecoration(
              color: i < bars ? c : p.line,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
      ],
    );
  }
}

/// The unit's mark: a rounded tile with the wave, copper when linked over
/// Bluetooth, grey when not, with a status dot.
class UnitMark extends StatelessWidget {
  final bool connected;
  final double size;
  const UnitMark({super.key, required this.connected, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return SizedBox(
      width: size + 4,
      height: size + 4,
      child: Stack(
        children: [
          Container(
            width: size,
            height: size,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * .3),
              gradient: connected
                  ? p.sunGrad
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFA39A92), Color(0xFF7D746C)],
                    ),
            ),
            child: Icon(Icons.waves_rounded,
                color: Colors.white, size: size * .46),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: connected ? p.good : p.ink3,
                border: Border.all(color: p.card, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ready / In use / Not connected.
class UnitStatusPill extends StatelessWidget {
  final UnitLink link;
  const UnitStatusPill(this.link, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final (label, fg, bg, border) = link.busy
        ? ('In use', p.copperInk, p.tanSoft, Colors.transparent)
        : link.connected
            ? ('Ready', p.good, p.goodSoft, Colors.transparent)
            : ('Not connected', p.ink3, Colors.transparent, p.cardline);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}

/// One unit in the Device Center list (v6 `.devcard`).
class DeviceUnitCard extends ConsumerWidget {
  final DeviceInfo device;
  final List<String> candidates;
  final VoidCallback onTap;
  const DeviceUnitCard({
    super.key,
    required this.device,
    required this.candidates,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final link = watchUnitLink(ref, device, candidates);
    final rssi = link.bleId == null
        ? null
        : ref.watch(unitRssiProvider(link.bleId!)).valueOrNull;
    final fw = device.firmware?.trim();
    final meta = TextStyle(fontSize: 13, color: p.ink3);

    return Semantics(
      button: true,
      label: '${device.name}, '
          '${link.busy ? 'in use' : link.connected ? 'ready' : 'not connected'}',
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: p.cardline),
            ),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  UnitMark(connected: link.connected),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: p.ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 5,
                          runSpacing: 2,
                          children: [
                            Text(
                              link.connected
                                  ? 'Bluetooth · direct'
                                  : 'Not connected',
                              style: meta,
                            ),
                            if (rssi != null) ...[
                              Text('·', style: meta),
                              SignalBars(signalOf(rssi).bars),
                            ],
                            if (fw != null && fw.isNotEmpty) ...[
                              Text('·', style: meta),
                              Text('fw $fw', style: meta),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  UnitStatusPill(link),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// v6 `renderDevDetail` — one unit: its name, status, facts and every action
/// the Device Center offers, each calling the same flow as before.
class DeviceDetailPage extends ConsumerWidget {
  final DeviceInfo device;
  final List<String> candidates;
  final VoidCallback onRename;
  final VoidCallback onWifi;
  final VoidCallback onLocate;
  final VoidCallback onReport;
  final VoidCallback onHandOff;
  final VoidCallback onUnregister;

  const DeviceDetailPage({
    super.key,
    required this.device,
    required this.candidates,
    required this.onRename,
    required this.onWifi,
    required this.onLocate,
    required this.onReport,
    required this.onHandOff,
    required this.onUnregister,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    // Follow the list so a rename shows here, and leave once the unit has
    // been unregistered.
    final list = ref.watch(wifiDevicesByOrgProvider).valueOrNull;
    final live = list
            ?.where((x) =>
                (device.id != null && x.id == device.id) ||
                _norm(x.macAddress) == _norm(device.macAddress))
            .firstOrNull ??
        device;
    if (list != null &&
        !list.any((x) =>
            (device.id != null && x.id == device.id) ||
            _norm(x.macAddress) == _norm(device.macAddress))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
    }

    final link = watchUnitLink(ref, live, candidates);
    final rssi = link.bleId == null
        ? null
        : ref.watch(unitRssiProvider(link.bleId!)).valueOrNull;
    final fw = live.firmware?.trim();
    final tablet = HwTablet.of(context);

    Widget infoRow(String k, Widget v, {bool last = false}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: last ? null : Border(bottom: BorderSide(color: p.divider)),
          ),
          child: Row(
            children: [
              Text(k,
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: p.ink)),
              const SizedBox(width: 12),
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: v),
              ),
            ],
          ),
        );
    TextStyle val() => TextStyle(fontSize: 14, color: p.ink3);

    final rows = <(String, Widget)>[
      (
        'Connection',
        Text(link.connected ? 'Bluetooth · direct' : 'Not connected',
            style: val())
      ),
      if (rssi != null)
        (
          'Signal',
          Text('${signalOf(rssi).word} ($rssi dBm)', style: val()),
        ),
      if (fw != null && fw.isNotEmpty) ('Firmware', Text(fw, style: val())),
      (
        'MAC ID',
        Text(live.macAddress,
            style: val()
                .copyWith(fontFeatures: const [FontFeature.tabularFigures()]))
      ),
      ('Pads', Text('1 Sun ☀ + 1 Moon ☾', style: val())),
    ];

    Widget soft(String label, IconData icon, VoidCallback onTap) => Material(
          color: p.tanSoft,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: p.copperInk),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: p.copperInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    BoxDecoration card() => BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.cardline),
        );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── name ───────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Unit name',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: p.ink2)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: p.bg2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.cardline),
                ),
                child: Text(live.name,
                    style: TextStyle(fontSize: 15, color: p.ink)),
              ),
              const SizedBox(height: 12),
              Semantics(
                button: true,
                child: Material(
                  color: const Color(0xFF1F2B33),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: onRename,
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                      child: Text(
                        'Rename — sent over Bluetooth',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── facts ──────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: card(),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                infoRow(rows[i].$1, rows[i].$2, last: i == rows.length - 1),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── actions ────────────────────────────────────────────────────────
        soft('Update WiFi network', Icons.wifi_rounded, onWifi),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: soft('Locate', Icons.my_location_rounded, onLocate)),
            const SizedBox(width: 10),
            Expanded(
                child:
                    soft('Device report', Icons.fact_check_rounded, onReport)),
          ],
        ),
        const SizedBox(height: 14),

        // ── lease ──────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Device lease',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: p.ink)),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: p.cardline),
                    ),
                    child: Text('Hand-off',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: p.ink3)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Hand this unit to a client for at-home sessions. Pick the '
                'client in Users to set up the lease.',
                style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink3),
              ),
              const SizedBox(height: 12),
              Material(
                color: p.tanSoft,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onHandOff,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Text('Start hand-off',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: p.copperInk)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── unregister ─────────────────────────────────────────────────────
        Material(
          color: p.card,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onUnregister,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.cardline),
              ),
              child: Text('Unregister unit',
                  style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: p.low)),
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            HwTablet.sidePadding(context, column: HwTablet.wide, phone: 16),
            10,
            HwTablet.sidePadding(context, column: HwTablet.wide, phone: 16),
            28,
          ),
          children: [
            // ── header ──────────────────────────────────────────────────────
            Row(
              children: [
                Semantics(
                  button: true,
                  label: 'Back',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.card,
                        border: Border.all(color: p.cardline),
                      ),
                      child: Icon(Icons.chevron_left_rounded,
                          color: p.ink2, size: 26),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(live.name,
                          style: TextStyle(
                              fontSize: tablet ? 20 : 19,
                              fontWeight: FontWeight.w800,
                              color: p.ink)),
                      const SizedBox(height: 2),
                      Text(
                          link.connected
                              ? 'Bluetooth · direct'
                              : 'Not connected',
                          style: TextStyle(fontSize: 13, color: p.ink3)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                UnitStatusPill(link),
              ],
            ),
            const SizedBox(height: 16),
            content,
          ],
        ),
      ),
    );
  }
}
