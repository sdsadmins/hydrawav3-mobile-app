import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrawav3/features/notifications/data/notification_remote_source.dart';
import 'package:hydrawav3/features/notifications/domain/app_notification.dart';
import 'package:hydrawav3/features/notifications/presentation/providers/notification_provider.dart';
import 'package:hydrawav3/features/notifications/presentation/screens/notifications_screen.dart';

class _FakeSource extends NotificationRemoteSource {
  final read = <String>[];
  _FakeSource() : super(Dio());
  @override
  Future<void> markRead(String id) async => read.add(id);
}

final _now = DateTime.now();
final _items = [
  AppNotification(
      id: 'n1',
      title: 'AI Report Generated with Malik Carter',
      message: 'Your AI report has been generated successfully',
      createdAt: _now.subtract(const Duration(hours: 2))),
  AppNotification(
      id: 'n2',
      title: 'AI Report Generated with Guest',
      message: 'Your AI report has been generated successfully',
      createdAt: _now.subtract(const Duration(days: 1))),
  AppNotification(
      id: 'n3',
      title: 'AI Report Generated with Sofia Reyes',
      message: 'Your AI report has been generated successfully',
      read: true,
      createdAt: _now.subtract(const Duration(days: 3))),
];

/// Notifications (v6 `renderNotifs`): back bar with the unread count, every
/// notification in one card (read ones dimmed), opening marks them read.
void main() {
  testWidgets('lists every notification and marks them read', (tester) async {
    final fonts = Platform.environment['ROBOTO_DIR'];
    if (fonts != null) {
      final l = FontLoader('Roboto');
      for (final f in ['regular', 'medium', 'bold', 'black']) {
        l.addFont(Future.value(ByteData.view(
            File('$fonts/roboto-$f.ttf').readAsBytesSync().buffer)));
      }
      await l.load();
    }
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final source = _FakeSource();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        notificationsProvider.overrideWith((ref) async => _items),
        notificationRemoteSourceProvider.overrideWithValue(source),
      ],
      child: MaterialApp(
        builder: (c, child) => RepaintBoundary(child: child),
        home: const NotificationsScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('2 unread'), findsOneWidget);
    expect(find.text('AI report ready'), findsNWidgets(3));
    expect(find.text('Malik Carter · report generated'), findsOneWidget);
    expect(find.text('Sofia Reyes · report generated'),
        findsOneWidget); // read, dimmed
    // opening marks the unread ones read
    expect(source.read, ['n1', 'n2']);

    final dir = Platform.environment['SHOTS'];
    if (dir != null) {
      final ro = tester.renderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary).first);
      await tester.runAsync(() async {
        final img = await ro.toImage(pixelRatio: 1);
        final d = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$dir/app_notifs.png').writeAsBytesSync(d!.buffer.asUint8List());
      });
    }
    expect(tester.takeException(), isNull);
  });
}
