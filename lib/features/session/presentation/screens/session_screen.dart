import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/constants/theme_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/logger.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../advanced_settings/domain/advanced_settings_model.dart';
import '../../../protocols/domain/protocol_model.dart';
import '../../../protocols/presentation/providers/protocol_provider.dart';
import '../../services/session_engine.dart';
import '../../domain/session_model.dart';
import '../../../ble/data/ble_repository.dart';
import '../../../devices/presentation/providers/wifi_devices_provider.dart';

class SessionScreen extends ConsumerStatefulWidget {
  final String protocolId;
  final Protocol? protocol;
  final List<String> deviceIds;
  final Map<String, String> protocolByDeviceId;
  final bool skipEngineBootstrap;

  /// 'ble' or 'wifi'
  final String transport;

  /// Epoch ms when WiFi MQTT config last succeeded — aligns app timer with device.
  final int? sessionClockAnchorMs;

  final AdvancedSettings advancedSettings;
  final Map<String, AdvancedSettings> advancedSettingsByDevice;
  final String? delayedDeviceId;
  final bool wifiConfigAlreadyPublished;

  const SessionScreen({
    super.key,
    required this.protocolId,
    this.protocol,
    required this.deviceIds,
    this.protocolByDeviceId = const {},
    this.transport = 'ble',
    this.sessionClockAnchorMs,
    this.advancedSettings = const AdvancedSettings(),
    this.advancedSettingsByDevice = const {},
    this.delayedDeviceId,
    this.skipEngineBootstrap = false,
    this.wifiConfigAlreadyPublished = false,
  });

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  bool _bootstrapStarted = false;
  int _activeDevicePage = 0;
  ProviderSubscription<SessionEngineState>? _engineSub;
  bool _startingSession = false;

  /// Backend pad labels from Node `GET sessions/active/:org` (Hydrawav3-Server).
  String? _backendMoon;
  String? _backendSun;
  Timer? _padPollTimer;

  final Map<String, String> _deviceLabelById = {};

  String _deviceLabel(String id) {
    final key = _normalizeMac(id);
    return _deviceLabelById[key] ?? id;
  }

  @override
  void initState() {
    super.initState();

    _engineSub = ref.listenManual<SessionEngineState>(
      sessionEngineProvider,
      (prev, next) {
        if (!mounted) return;
        final prevS = prev?.status;
        final nextS = next.status;
        final nowActive = nextS == SessionStatus.running ||
            nextS == SessionStatus.paused;
        final wasActive = prevS == SessionStatus.running ||
            prevS == SessionStatus.paused;
        if (nowActive && !wasActive) {
          _startBackendPadPolling();
        } else if (!nowActive && wasActive) {
          // Avoid setState while route is being popped/unmounted.
          _stopBackendPadPolling(fromDispose: true);
        }
      },
    );

    Future<void> bootstrap() async {
      if (!mounted) return;
      if (_bootstrapStarted) return;
      _bootstrapStarted = true;
      if (widget.skipEngineBootstrap) return;

      final ctrl = ref.read(sessionEngineProvider.notifier);

      try {
        if (!mounted) return;
        ctrl.prepareSession(
          deviceIds: widget.deviceIds,
          transport: widget.transport == 'wifi'
              ? SessionTransport.wifi
              : SessionTransport.ble,
        );

        final Protocol commonProtocol = widget.protocol ??
            await ref.read(
              protocolDetailProvider(widget.protocolId).future,
            );

        if (!mounted) return;

        // Resolve the selected protocol per device (no fallback: every device must have one).
        if (widget.protocolByDeviceId.isEmpty) {
          throw StateError('Missing protocolByDeviceId: per-device protocol is required.');
        }

        final Map<String, Protocol> protocolByDevice = {};
        await Future.wait(widget.deviceIds.map((id) async {
          final pid = widget.protocolByDeviceId[id];
          if (pid == null) {
            throw StateError('No protocol selected for device: $id');
          }
          final proto = pid == commonProtocol.id
              ? commonProtocol
              : await ref.read(protocolDetailProvider(pid).future);
          protocolByDevice[id] = proto;
        }));

        if (protocolByDevice.length != widget.deviceIds.length) {
          throw StateError('protocolByDevice resolution incomplete.');
        }

        ctrl.loadSession(
          commonProtocol,
          widget.deviceIds,
          transport: widget.transport == 'wifi'
              ? SessionTransport.wifi
              : SessionTransport.ble,
          advancedSettings: widget.advancedSettings,
          advancedSettingsByDevice: widget.advancedSettingsByDevice,
          delayedDeviceId: widget.delayedDeviceId,
          protocolByDevice: protocolByDevice,
          wifiConfigAlreadyPublished: widget.wifiConfigAlreadyPublished,
        );

        if (!mounted) return;
        if (widget.transport == 'wifi') {
          final ms = widget.sessionClockAnchorMs;
          if (widget.wifiConfigAlreadyPublished && ms != null) {
            ctrl.applySessionClockOffsetFromWallAnchor(
              DateTime.fromMillisecondsSinceEpoch(ms),
            );
          }
          await ctrl.start();
        }
      } catch (e) {
        appLogger.e('SessionScreen error: $e');
      }
    }

    // Must run after the first frame: Riverpod [ref] and [mounted] are not safe
    // from a microtask scheduled at initState time; WiFi start() was never
    // reached, so the session stayed idle (no timer / no pause controls).
    WidgetsBinding.instance.addPostFrameCallback((_) => bootstrap());

    // Load device names once so the session UI can show user-friendly labels.
    unawaited(_loadDeviceNames());
  }

