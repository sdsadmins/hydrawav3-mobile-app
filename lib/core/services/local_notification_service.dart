import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final localNotificationServiceProvider = Provider<LocalNotificationService>(
  (ref) => LocalNotificationService.instance,
);

/// One-shot system/phone notifications (distinct from the ongoing Android
/// foreground-service session notification in `background_session_runtime`).
/// Used for the "device out of range, about to hold the next protocol in the
/// stack" alert so the user gets a chime even if the app isn't in front of
/// them.
class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance =
      LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _bleChannelId = 'ble_out_of_range';
  static const _bleChannelName = 'Device out of range';
  static const _bleChannelDescription =
      'Alerts when a Hydrawave device goes out of Bluetooth range while a '
      'stacked protocol run is waiting to switch to the next protocol.';
  static const _outOfRangeNotificationId = 481001;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings:
          const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _bleChannelId,
        _bleChannelName,
        description: _bleChannelDescription,
        importance: Importance.high,
        playSound: true,
      ));
      await android?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  /// Fires exactly once per disconnect episode — call only at the moment a
  /// stacked-protocol device is confirmed out of range and about to hold the
  /// switch to its next protocol, not on every BLE blip.
  Future<void> notifyDeviceOutOfRangeBeforeNextProtocol({
    String deviceLabel = 'Your Hydrawave device',
  }) =>
      _showOutOfRange(
        '$deviceLabel is out of Bluetooth range, so the next protocol in '
        'the stack is on hold. Bring it back in range to continue.',
      );

  /// The general "your device disconnected mid-session" alert — shown for any
  /// device, not just a Protocol Plus one waiting on its next stack switch.
  /// A real system notification (not the in-app dialog `session_screen.dart`
  /// shows on the same grace-timer edge): that dialog is a `Navigator` push
  /// and only renders while the screen is actually on-screen, so it never
  /// appeared while the app was backgrounded. This does, as long as the
  /// engine's own tick loop (a Riverpod provider, not tied to the screen's
  /// widget lifecycle) is still alive — which the foreground service keeps
  /// true even with the screen off.
  Future<void> notifyDeviceOutOfRange({
    String deviceLabel = 'Your Hydrawave device',
  }) =>
      _showOutOfRange(
        '$deviceLabel lost its Bluetooth connection. Move it closer to '
        'your phone, and it will reconnect automatically and your session '
        'keeps running.',
      );

  Future<void> _showOutOfRange(String body) async {
    if (!_initialized || kIsWeb) return;
    // Plain AndroidNotificationDetails collapses the body to ~2 lines with no
    // way to see the rest — BigTextStyleInformation is what makes the system
    // notification expandable (swipe/tap open) to show the full text, then
    // collapse back.
    final androidDetails = AndroidNotificationDetails(
      _bleChannelId,
      _bleChannelName,
      channelDescription: _bleChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: 'Device out of range',
      ),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    // Shared id: only one out-of-range notification is ever showing at a
    // time, whichever device/case triggered it most recently.
    await _plugin.show(
      id: _outOfRangeNotificationId,
      title: 'Device out of range',
      body: body,
      notificationDetails:
          NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }
}
