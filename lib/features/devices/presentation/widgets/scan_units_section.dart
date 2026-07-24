import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/ble_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../ble/data/ble_repository.dart';
import '../../../ble/presentation/providers/auto_connect_provider.dart';
import '../../../ble/presentation/providers/ble_scan_provider.dart';
import '../../../session/domain/session_model.dart';
import '../../../session/presentation/providers/session_target_provider.dart';
import 'ref_palette.dart';

/// University-only "Your other units" scan/connect section — reuses the SAME
/// BLE providers as the standard device manager (`startScanProvider`,
/// `bleScanResultsProvider`, `bleRepositoryProvider.connectDevice`,
/// `bleConnectingIdsProvider`), so scanning and connecting behave identically.
/// Styled in the copper handoff design. BLE-only (WiFi has no local scan).
class ScanUnitsSection extends ConsumerWidget {
  const ScanUnitsSection({super.key});

  Future<void> _connect(
    BuildContext context,
    WidgetRef ref,
    ScanResult result,
    String name,
  ) async {
    final id = result.device.remoteId.str;
    final connecting = ref.read(bleConnectingIdsProvider);
    if (connecting.contains(id)) return;

    ref.read(bleConnectingIdsProvider.notifier).state = {...connecting, id};
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok =
          await ref.read(bleRepositoryProvider).connectDevice(result.device);
      messenger.showSnackBar(
        SnackBar(
          content: Text(ok ? 'Connected to $name' : 'Failed to connect to $name'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Connect failed: $e')));
    } finally {
      final cur = ref.read(bleConnectingIdsProvider);
      ref.read(bleConnectingIdsProvider.notifier).state = {...cur}..remove(id);
    }
  }

  /// Hydrawav-only filter + de-dupe, mirroring the standard device manager.
  List<ScanResult> _visible(List<ScanResult> list) {
    final byId = <String, ScanResult>{};
    for (final r in list) {
      byId.putIfAbsent(r.device.remoteId.str, () => r);
    }
    const expected = BleConstants.preferredServiceUuid;
    if (expected == null || expected.isEmpty) return byId.values.toList();
    final target = BleConstants.normalizeUuid(expected);
    return byId.values.where((r) {
      return r.advertisementData.serviceUuids
          .any((u) => BleConstants.normalizeUuid(u.str) == target);
    }).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    // Scan is a Bluetooth concept — hidden in WiFi mode (parity with the ref).
    if (ref.watch(sessionTargetProvider).transport != SessionTransport.ble) {
      return const SizedBox.shrink();
    }

    final scanAsync = ref.watch(bleScanResultsProvider);
    final connectingIds = ref.watch(bleConnectingIdsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // eyebrow + Scan button.
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'YOUR OTHER UNITS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: p.copperInk,
                  ),
                ),
              ),
              _ScanBtn(palette: p, onTap: () => ref.read(startScanProvider)()),
            ],
          ),
        ),
        scanAsync.when(
          loading: () => _hint(p, 'Scanning…'),
          error: (e, _) => _hint(p, 'Scan error: $e'),
          data: (list) {
            final visible = _visible(list);
            if (visible.isEmpty) {
              return _hint(
                p,
                'No units found yet. Tap Scan and make sure your unit is on.',
              );
            }
            return Column(
              children: [
                for (final r in visible)
                  _AvailRow(
                    palette: p,
                    name: r.device.platformName.isNotEmpty
                        ? r.device.platformName
                        : 'Unknown unit',
                    mac: r.device.remoteId.str,
                    connecting:
                        connectingIds.contains(r.device.remoteId.str),
                    onConnect: () => _connect(
                      context,
                      ref,
                      r,
                      r.device.platformName.isNotEmpty
                          ? r.device.platformName
                          : 'unit',
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        // "＋ Add a new unit · Device Center" — moved here from the header.
        _AddUnitButton(
          palette: p,
          onTap: () => context.push(RoutePaths.deviceRegister),
        ),
      ],
    );
  }

  Widget _hint(RefPalette p, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          text,
          style: TextStyle(fontSize: 12, height: 1.4, color: p.ink3),
        ),
      );
}

/// Reference `.btn.ghost.sm` — full-width "Add a new unit · Device Center".
class _AddUnitButton extends StatelessWidget {
  final RefPalette palette;
  final VoidCallback onTap;
  const _AddUnitButton({required this.palette, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: p.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 16, color: p.ink2),
              const SizedBox(width: 6),
              Text(
                'Add a new unit · Device Center',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: p.ink2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reference `.devbtn` — the "Scan" affordance.
class _ScanBtn extends StatelessWidget {
  final RefPalette palette;
  final VoidCallback onTap;
  const _ScanBtn({required this.palette, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: p.copper, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.radar_rounded, size: 14, color: p.copperInk),
              const SizedBox(width: 5),
              Text(
                'Scan',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: p.copperInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An available (offline) unit row with a Connect button — reference `avail`.
class _AvailRow extends StatelessWidget {
  final RefPalette palette;
  final String name;
  final String mac;
  final bool connecting;
  final VoidCallback onConnect;
  const _AvailRow({
    required this.palette,
    required this.name,
    required this.mac,
    required this.connecting,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.cardline),
        boxShadow: p.shadow,
      ),
      child: Row(
        children: [
          // .devring off — grey gradient.
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF9C948B), Color(0xFF6E675F)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.graphic_eq_rounded,
                size: 17, color: Colors.white),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '$mac · last seen offline',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.ink2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // .btn.dark.sm — Connect.
          Material(
            borderRadius: BorderRadius.circular(13),
            child: InkWell(
              borderRadius: BorderRadius.circular(13),
              onTap: connecting ? null : onConnect,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  gradient: p.heroGrad,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: connecting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Color(0xFFF2E9E2)),
                        ),
                      )
                    : const Text(
                        'Connect',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF2E9E2),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
