import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/ai_report_repository.dart';
import '../providers/ai_report_providers.dart';

/// Paginated history of generated AI reports, in the UI handoff's reports-list
/// form (`renderReports()`, app.js:2763).
///
/// THE MERGE. `GET ai-reports/all` only ever returns COMPLETED reports, so a
/// report being generated right now exists solely as a job in
/// `aiReportGenerationProvider`. The spec's list shows Generating / Ready /
/// Failed together, so in-flight jobs are merged in on top of the server page:
///
///   * busy job    → a `Generating` row, prepended (the spec `unshift`s), inert
///   * failed job  → a `Failed` row carrying the error line, with Dismiss
///   * done job    → shown as `Ready` from its in-memory result, and DROPPED as
///                   soon as a server row with the same `_id` arrives, so the
///                   report never appears twice
///
/// Rendered as a non-scrolling [Column] (pagination is button-driven) so it can
/// be embedded in the reports screen or under the lease card on client detail.
class ClientReportsSection extends ConsumerStatefulWidget {
  /// When set, lists this client's reports. When null, the current user/org.
  final String? clientId;

  const ClientReportsSection({super.key, this.clientId});

  @override
  ConsumerState<ClientReportsSection> createState() =>
      _ClientReportsSectionState();
}

class _ClientReportsSectionState extends ConsumerState<ClientReportsSection> {
  static const _limit = 10;
  final List<Map<String, dynamic>> _reports = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;

