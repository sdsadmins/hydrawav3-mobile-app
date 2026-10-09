import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_tablet.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../widgets/client_lease_section.dart';

/// v6 "Player hand-off" (University) / "Client hand-off" (clinic). The lease
/// UI + BLE/API handshake lives in [ClientLeaseSection]; this screen adds the
/// v6 header and the "What a lease does" card above it.
class ClientLeaseScreen extends ConsumerWidget {
  final String clientId;

  /// The client's display name (passed by Users and the profile).
  final String? title;

  const ClientLeaseScreen({super.key, required this.clientId, this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final university =
        (ref.watch(authStateProvider).user?.organizationType ?? '')
                .toUpperCase() ==
            'UNIVERSITY';
    final name = (title ?? '').trim();
    final who = name.isEmpty ? (university ? 'the player' : 'the client') : name;
    // Tablet: centred 680px reading column (v6 `97-tablet`).
    final side = HwTablet.sidePadding(context, column: HwTablet.read, phone: 16);

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(side, 10, side, 32),
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        university ? 'Player hand-off' : 'Client hand-off',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: p.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        name.isEmpty ? 'Device lease' : '$name · device lease',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: p.ink3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── what a lease does ───────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: p.cardline),
                boxShadow: p.shadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'What a lease does',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: p.ink,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: p.tanSoft,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Client mode',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: p.copperInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Loads a lease ID onto a unit over Bluetooth so $who can '
                    'take it home and run sessions on their own in the '
                    'Hydrawav3 app.',
                    style: TextStyle(fontSize: 14, height: 1.4, color: p.ink2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            ClientLeaseSection(clientId: clientId),
          ],
        ),
      ),
    );
  }
}
