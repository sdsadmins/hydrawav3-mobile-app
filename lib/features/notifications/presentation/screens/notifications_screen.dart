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
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _markAllRead(list));
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
              HwBackBar(
                title: 'Notifications',
                subtitle: unread > 0 ? '$unread unread' : 'all caught up',
                onBack: () => _back(context),
              ),
              const SizedBox(height: HwSpace.s2),
              async.when(
                loading: () => HwCard(
                  child: Text(
                    'Loading…',
                    style:
                        TextStyle(fontSize: HwType.cap, color: p.ink3),
                  ),
                ),
                error: (_, __) => HwCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Couldn't load notifications.",
                          style: TextStyle(
                              fontSize: HwType.cap, color: p.ink2),
                        ),
                      ),
                      HwPress(
                        onTap: () =>
                            ref.invalidate(notificationsProvider),
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
                              fontSize: HwType.sm,
                              height: 1.45,
                              color: p.ink2),
                        ),
                      )
                    : HwRowGroup(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        children: [
                          for (final n in items) _NotifRow(n),
                        ],
                      ),
              ),
              const SizedBox(height: HwSpace.s1),
              Text(
                'Quiet by design: only session, lease, report, and fleet '
                'events.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: HwType.cap, height: 1.4, color: p.ink3),
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

class _NotifRow extends StatelessWidget {
  final AppNotification notification;
  const _NotifRow(this.notification);

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Opacity(
      opacity: notification.read ? .6 : 1,
      child: HwRow(
        leading: HwIcon(_icon, size: 19, color: p.copperInk),
        title: notification.title,
        subtitle: notification.message.isEmpty ? null : notification.message,
        trailing: Text(
          _relative(notification.createdAt),
          style: TextStyle(fontSize: HwType.cap, color: p.ink3),
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