  Future<void> _loadDeviceNames() async {
    try {
      final transport = widget.transport;
      final map = <String, String>{};

      if (transport == 'ble') {
        final paired = await ref.read(bleRepositoryProvider).getPairedDevices();
        for (final p in paired) {
          map[_normalizeMac(p.macAddress)] = p.name;
        }
      } else if (transport == 'wifi') {
        final wifiDevices = await ref.read(wifiDevicesByOrgProvider.future);
        for (final d in wifiDevices) {
          map[_normalizeMac(d.macAddress)] = d.name;
        }
      }

      if (!mounted) return;
      setState(() {
        _deviceLabelById
          ..clear()
          ..addAll(map);
      });
    } catch (_) {
      // If loading fails, we keep showing ids (fallback).
    }
  }

  @override
  void dispose() {
    _stopBackendPadPolling(fromDispose: true);
    _engineSub?.close();
    // ⚠️ DO NOT use ref in dispose() - widget is already unmounted
    // Session engine cleanup happens automatically
    super.dispose();
  }

  String? _resolveOrganizationId() {
    final auth = ref.read(authStateProvider);
    final id = auth.selectedOrgId ?? auth.user?.organizationId;
    if (id == null || id.isEmpty) return null;
    return id;
  }

  static String _normalizeMac(String raw) {
    return raw.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
  }

