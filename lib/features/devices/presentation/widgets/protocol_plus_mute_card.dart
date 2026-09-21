import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../home/presentation/providers/hub_prefs_provider.dart';
import 'ref_palette.dart';

/// Global, opt-in switch for Protocol Plus's "2 beeps only" behaviour.
///
/// Off (default): the firmware beeps on every sub-protocol switch, as usual.
/// On: the app arms the firmware's `{"muteSeconds": N}` window (~10s before
/// protocol[0] ends) so a multi-stage Plus run beeps only at the very first
/// start and the very last end. See `SessionEngine._maybeArmPlusMute`.
///
/// Thin wrapper around [ProtocolPlusMuteRow] — its own full-width
/// `.togglecard`. Kept for any caller that wants it alone; the Devices List
/// screen stacks [ProtocolPlusMuteRow] with [SessionMusicRow] inside one
/// shared card instead.
class ProtocolPlusMuteCard extends StatelessWidget {
  const ProtocolPlusMuteCard({super.key});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: p.cardline, width: 1.5),
      ),
      child: const ProtocolPlusMuteRow(),
    );
  }
}

/// The Plus-mute `.togglecard`'s CONTENT only — icon, label/subtitle, switch
/// — with no outer card of its own, so it can be stacked with other rows
/// inside a shared [Container]. See [ProtocolPlusMuteCard] for the
/// standalone card version.
class ProtocolPlusMuteRow extends ConsumerWidget {
  const ProtocolPlusMuteRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final on = ref.watch(protocolPlusMuteEnabledProvider);
    final notifier = ref.read(protocolPlusMuteEnabledProvider.notifier);

    return Row(
      children: [
        SizedBox(
          width: 26,
          child: Icon(
            on ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            size: 18,
            color: p.copperInk,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: InkWell(
            onTap: () => notifier.setEnabled(!on),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Protocol Plus: 2 beeps only',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: p.ink,
                  ),
                ),
                Text(
                  on ? 'On, muted mid-stack' : 'Off, beeps every switch',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, height: 1.4, color: p.ink3),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // .sw — on when the Plus mute setting is enabled.
        GestureDetector(
          onTap: () => notifier.setEnabled(!on),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 46,
            height: 27,
            decoration: BoxDecoration(
              color: on ? p.copper : p.bg2,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: on ? p.copper : p.line),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Container(
                  width: 19,
                  height: 19,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x47000000),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
