import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_icon.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../domain/warranty_model.dart';
import '../providers/warranty_provider.dart';

/// Warranty — one card per registered device, `GET warranty/:orgId`.
///
/// Same shape as [NotificationsScreen]: `HwBackBar` + async.when(loading /
/// error / data) into an `HwRowGroup`/`HwCard` stack, so it reads as part of
/// the same app rather than a bolted-on screen.
class WarrantyScreen extends ConsumerWidget {
  const WarrantyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final async = ref.watch(warrantyByOrgProvider);
    final list = async.valueOrNull ?? const <WarrantyRecord>[];
    final activeCount = list.where((w) => w.isActive).length;

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
                title: 'Warranty',
                subtitle: async.hasValue
                    ? (list.isEmpty
                        ? 'No registered devices'
                        : '$activeCount of ${list.length} covered')
                    : null,
                onBack: () => _back(context),
              ),
              const SizedBox(height: HwSpace.s2),
              async.when(
                loading: () => HwCard(
                  child: Text(
                    'Loading…',
                    style: TextStyle(fontSize: HwType.cap, color: p.ink3),
                  ),
                ),
                error: (_, __) => HwCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Couldn't load warranty status.",
                          style:
                              TextStyle(fontSize: HwType.cap, color: p.ink2),
                        ),
                      ),
                      HwPress(
                        onTap: () => ref.invalidate(warrantyByOrgProvider),
                        child: Text(
                          'Retry',
                          style: TextStyle(
                            fontSize: HwType.cap,
                            fontWeight: FontWeight.w700,
                            color: p.copperInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                data: (items) => items.isEmpty
                    ? HwCard(
                        child: Text(
                          'No devices registered to this organization yet.',
                          style: TextStyle(
                              fontSize: HwType.sm,
                              height: 1.45,
                              color: p.ink2),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final w in items) ...[
                            _WarrantyCard(w),
                            const SizedBox(height: HwSpace.s3),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.settings);
    }
  }
}

class _WarrantyCard extends StatelessWidget {
  final WarrantyRecord warranty;
  const _WarrantyCard(this.warranty);

  /// Loose, forward-compatible: anything not recognized falls back to a
  /// neutral pill rather than a blank/crashing one, so a new backend status
  /// value never breaks this screen.
  (String, HwPillTone) get _statusDisplay {
    switch (warranty.status) {
      case 'ACTIVE':
        return ('Active', HwPillTone.good);
      case 'NO_WARRANTY':
        return ('No warranty', HwPillTone.ghost);
      case 'EXPIRED':
        return ('Expired', HwPillTone.low);
      default:
        return (
          warranty.status.isEmpty ? 'Unknown' : warranty.status,
          HwPillTone.mid,
        );
    }
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final (statusLabel, statusTone) = _statusDisplay;
    final hasDates = warranty.startDate != null || warranty.endDate != null;

    return HwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 30,
                child: Center(
                  child: HwIcon(HwIcons.doc, size: 19, color: p.copperInk),
                ),
              ),
              const SizedBox(width: HwSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      warranty.deviceName.isEmpty
                          ? warranty.macAddress
                          : warranty.deviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: HwType.base,
                        fontWeight: FontWeight.w600,
                        color: p.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      warranty.macAddress,
                      style: TextStyle(
                        fontSize: HwType.cap,
                        color: p.ink3,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HwSpace.s2),
              HwPill(statusLabel, tone: statusTone),
            ],
          ),
          if (warranty.product != null || warranty.edition != null) ...[
            const SizedBox(height: HwSpace.s3),
            Wrap(
              spacing: HwSpace.s2,
              runSpacing: 6,
              children: [
                if (warranty.product != null)
                  HwPill(warranty.product!, tone: HwPillTone.copper),
                if (warranty.edition != null)
                  HwPill(warranty.edition!, tone: HwPillTone.info),
              ],
            ),
          ],
          if (hasDates || warranty.warrantyDurationMonths != null) ...[
            const SizedBox(height: HwSpace.s3),
            Text(
              [
                if (warranty.startDate != null)
                  'Activated ${_fmtDate(warranty.startDate)}',
                if (warranty.endDate != null)
                  'Expires ${_fmtDate(warranty.endDate)}',
                if (warranty.warrantyDurationMonths != null)
                  '${warranty.warrantyDurationMonths} mo term',
              ].join(' · '),
              style: TextStyle(fontSize: HwType.cap, color: p.ink2),
            ),
          ],
          if (warranty.features.isNotEmpty) ...[
            const SizedBox(height: HwSpace.s3),
            _DetailList(title: 'What\'s covered', items: warranty.features),
          ],
          if (warranty.coverage.isNotEmpty) ...[
            const SizedBox(height: HwSpace.s3),
            _DetailList(title: 'Coverage', items: warranty.coverage),
          ],
        ],
      ),
    );
  }
}

class _DetailList extends StatelessWidget {
  final String title;
  final List<WarrantyDetail> items;
  const _DetailList({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: HwType.eyebrow,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: p.ink3,
          ),
        ),
        const SizedBox(height: 4),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: HwType.cap, color: p.ink2, height: 1.4),
                children: [
                  TextSpan(
                    text: item.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (item.description.isNotEmpty)
                    TextSpan(text: ' — ${item.description}'),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