  void _startBackendPadPolling() {
    if (_padPollTimer != null) return;
    final orgId = _resolveOrganizationId();
    if (orgId == null || widget.deviceIds.isEmpty) return;
    final targetMac = _normalizeMac(widget.deviceIds.first);
    if (targetMac.isEmpty) return;

    Future<void> tick() async {
      if (!mounted) return;
      try {
        final dio = ref.read(nodeDioProvider);
        final resp = await dio.get<Map<String, dynamic>>(
          ApiEndpoints.sessionsActive(orgId),
        );
        final data = resp.data;
        if (data == null || !mounted) return;
        final sessions = data['sessions'] as List<dynamic>?;
        if (sessions == null) return;

        String? moon;
        String? sun;
        sessionLoop:
        for (final raw in sessions) {
          if (raw is! Map<String, dynamic>) continue;
          final devices = raw['devices'] as List<dynamic>?;
          if (devices == null) continue;
          for (final dev in devices) {
            if (dev is! Map<String, dynamic>) continue;
            final mac = _normalizeMac('${dev['macAddress'] ?? ''}');
            if (mac.isEmpty || mac != targetMac) continue;
            final m = dev['moon'];
            final s = dev['sun'];
            if (m != null) moon = m.toString();
            if (s != null) sun = s.toString();
            break sessionLoop;
          }
        }

        if (!mounted) return;
        // Keep this update passive to avoid defunct setState races during
        // route transitions; pads are a visual hint only.
        _backendMoon = moon;
        _backendSun = sun;
      } catch (e, st) {
        appLogger.d('Session pad poll: $e\n$st');
      }
    }

    unawaited(tick());
    _padPollTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void _stopBackendPadPolling({bool fromDispose = false}) {
    _padPollTimer?.cancel();
    _padPollTimer = null;
    _backendMoon = null;
    _backendSun = null;
  }

  @override
  Widget build(BuildContext context) {
    final engine = ref.watch(
        sessionEngineProvider); // ✅ FIX: WATCH instead of READ so UI rebuilds on state changes
    final protocolAsync = widget.protocol != null
        ? AsyncValue.data(widget.protocol!)
        : ref.watch(protocolDetailProvider(widget.protocolId));

    final timer = engine.timer;
    final status = engine.status;
    final ctrl = ref.read(sessionEngineProvider.notifier);
    final protocol = engine.protocol;
    // During timed pause gaps the engine sets currentCycleIndex to -1, but
    // the pads still reflect the active protocol cycle — use lastVisualCycleIndex.
    final int padCycleIdx;
    if (protocol != null && protocol.cycles.isNotEmpty) {
      if (timer.currentCycleIndex >= 0 &&
          timer.currentCycleIndex < protocol.cycles.length) {
        padCycleIdx = timer.currentCycleIndex;
      } else if (timer.lastVisualCycleIndex >= 0 &&
          timer.lastVisualCycleIndex < protocol.cycles.length) {
        padCycleIdx = timer.lastVisualCycleIndex;
      } else {
        padCycleIdx = 0;
      }
    } else {
      padCycleIdx = -1;
    }
    final padCycle = padCycleIdx >= 0 && protocol != null
        ? protocol.cycles[padCycleIdx]
        : null;
    // Web parity: Hydrawav3-ai/.../liveSession.tsx DeviceTimer (moon/sun).
    Color moonColor = Colors.grey;
    Color sunColor = Colors.grey;
    final pc = padCycle;
    if (pc != null &&
        (status == SessionStatus.running || status == SessionStatus.paused)) {
      final moonFn = _useBackendPad(_backendMoon) ? _backendMoon! : pc.leftFunction;
      final sunFn = _useBackendPad(_backendSun) ? _backendSun! : pc.rightFunction;
      moonColor = _webMoonPadColor(moonFn);
      sunColor = _webSunPadColor(sunFn);
    }
    final orderedDeviceIds = widget.deviceIds
        .where((id) => engine.deviceTimers.containsKey(id))
        .toList();
    if (orderedDeviceIds.isEmpty && engine.deviceTimers.isNotEmpty) {
      orderedDeviceIds.addAll(engine.deviceTimers.keys);
    }
    if (_activeDevicePage >= orderedDeviceIds.length &&
        orderedDeviceIds.isNotEmpty) {
      _activeDevicePage = 0;
    }

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(
        title: Text('Session(${widget.deviceIds.length} Devices)'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () async {
            if (status == SessionStatus.running ||
                status == SessionStatus.paused) {
              await ctrl.stop();
            }
            ctrl.reset();
            if (!mounted) return;
            context.pop();
          },
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
              const SizedBox(height: 8),
              if (status == SessionStatus.idle) ...[
                _buildControls(status, ctrl),
                const SizedBox(height: 24),
              ] else if (orderedDeviceIds.isNotEmpty) ...[
                SizedBox(
                  height: 420,
                  child: PageView.builder(
                    itemCount: orderedDeviceIds.length,
                    onPageChanged: (idx) =>
                        setState(() => _activeDevicePage = idx),
                    itemBuilder: (context, index) {
                      final id = orderedDeviceIds[index];
                      final deviceTimer = engine.deviceTimers[id]!;
                      final deviceStatus = engine.deviceStatuses[id]!;
                      final perDeviceProtocolName =
                          engine.protocolByDevice[id]?.templateName ??
                              protocol?.templateName ??
                              '';
                      return _buildDeviceSessionCard(
                        id: id,
                        label: _deviceLabel(id),
                        protocolName: perDeviceProtocolName,
                        timer: deviceTimer,
                        status: deviceStatus,
                        totalCycles: timer.totalCycles,
                        padCycleIdx: padCycleIdx,
                        moonColor: moonColor,
                        sunColor: sunColor,
                        ctrl: ctrl,
                      );
                    },
                  ),
                ),
                if (orderedDeviceIds.length > 1) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(orderedDeviceIds.length, (idx) {
                      final active = idx == _activeDevicePage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 16 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active
                              ? ThemeConstants.accent
                              : ThemeConstants.textTertiary
                                  .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      );
                    }),
                  ),
                ],
                const SizedBox(height: 18),
                const SizedBox(height: 24),
              ] else ...[
                const SizedBox(height: 24),
              ],

              // Device status
              if (widget.deviceIds.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: ThemeConstants.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ThemeConstants.border)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: ThemeConstants.success,
                              shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(
                        widget.transport == 'wifi'
                            ? '${widget.deviceIds.length} WiFi device(s) selected'
                            : '${widget.deviceIds.length} device(s) connected',
                        style: const TextStyle(
                          color: ThemeConstants.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
            ],
        ),
      ),
    );
  }

  Widget _buildDeviceSessionCard({
    required String id,
    required String label,
    required String protocolName,
    required TimerState timer,
    required SessionStatus status,
    required int totalCycles,
    required int padCycleIdx,
    required Color moonColor,
    required Color sunColor,
    required SessionEngine ctrl,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeConstants.border),
      ),
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          if (protocolName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              protocolName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ThemeConstants.textSecondary,
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            decoration: status == SessionStatus.running
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: ThemeConstants.accent.withValues(alpha: 0.10),
                        blurRadius: 26,
                        spreadRadius: 2,
                      ),
                    ],
                  )
                : null,
            child: SizedBox(
              width: 200,
              height: 200,
              child: CustomPaint(
                painter:
                    _TimerRing(progress: timer.progress, active: status == SessionStatus.running),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timer.remaining.formatted,
                        style: const TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.dark_mode_rounded, size: 20, color: moonColor),
                          const SizedBox(width: 12),
                          Icon(Icons.wb_sunny_rounded, size: 22, color: sunColor),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _statusColor(status).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _statusLabel(status),
              style: TextStyle(
                color: _statusColor(status),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          if (totalCycles > 0 && padCycleIdx >= 0) ...[
            const SizedBox(height: 8),
            Text(
              'Cycle ${padCycleIdx + 1}/$totalCycles',
              style: const TextStyle(
                color: ThemeConstants.textTertiary,
                fontSize: 12,
              ),
            ),
          ],
          const Spacer(),
          _buildPerDeviceControls(id, status, ctrl),
        ],
      ),
    );
  }

  Widget _buildPerDeviceControls(
    String deviceId,
    SessionStatus status,
    SessionEngine ctrl,
  ) {
    if (status == SessionStatus.running) {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: () => ctrl.pauseDevice(deviceId),
                child: const Text('Pause'),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: () => ctrl.stopDevice(deviceId),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeConstants.error,
                ),
                child: const Text('Stop'),
              ),
            ),
          ),
        ],
      );
    }
    if (status == SessionStatus.paused) {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: () => ctrl.resumeDevice(deviceId),
                child: const Text('Resume'),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: () => ctrl.stopDevice(deviceId),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeConstants.error,
                ),
                child: const Text('Stop'),
              ),
            ),
          ),
        ],
      );
    }
    return SizedBox(
      height: 44,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: null,
        child: Text(_statusLabel(status)),
      ),
    );
  }

  Widget _buildControls(SessionStatus status, SessionEngine ctrl) {
    return switch (status) {
      SessionStatus.idle => SizedBox(
          height: 52,
          width: double.infinity,
          child: ElevatedButton(
            // WiFi sessions auto-start once protocol loads; don't allow manual start.
            onPressed: widget.transport == 'wifi' || _startingSession
                ? null
                : () async {
                    setState(() => _startingSession = true);
                    try {
                      await ctrl.start();
                    } finally {
                      if (mounted) {
                        setState(() => _startingSession = false);
                      }
                    }
                  },
            child: _startingSession
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.transport == 'wifi' ? 'Starting…' : 'Start Session'),
          ),
        ),
      SessionStatus.running => const SizedBox.shrink(),
      SessionStatus.paused => const SizedBox.shrink(),
      SessionStatus.stopped || SessionStatus.completed => SizedBox(
          height: 52,
          width: double.infinity,
          child: ElevatedButton(
              onPressed: () {
                ctrl.reset();
                context.pop();
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeConstants.success),
              child: const Text('Done'))),
    };
  }

  Color _statusColor(SessionStatus s) => switch (s) {
        SessionStatus.idle => ThemeConstants.textTertiary,
        SessionStatus.running => ThemeConstants.success,
        SessionStatus.paused => ThemeConstants.warning,
        SessionStatus.stopped => ThemeConstants.error,
        SessionStatus.completed => ThemeConstants.success,
      };

  String _statusLabel(SessionStatus s) => switch (s) {
        SessionStatus.idle => 'Ready',
        SessionStatus.running => 'Running',
        SessionStatus.paused => 'Paused',
        SessionStatus.stopped => 'Stopped',
        SessionStatus.completed => 'Completed',
      };

  static bool _strEqIc(String a, String b) =>
      a.toLowerCase().trim() == b.toLowerCase().trim();

  /// Prefer Node session device `moon` / `sun` when present (see Hydrawav3-Server session.service).
  static bool _useBackendPad(String? v) {
    if (v == null) return false;
    final s = v.trim();
    return s.isNotEmpty && s != 'null';
  }

  /// Same rules as web `DeviceTimer` Moon icon (left pad).
  Color _webMoonPadColor(String? moon) {
    if (moon == null || moon.isEmpty) return Colors.grey;
    final m = moon.trim();
    if (_strEqIc(m, 'leftHotRed') || _strEqIc(m, 'hot')) return Colors.red;
    if (_strEqIc(m, 'leftColdBlue') || _strEqIc(m, 'cold')) {
      return Colors.blue;
    }
    return Colors.grey;
  }

  /// Same rules as web `DeviceTimer` Sun icon (right pad).
  Color _webSunPadColor(String? sun) {
    if (sun == null || sun.isEmpty) return Colors.grey;
    final s = sun.trim();
    if (_strEqIc(s, 'rightHotRed') || _strEqIc(s, 'hot')) return Colors.red;
    if (_strEqIc(s, 'rightColdBlue') || _strEqIc(s, 'cold')) {
      return Colors.blue;
    }
    return Colors.grey;
  }
}

class _TimerRing extends CustomPainter {
  final double progress;
  final bool active;
  _TimerRing({required this.progress, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    final bg = Paint()
      ..color = ThemeConstants.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, bg);
    final fg = Paint()
      ..color = ThemeConstants.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -pi / 2,
        2 * pi * progress, false, fg);
  }

  @override
  bool shouldRepaint(covariant _TimerRing old) => progress != old.progress;
}
