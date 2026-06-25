import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/ai_report_repository.dart';
import 'ai_report_screen.dart';

/// Paginated history of generated AI reports (parity with the web Client‑Details
/// table): each row summarizes discomfort areas + ROM with View + Download.
class AiReportsListScreen extends ConsumerStatefulWidget {
  /// When set, lists this client's reports (web parity: `ai-reports/all`
  /// queried by the client id). When null, falls back to the current user/org.
  final String? clientId;
  final String? title;

  const AiReportsListScreen({super.key, this.clientId, this.title});

  @override
  ConsumerState<AiReportsListScreen> createState() =>
      _AiReportsListScreenState();
}

class _AiReportsListScreenState extends ConsumerState<AiReportsListScreen> {
  static const _limit = 10;
  final List<Map<String, dynamic>> _reports = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;
  String? _downloadingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
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
      setState(() {
        _reports.addAll(page);
        _hasMore = page.length >= _limit;
        _page += 1;
      });
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _id(Map<String, dynamic> r) =>
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
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(
        backgroundColor: ThemeConstants.surface,
        foregroundColor: ThemeConstants.textPrimary,
        title: Text(widget.title ?? 'AI Reports'),
      ),
      body: _error != null && _reports.isEmpty
          ? _ErrorState(error: _error!, onRetry: _load)
          : (_reports.isEmpty && _loading)
              ? const Center(child: CircularProgressIndicator())
              : _reports.isEmpty
                  ? Center(
                      child: Text('No reports yet',
                          style:
                              TextStyle(color: ThemeConstants.textSecondary)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      itemCount: _reports.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        if (i >= _reports.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: _loading
                                  ? const CircularProgressIndicator()
                                  : OutlinedButton(
                                      onPressed: _load,
                                      child: const Text('Load more'),
                                    ),
                            ),
                          );
                        }
                        return _row(_reports[i]);
                      },
                    ),
    );
  }

  Widget _row(Map<String, dynamic> r) {
    final id = _id(r);
    final downloading = _downloadingId == id && id.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeConstants.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_summaryTitle(r),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: ThemeConstants.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(_summarySub(r),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: ThemeConstants.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'View',
            onPressed: () =>
                context.pushNamed(RouteNames.aiReport, extra: r),
            icon: Icon(Icons.visibility_outlined,
                size: 20, color: ThemeConstants.accent),
          ),
          IconButton(
            tooltip: 'Download',
            onPressed: downloading
                ? null
                : () async {
                    setState(() => _downloadingId = id);
                    await downloadAiReport(context, r);
                    if (mounted) setState(() => _downloadingId = null);
                  },
            icon: downloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.download_rounded,
                    size: 20, color: ThemeConstants.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Failed to load reports',
              style: TextStyle(
                  color: ThemeConstants.textPrimary,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text('$error',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: ThemeConstants.textSecondary, fontSize: 12)),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
