import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../data/history_repository.dart';
import '../../domain/session_history_model.dart';

class SessionDetailScreen extends ConsumerWidget {
  final String sessionId;
  final SessionHistoryItem? item;

  const SessionDetailScreen({
    super.key,
    required this.sessionId,
    this.item,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item != null) {
      return _DetailScaffold(session: item!);
    }

    final sessionsAsync = ref.watch(allSessionsProvider);
    return sessionsAsync.when(
      loading: () => const _DetailSkeletonScaffold(),
      error: (error, _) => _StatusScaffold(
        child: Text(
          'Couldn\'t load session.\n$error',
          textAlign: TextAlign.center,
          style: TextStyle(color: ThemeConstants.textSecondary),
        ),
      ),
      data: (sessions) {
        final found = _findById(sessions, sessionId);
        if (found == null) {
          return _StatusScaffold(
            child: Text(
              'Session not found.',
              style: TextStyle(color: ThemeConstants.textSecondary),
            ),
          );
        }
        return _DetailScaffold(session: found);
      },
    );
  }

  SessionHistoryItem? _findById(
      List<SessionHistoryItem> sessions, String id) {
    for (final session in sessions) {
      if (session.id == id) return session;
    }
    return null;
  }
}

class _StatusScaffold extends StatelessWidget {
  final Widget child;
  const _StatusScaffold({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: _detailAppBar(context),
      body: Center(child: Padding(padding: const EdgeInsets.all(24), child: child)),
    );
  }
}

class _DetailSkeletonScaffold extends StatelessWidget {
  const _DetailSkeletonScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: _detailAppBar(context),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ShimmerBox(width: 150, height: 18, borderRadius: 6),
          SizedBox(height: 12),
          _SkeletonCard(rows: 4),
          SizedBox(height: 18),
          ShimmerBox(width: 110, height: 16, borderRadius: 6),
          SizedBox(height: 12),
          _SkeletonCard(rows: 2),
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final int rows;
  const _SkeletonCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeConstants.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows; i++)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ShimmerBox(width: 80, height: 13, borderRadius: 6),
                  ShimmerBox(width: 120, height: 13, borderRadius: 6),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  final SessionHistoryItem session;
  const _DetailScaffold({required this.session});

  @override
  Widget build(BuildContext context) {
    final protocolName = session.protocols.isNotEmpty
        ? (session.protocols.first.protocol ?? 'Session')
        : 'Session';
    final deviceNames = session.protocols
        .map((p) => p.deviceName)
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    final durationLabel = _formatDuration(_durationSeconds(session));
    final dateLabel = session.createdAt != null
        ? _formatDate(session.createdAt!)
        : 'Unknown';

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: _detailAppBar(context),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('Session Summary'),
          const SizedBox(height: 10),
          _Card(children: [
            _Row('Date', dateLabel),
            _Row('Duration', durationLabel),
            _Row('Protocol', protocolName),
            _Row(
              'Device(s)',
              deviceNames.isEmpty ? '—' : deviceNames.join(', '),
            ),
          ]),
          if (session.protocols.length > 1) ...[
            const SizedBox(height: 18),
            const _SectionTitle('Protocols'),
            const SizedBox(height: 10),
            _Card(
              children: [
                for (final protocol in session.protocols)
                  _Row(
                    protocol.deviceName?.isNotEmpty == true
                        ? protocol.deviceName!
                        : (protocol.bodyPart ?? 'Device'),
                    protocol.protocol ?? '—',
                  ),
              ],
            ),
          ],
          if (session.sessionNotes != null &&
              session.sessionNotes!.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            const _SectionTitle('Notes'),
            const SizedBox(height: 10),
            _Card(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Text(
                  session.sessionNotes!.trim(),
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: ThemeConstants.textPrimary,
                  ),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

PreferredSizeWidget _detailAppBar(BuildContext context) {
  return AppBar(
    backgroundColor: ThemeConstants.background,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    iconTheme: IconThemeData(color: ThemeConstants.textPrimary),
    title: Text(
      'Session Details',
      style: TextStyle(
        color: ThemeConstants.textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 18,
      ),
    ),
  );
}

int _durationSeconds(SessionHistoryItem session) {
  var maxSeconds = 0;
  for (final protocol in session.protocols) {
    final value = protocol.duration ?? 0;
    if (value > maxSeconds) maxSeconds = value;
  }
  return maxSeconds;
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year}  $hour:$minute';
}

String _formatDuration(int seconds) {
  final safeSeconds = seconds < 0 ? 0 : seconds;
  final hours = safeSeconds ~/ 3600;
  final minutes = (safeSeconds % 3600) ~/ 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m';
  return '${safeSeconds}s';
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: ThemeConstants.textPrimary,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeConstants.border),
      ),
      child: Column(
        children: children
            .asMap()
            .entries
            .map((e) => Column(children: [
                  e.value,
                  if (e.key < children.length - 1)
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: ThemeConstants.border,
                    ),
                ]))
            .toList(),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14, color: ThemeConstants.textSecondary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ThemeConstants.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