  /// Job ids already reconciled against a server row, so a completed generation
  /// doesn't keep rendering its in-memory copy alongside the persisted one.
  final Set<String> _absorbed = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (!reset && !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _reports.clear();
        _page = 1;
        _hasMore = true;
      }
    });
    try {
      final auth = ref.read(authStateProvider);
      final orgId = int.tryParse(auth.selectedOrgId ?? '');
      final page = await ref.read(aiReportRepositoryProvider).list(
            userId: widget.clientId ?? auth.user?.id,
            organizationId: orgId,
            page: _page,
            limit: _limit,
          );
      if (!mounted) return;
      setState(() {
        _reports.addAll(page);
        _hasMore = page.length >= _limit;
        _page += 1;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _id(Map<String, dynamic> r) =>
      (r['_id'] ?? r['id'] ?? '').toString();

  String _summaryTitle(Map<String, dynamic> r) {
    final intake = r['intakeData'];
    if (intake is Map && intake['discomfort_areas'] is List) {
      final areas = (intake['discomfort_areas'] as List)
          .whereType<Map>()
          .map((e) => (e['body_area'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();
      if (areas.isNotEmpty) return areas.join(', ');
    }
    final ps = r['personal_snapshot'];
    if (ps is Map && (ps['primary_concern']?.toString().isNotEmpty ?? false)) {
      return ps['primary_concern'].toString();
    }
    return 'AI Report';
  }

  String _summarySub(Map<String, dynamic> r) {
    final parts = <String>[];
    final intake = r['intakeData'];
    if (intake is Map && intake['movement_findings'] is List) {
      final roms = (intake['movement_findings'] as List)
          .whereType<Map>()
          .map((e) => (e['discomfort_area'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();
      if (roms.isNotEmpty) parts.add('ROM: ${roms.join(', ')}');
    }
    final created = (r['createdAt'] ?? r['created_at'])?.toString();
    if (created != null && created.length >= 10) {
      parts.add(created.substring(0, 10));
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final jobs = ref.watch(aiReportGenerationProvider);

    // A finished job whose report is already on the server page is redundant —
    // record it once and let the persisted row stand in from then on.
    final serverIds = _reports.map(_id).where((e) => e.isNotEmpty).toSet();
    for (final j in jobs) {
      if (j.phase == AiReportPhase.done && j.report != null) {
        final rid = _id(j.report!);
        if (rid.isNotEmpty && serverIds.contains(rid)) _absorbed.add(j.id);
      }
    }
    final pending =
        jobs.where((j) => !_absorbed.contains(j.id) && j.phase != AiReportPhase.done)
            .toList();
    final finished = jobs
        .where((j) =>
            !_absorbed.contains(j.id) &&
            j.phase == AiReportPhase.done &&
            j.report != null)
        .toList();

    if (_error != null && _reports.isEmpty && jobs.isEmpty) {
      return const _ComingSoonState();
    }
    if (_reports.isEmpty && jobs.isEmpty && _loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_reports.isEmpty && jobs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
        child: Center(
          child: Text(
            // The spec's empty state, verbatim.
            'No reports yet — run a guided assessment to generate one.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: HwType.cap, height: 1.5, color: p.ink3),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // In-flight and failed jobs sit on top, as the spec unshifts them.
        for (final j in pending) _jobRow(p, j),
        for (final j in finished)
          _row(p, j.report!, title: j.label, status: HwStatus.ready),
        for (final r in _reports) _row(p, r),
        if (_hasMore) ...[
          const SizedBox(height: HwSpace.s2),
          Center(
            child: _loading
                ? const CircularProgressIndicator()
                : HwPress(
                    onTap: _load,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Load more',
                        style: TextStyle(
                          fontSize: HwType.sm,
                          fontWeight: FontWeight.w700,
                          color: p.copperInk,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ],
    );
  }

  /// A generating or failed job. Neither is openable — the spec only makes a
  /// row tappable once its status is `ready`.
  Widget _jobRow(RefPalette p, AiReportJob job) {
    final failed = job.phase == AiReportPhase.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: HwSpace.s2),
      child: HwCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _avatar(p, job.label),
                const SizedBox(width: HwSpace.s3),
                Expanded(
                  child: Text(
                    job.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: p.ink,
                    ),
                  ),
                ),
                const SizedBox(width: HwSpace.s2),
                HwStatusBanner(
                    failed ? HwStatus.failed : HwStatus.generating),
              ],
            ),
            if (failed) ...[
              const SizedBox(height: 8),
              Text(
                // The repository already produces the spec's exact wording for
                // the timeout case.
                job.message ?? 'AI analysis failed. Please try again.',
                style: TextStyle(
                    fontSize: HwType.eyebrow, height: 1.45, color: p.low),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: HwPress(
                  onTap: () => ref
                      .read(aiReportGenerationProvider.notifier)
                      .dismiss(job.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Dismiss',
                      style: TextStyle(
                        fontSize: HwType.cap,
                        fontWeight: FontWeight.w700,
                        color: p.copperInk,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(
    RefPalette p,
    Map<String, dynamic> r, {
    String? title,
    HwStatus status = HwStatus.ready,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: HwSpace.s2),
      child: HwCard(
        padding: const EdgeInsets.all(14),
        onTap: () => context.pushNamed(RouteNames.aiReport, extra: r),
        child: Row(
          children: [
            _avatar(p, title ?? _summaryTitle(r)),
            const SizedBox(width: HwSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title ?? _summaryTitle(r),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: p.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _summarySub(r),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: HwType.eyebrow, color: p.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: HwSpace.s2),
            HwStatusBanner(status),
          ],
        ),
      ),
    );
  }

  /// The spec's `.pava` initials tile.
  Widget _avatar(RefPalette p, String source) {
    final letter = source.trim().isEmpty ? '?' : source.trim()[0].toUpperCase();
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.tanSoft,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: HwType.base,
          fontWeight: FontWeight.w800,
          color: p.copperInk,
        ),
      ),
    );
  }
}

class _ComingSoonState extends StatelessWidget {
  const _ComingSoonState();

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HwComingSoonBanner(),
            const SizedBox(height: 6),
            Text(
              'AI reports are coming soon.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: HwType.base,
                fontWeight: FontWeight.w800,
                color: p.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'You’ll see reports here once the feature is enabled.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
            ),
          ],
        ),
      ),
    );
  }
}
