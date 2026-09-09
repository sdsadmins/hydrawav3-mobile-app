import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/widgets/hw_info_dialog.dart';
import '../domain/plus_reconnect_registry.dart';

/// Shows a global "bring your device back in range" reminder — immediately,
/// then every 30s — for as long as any Protocol Plus device is frozen
/// waiting to reconnect (on break AND BLE-disconnected — see
/// `SessionEngine.protocolPlusAwaitingReconnectByDevice`, which is what
/// populates [plusAwaitingReconnectDeviceIdsProvider]). Uses the app's root
/// navigator so it's visible no matter which screen (session screen, device
/// list screen, anywhere) is currently active. Never stops the session —
/// only a reconnect or an explicit user Stop does that.
class PlusReconnectWatchdog extends ConsumerStatefulWidget {
  const PlusReconnectWatchdog({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PlusReconnectWatchdog> createState() =>
      _PlusReconnectWatchdogState();
}

class _PlusReconnectWatchdogState
    extends ConsumerState<PlusReconnectWatchdog> {
  static const _repeatInterval = Duration(seconds: 30);

  Timer? _timer;
  bool _dialogShowing = false;
  Set<String> _awaitingIds = const {};

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onAwaitingChanged(Set<String> ids) {
    _awaitingIds = ids;
    if (ids.isEmpty) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null) return; // Already nagging — let it keep repeating.
    unawaited(_showReminder());
    _timer = Timer.periodic(_repeatInterval, (_) {
      unawaited(_showReminder());
    });
  }

  Future<void> _showReminder() async {
    if (_awaitingIds.isEmpty || _dialogShowing) return;
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;

    final count = _awaitingIds.length;
    _dialogShowing = true;
    try {
      await showHwInfoDialog(
        navContext,
        icon: Icons.bluetooth_disabled_rounded,
        title: count == 1
            ? 'Please bring your device back in range'
            : 'Please bring your devices back in range',
        message: count == 1
            ? 'That device lost its Bluetooth connection. Its session is '
                'paused and will resume automatically once it reconnects. '
                'Move it closer to your phone. You can stop the session at '
                'any time.'
            : '$count devices lost their Bluetooth connection. Their '
                'sessions are paused and will resume automatically once they '
                'reconnect. You can stop the session at any time.',
        actionLabel: 'OK',
      );
    } finally {
      _dialogShowing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<Set<String>>(
      plusAwaitingReconnectDeviceIdsProvider,
      (_, next) => _onAwaitingChanged(next),
    );
    return widget.child;
  }
}
