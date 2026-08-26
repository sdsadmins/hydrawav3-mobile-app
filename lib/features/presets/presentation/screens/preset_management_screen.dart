import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/storage/local_db.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_icon.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../protocols/presentation/providers/protocol_provider.dart';
import '../../data/preset_repository.dart';
import '../providers/preset_provider.dart';

/// Quick Presets — ported from the UI spec's `renderPresets()` (app.js:2590).
///
/// Always exactly three slots. Filled slots come from the local preset
/// database; empty ones show the spec's dashed placeholder. Nothing here is
/// hard-coded — this screen previously displayed a fabricated preset name
/// with a dead tap handler, while `PresetRepository` sat fully implemented and
/// unused.
class PresetManagementScreen extends ConsumerWidget {
  const PresetManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final async = ref.watch(presetListProvider);
    final presets = async.valueOrNull ?? const <Preset>[];

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 108),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HwBackBar(
                title: 'Quick Presets',
                subtitle: '${presets.length} of ${AppConstants.maxPresets} '
                    'slots · one-tap setups',
                onBack: () => _back(context),
              ),
              const SizedBox(height: HwSpace.s2),
              if (async.hasError)
                HwCard(
                  child: Text(
                    "Couldn't load your presets.",
                    style: TextStyle(fontSize: HwType.sm, color: p.ink2),
                  ),
                )
              else
                for (var i = 0; i < AppConstants.maxPresets; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: i < presets.length
                        ? _FilledSlot(preset: presets[i])
                        : const _EmptySlot(),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  static void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.settings);
    }
  }
}

class _FilledSlot extends ConsumerWidget {
  final Preset preset;
  const _FilledSlot({required this.preset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    // The protocol name is the useful half of the summary; fall back to a
    // neutral label only while the catalogue is still loading.
    final protocol = ref.watch(protocolDetailProvider(preset.protocolId));

    return HwCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Text('☆', style: TextStyle(fontSize: 22, color: p.copper)),
          const SizedBox(width: HwSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preset.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: HwType.base,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  protocol.maybeWhen(
                    data: (d) => d.templateName,
                    orElse: () => 'Saved setup',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: HwType.cap, color: p.ink3),
                ),
              ],
            ),
          ),
          const SizedBox(width: HwSpace.s2),
          HwPress(
            onTap: () => _run(context, ref),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: p.sunGrad,
                borderRadius: BorderRadius.circular(HwRadius.sm),
              ),
              child: const Text(
                'Run',
                style: TextStyle(
                  fontSize: HwType.sm,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: HwSpace.s2),
          HwIconButton(
            asset: HwIcons.x,
            size: 34,
            onTap: () => _delete(context, ref),
          ),
        ],
      ),
    );
  }

  void _run(BuildContext context, WidgetRef ref) {
    // A preset is a saved session configuration, so running it hands the
    // Session tab the protocol and lets the practitioner pick the unit.
    ref.read(recentProtocolIdsProvider.notifier).recordUsed(preset.protocolId);
    context.go(RoutePaths.devices);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(presetRepositoryProvider).deletePreset(preset.id);
    messenger.showSnackBar(const SnackBar(content: Text('Preset removed')));
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(HwRadius.lg),
        border: Border.all(color: p.line, width: 1.5),
      ),
      child: Text(
        'Empty slot: save a setup here from any session.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: HwType.cap, height: 1.4, color: p.ink3),
      ),
    );
  }
}
