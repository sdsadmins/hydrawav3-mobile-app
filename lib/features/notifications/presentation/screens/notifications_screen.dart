import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_icon.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../domain/app_notification.dart';
import '../providers/notification_provider.dart';

/// Notifications — ported from the UI spec's `renderNotifs()` (app.js:3273).
///
/// Read entries dim to 60%; rows are informational, not tappable. Everything
/// on screen comes from `GET notifications/:userId`.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _markedRead = false;

  /// The spec marks everything read as a side effect of rendering, so the
  /// count reads "N unread" on arrival and "all caught up" next time.
  void _markAllRead(List<AppNotification> list) {
    if (_markedRead) return;
    _markedRead = true;
    for (final n in list.where((n) => !n.read)) {
      markNotificationRead(ref, n.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final async = ref.watch(notificationsProvider);
    final list = async.valueOrNull ?? const <AppNotification>[];
    final unread = list.where((n) => !n.read).length;

    if (list.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _markAllRead(list));
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 108),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                subtitle: unread > 0 ? '$unread unread' : 'all caught up',
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
                          "Couldn't load notifications.",
                          style: TextStyle(fontSize: HwType.cap, color: p.ink2),
                        ),
                      ),
                      HwPress(
                        onTap: () => ref.invalidate(notificationsProvider),
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
                          'Nothing yet. Session, lease and report events '
                          'will land here.',
                          style: TextStyle(
                              fontSize: HwType.sm, height: 1.45, color: p.ink2),
                        ),
                      )
                    // `.card` (padding 6/16): white, soft shadow, no border
                    : Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: p.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: p.line2),
                          boxShadow: p.shadow,
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < items.length; i++) ...[
                              if (i > 0)
                                Divider(
                                    height: 1, thickness: 1, color: p.line2),
                              _NotifRow(items[i]),
                            ],
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: HwSpace.s3),
              Text(
                'Quiet by design — only session, lease, report, and fleet '
                'events.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: HwType.cap, height: 1.4, color: p.ink3),
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

/// `.backbar`: a round white back button, then "Notifications" (24/800) and
/// the unread line.
class _Header extends StatelessWidget {
  final String subtitle;
  final VoidCallback onBack;
  const _Header({required this.subtitle, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 10),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Back',
            child: Container(
              decoration:
                  BoxDecoration(shape: BoxShape.circle, boxShadow: p.shadow),
              child: Material(
                color: p.card,
                shape: CircleBorder(side: BorderSide(color: p.line)),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onBack,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.chevron_left_rounded,
                        size: 24, color: p.ink2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notifications',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.48,
                        height: 1.15,
                        color: p.ink)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: p.ink3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `.row`: glyph, title (14/600) + one-line detail (12), time on the right.
class _NotifRow extends StatelessWidget {
  final AppNotification notification;
  const _NotifRow(this.notification);

  /// "AI Report Generated with Malik Carter" → "AI report ready" /
  /// "Malik Carter · report generated", the prototype's short wording.
  (String, String?) get _text {
    const lead = 'AI Report Generated with ';
    final t = notification.title.trim();
    if (t.startsWith(lead) && t.length > lead.length) {
      return (
        'AI report ready',
        '${t.substring(lead.length).trim()} · report generated'
      );
    }
    final m = notification.message.trim();
    return (t, m.isEmpty ? null : m);
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final (title, detail) = _text;
    return Opacity(
      opacity: notification.read ? .6 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 13),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Align(
                alignment: Alignment.centerLeft,
                child: HwIcon(_icon, size: 19, color: p.copperInk),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          color: p.ink)),
                  if (detail != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, height: 1.3, color: p.ink2)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _relative(notification.createdAt),
              style: TextStyle(fontSize: 12, color: p.ink3),
            ),
          ],
        ),
      ),
    );
  }

  /// Map the event to the spec's per-type glyph (app.js:3262-3266).
  String get _icon {
    final t = '${notification.title} ${notification.message}'.toLowerCase();
    if (t.contains('report')) return HwIcons.doc;
    if (t.contains('lease')) return HwIcons.key;
    if (t.contains('credit') || t.contains('token')) return HwIcons.chart;
    if (t.contains('offline') || t.contains('device')) {
      return HwIcons.offline;
    }
    return HwIcons.check;
  }

  static String _relative(DateTime? at) {
    if (at == null) return '';
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays == 1) return 'Yesterday';
    return '${d.inDays}d ago';
  }
}
