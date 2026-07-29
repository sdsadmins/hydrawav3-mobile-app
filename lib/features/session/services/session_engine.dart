import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/mqtt_publish_client.dart';
import '../../../core/constants/ble_constants.dart';
import '../../../core/utils/logger.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../../ble/services/ble_connector.dart';
import '../../advanced_settings/domain/advanced_settings_model.dart';
import '../../intake/domain/intake_models.dart';
import '../../protocols/domain/protocol_model.dart';
import 'background_session_runtime.dart';
import 'session_sync_service.dart';
import '../data/session_repository.dart';
import '../domain/pending_session_outcome_model.dart';
import '../domain/session_model.dart';
import '../presentation/providers/pending_outcomes_provider.dart';

/// Provider family that creates a separate SessionEngine instance for each session
/// This allows true concurrent sessions without sharing state
final sessionEngineFamilyProvider =
    StateNotifierProvider.family<SessionEngine, SessionEngineState, String>(
        (ref, sessionId) {
  return SessionEngine(ref, sessionId: sessionId);
});

/// Live per-device telemetry received FROM the device during a running session
/// (device→app direction). Mirrors the fields the web app renders on its device
/// card: pad thermode state ([sun]/[moon]), non-blocking warnings ([warnCode]),
/// and blocking faults ([faultReason]/[faultValue]/[telemetryState]). [raw] keeps
/// the full merged frame — exactly like the web's `{...device, ...json}` spread —
/// so richer sensor fields the firmware/backend sends are preserved for display.
///
/// Both transports converge here: BLE devices report over the EVENT/STATUS notify
/// channels; Wi-Fi devices report via the backend (Socket.IO `SESSION_UPDATED`
/// and the active-sessions poll). Field names are normalized so the firmware's
/// short forms (`w`/`fr`/`fv`/`s`) and the backend's long forms
/// (`pad`/`faultReason`/`faultValue`/`telemetryState`) both resolve.
class DeviceTelemetry {
  final String? sun; // right pad (p2): 'hot' | 'cold' | 'disabled'
  final String? moon; // left pad (p1): 'hot' | 'cold' | 'disabled'
  final String? warnCode; // 'pad_disconnect' | 'ntc_overheat'
  final String? faultReason; // 'overcurrent_spike' | 'overcurrent_sustained'
  final num? faultValue;
  final String? telemetryState; // 'fault'
  final Map<String, dynamic> raw;
  final DateTime? updatedAt;

  const DeviceTelemetry({
    this.sun,
    this.moon,
    this.warnCode,
    this.faultReason,
    this.faultValue,
    this.telemetryState,
    this.raw = const {},
    this.updatedAt,
  });

  bool get isPadDisconnect => warnCode == 'pad_disconnect';
  bool get isNtcOverheat => warnCode == 'ntc_overheat';
  bool get isWarning => isPadDisconnect || isNtcOverheat;

  bool get isOvercurrentSpike => faultReason == 'overcurrent_spike';
  bool get isOvercurrentSustained => faultReason == 'overcurrent_sustained';
  bool get isFaultState => telemetryState == 'fault';
  bool get isFault =>
      isOvercurrentSpike || isOvercurrentSustained || isFaultState;

  /// Human label for the fault card (web parity).
  String? get faultLabel => isOvercurrentSpike
      ? 'Overcurrent Spike'
      : isOvercurrentSustained
          ? 'Overcurrent Sustained'
          : isFaultState
              ? 'Device Fault'
              : null;

  /// Structural / already-surfaced keys excluded from the generic sensor row.
  static const Set<String> _structuralKeys = {
    'mac', 'macaddress', 'deviceid', 'device_id', 'id', 'bluetoothid',
    'slotid', 'devicename', 'sun', 'moon', 'pad', 'w', 'faultreason', 'fr',
    'faultvalue', 'fv', 'telemetrystate', 's', 'lastseen', 'playcmd', 'type',
    // Session bookkeeping fields from the backend active-sessions frame — not
    // device sensors, so they must not appear as readout chips.
    'remainingseconds', 'elapsedseconds', 'totaldurationseconds',
    'organizationid', 'bodypart', 'protocol', 'status', 'advancedsettings',
    'sessionid', 'clientid',
    // Compact firmware-frame fields that aren't sensor readings: firmware
    // version (parses numeric), medium, run state, user mode, and the p1/p2 pad
    // objects (surfaced via sun/moon instead).
    'fw', 'm', 'rs', 'lm', 'p1', 'p2', 'pe', 'pw', 'l', 'v',
    // Hidden readout chips (per product): temperature (tp), current (c),
    // voltage (av), and the unidentified td/tl — excluded so they don't render
    // on the device card.
    'tp', 'c', 'av', 'td', 'tl',
  };

  /// Numeric "extra" readings (temperature/voltage/current/cycle progress/…)
  /// the firmware/backend includes beyond what the web card renders. Generic by
  /// design — exact field names vary by firmware, so any numeric, non-structural
  /// key is surfaced rather than hard-coded.
  Map<String, num> get sensorReadouts {
    final out = <String, num>{};
    raw.forEach((key, value) {
      if (_structuralKeys.contains(key.toLowerCase())) return;
      if (value is num) {
        out[key] = value;
      } else if (value is String) {
        final n = num.tryParse(value);
        if (n != null) out[key] = n;
      }
    });
    return out;
  }

  /// Merge a freshly-received frame onto this telemetry, web-style ({...d, ...json}),
  /// then re-derive the normalized fields from the accumulated map.
  DeviceTelemetry mergeJson(Map<String, dynamic> json) {
    final merged = Map<String, dynamic>.from(raw)..addAll(json);

    dynamic pick(List<String> keys) {
      for (final k in keys) {
        final v = merged[k];
        if (v != null) return v;
      }
      return null;
    }

    String? str(List<String> keys) {
      final v = pick(keys);
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    num? number(List<String> keys) {
      final v = pick(keys);
      if (v is num) return v;
      if (v is String) return num.tryParse(v);
      return null;
    }

    // The firmware's compact frame carries per-pad state under p1/p2, with the
    // LED color field `l` ("red"/"blue"). Per hardware: p1 is the LEFT pad
    // (moon) and p2 is the RIGHT pad (sun) — so moon ← p1.l, sun ← p2.l. (This
    // intentionally swaps the web's session.tsx mapping, which had sun ← p1.l /
    // moon ← p2.l.) Falls back to the backend's sun/moon
    // ('hot'/'cold'/'disabled') when p1/p2 are absent.
    String? padLed(String key) {
      final p = merged[key];
      if (p is Map && p['l'] is String) {
        final l = (p['l'] as String).trim();
        if (l.isNotEmpty) return l;
      }
      return null;
    }

    return DeviceTelemetry(
      sun: str(['sun']) ?? padLed('p2'),
      moon: str(['moon']) ?? padLed('p1'),
      warnCode: str(['pad', 'w']),
      faultReason: str(['faultReason', 'fr']),
      faultValue: number(['faultValue', 'fv']),
      // Web maps firmware `s` straight to telemetryState; only the literal value
      // "fault" drives the fault UI (a normal frame's `s` is e.g. "cycle3").
      telemetryState: str(['telemetryState', 's']),
      raw: merged,
      updatedAt: DateTime.now(),
    );
  }
}

class SessionEngineState {
  final SessionStatus status;
  final TimerState timer;
  final Protocol? protocol;
  final Map<String, Protocol> protocolByDevice;
  final List<String> deviceIds;
  final SessionTransport transport;
  final bool wifiConfigAlreadyPublished;
  final AdvancedSettings advancedSettings;
  final Map<String, AdvancedSettings> advancedSettingsByDevice;
  final Map<String, TimerState> deviceTimers;
  final Map<String, SessionStatus> deviceStatuses;
  final String? delayedDeviceId;

  /// Protocol Plus template name (the sequence's own title), the ordered
  /// sub-protocol names, and the index of the one currently running. Empty
  /// sequence = not a Protocol Plus session. Drives the sequence tracker in the
  /// live session screen.
  final String protocolPlusName;
  final List<String> protocolPlusSequence;
  final int protocolPlusIndex;

  /// Per-device Protocol Plus tracker state for mixed / multi-Plus sessions.
  /// A device id present in [protocolPlusSequenceByDevice] is a Plus device and
  /// gets its own progress card; absent ids are normal protocols.
  final Map<String, String> protocolPlusNameByDevice;
  final Map<String, List<String>> protocolPlusSequenceByDevice;
  final Map<String, int> protocolPlusIndexByDevice;

  /// Per-device ordered sub-protocol durations (seconds), aligned index-for-index
  /// with [protocolPlusSequenceByDevice]. Lets the live tracker show each
  /// protocol's time under its name.
  final Map<String, List<int>> protocolPlusDurationsByDevice;

  /// Per-device delay (seconds) inserted between stacked protocols on a
  /// Protocol Plus run (the `delay` field on the protocol-plus document).
  /// Shown in the live session tracker for Plus devices.
  final Map<String, int> protocolPlusDelayByDevice;

  /// True while a Plus device is in the BREAK between two stacked protocols —
  /// its current protocol has finished on the firmware and the next protocol's
  /// START_PROTOCOL switch hasn't landed yet. Drives the live break banner.
  final Map<String, bool> protocolPlusOnBreakByDevice;

  /// Seconds remaining in the current break for a Plus device (0 once the break
  /// elapses and we're just waiting for the server switch to land). Only
  /// meaningful while [protocolPlusOnBreakByDevice] is true for that device.
  final Map<String, int> protocolPlusBreakRemainingByDevice;

  /// Live device→app telemetry per device (faults, warnings, pad state, sensors).
  /// Empty until the first frame arrives over BLE notify or the backend channel.
  final Map<String, DeviceTelemetry> telemetryByDevice;

  /// Admin-defined post-session questions for every protocol used in this
  /// session (protocol name -> its questions), including each Protocol Plus
  /// sub-protocol. Set once at launch; drives the post-session outcomes sheet.
  final Map<String, List<ProtocolQuestion>> questionsByProtocolName;

  final String? error;

  const SessionEngineState({
    this.status = SessionStatus.idle,
    this.timer = const TimerState(),
    this.protocol,
    this.protocolByDevice = const {},
    this.deviceIds = const [],
    this.transport = SessionTransport.ble,
    this.wifiConfigAlreadyPublished = false,
    this.advancedSettings = const AdvancedSettings(),
    this.advancedSettingsByDevice = const {},
    this.deviceTimers = const {},
    this.deviceStatuses = const {},
    this.delayedDeviceId,
    this.protocolPlusName = '',
    this.protocolPlusSequence = const [],
    this.protocolPlusIndex = 0,
    this.protocolPlusNameByDevice = const {},
    this.protocolPlusSequenceByDevice = const {},
    this.protocolPlusIndexByDevice = const {},
    this.protocolPlusDurationsByDevice = const {},
    this.protocolPlusDelayByDevice = const {},
    this.protocolPlusOnBreakByDevice = const {},
    this.protocolPlusBreakRemainingByDevice = const {},
    this.telemetryByDevice = const {},
    this.questionsByProtocolName = const {},
    this.error,
  });

  SessionEngineState copyWith({
    SessionStatus? status,
    TimerState? timer,
    Protocol? protocol,
    Map<String, Protocol>? protocolByDevice,
    List<String>? deviceIds,
    SessionTransport? transport,
    bool? wifiConfigAlreadyPublished,
    AdvancedSettings? advancedSettings,
    Map<String, AdvancedSettings>? advancedSettingsByDevice,
    Map<String, TimerState>? deviceTimers,
    Map<String, SessionStatus>? deviceStatuses,
    String? delayedDeviceId,
    String? protocolPlusName,
    List<String>? protocolPlusSequence,
    int? protocolPlusIndex,
    Map<String, String>? protocolPlusNameByDevice,
    Map<String, List<String>>? protocolPlusSequenceByDevice,
    Map<String, int>? protocolPlusIndexByDevice,
    Map<String, List<int>>? protocolPlusDurationsByDevice,
    Map<String, int>? protocolPlusDelayByDevice,
    Map<String, bool>? protocolPlusOnBreakByDevice,
    Map<String, int>? protocolPlusBreakRemainingByDevice,
    Map<String, DeviceTelemetry>? telemetryByDevice,
    Map<String, List<ProtocolQuestion>>? questionsByProtocolName,
    String? error,
  }) {
    return SessionEngineState(
      status: status ?? this.status,
      timer: timer ?? this.timer,
      protocol: protocol ?? this.protocol,
      protocolByDevice: protocolByDevice ?? this.protocolByDevice,
      deviceIds: deviceIds ?? this.deviceIds,
      transport: transport ?? this.transport,
      wifiConfigAlreadyPublished:
          wifiConfigAlreadyPublished ?? this.wifiConfigAlreadyPublished,
      advancedSettings: advancedSettings ?? this.advancedSettings,
      advancedSettingsByDevice:
          advancedSettingsByDevice ?? this.advancedSettingsByDevice,
      deviceTimers: deviceTimers ?? this.deviceTimers,
      deviceStatuses: deviceStatuses ?? this.deviceStatuses,
      delayedDeviceId: delayedDeviceId ?? this.delayedDeviceId,
      protocolPlusName: protocolPlusName ?? this.protocolPlusName,
      protocolPlusSequence: protocolPlusSequence ?? this.protocolPlusSequence,
      protocolPlusIndex: protocolPlusIndex ?? this.protocolPlusIndex,
      protocolPlusNameByDevice:
          protocolPlusNameByDevice ?? this.protocolPlusNameByDevice,
      protocolPlusSequenceByDevice:
          protocolPlusSequenceByDevice ?? this.protocolPlusSequenceByDevice,
      protocolPlusIndexByDevice:
          protocolPlusIndexByDevice ?? this.protocolPlusIndexByDevice,
      protocolPlusDurationsByDevice:
          protocolPlusDurationsByDevice ?? this.protocolPlusDurationsByDevice,
      protocolPlusDelayByDevice:
          protocolPlusDelayByDevice ?? this.protocolPlusDelayByDevice,
      protocolPlusOnBreakByDevice:
          protocolPlusOnBreakByDevice ?? this.protocolPlusOnBreakByDevice,
      protocolPlusBreakRemainingByDevice: protocolPlusBreakRemainingByDevice ??
          this.protocolPlusBreakRemainingByDevice,
      telemetryByDevice: telemetryByDevice ?? this.telemetryByDevice,
      questionsByProtocolName:
          questionsByProtocolName ?? this.questionsByProtocolName,
      error: error,
    );
  }
}

class SessionEngine extends StateNotifier<SessionEngineState> {
  final Ref _ref;
  final String sessionId;
  Timer? _timer;
  final Stopwatch _stopwatch = Stopwatch();
  Duration _sessionClockOffset = Duration.zero;
  DateTime? _firstBlePlayAnchor;
  bool _startInProgress = false;
  final Map<String, Stopwatch> _deviceStopwatches = {};

  /// Wall-clock anchors for suspend-proof timing. The Dart [Stopwatch] uses a
  /// monotonic clock that does NOT advance while the device is in deep sleep,
  /// and the periodic UI ticker is frozen while the app is backgrounded / the
  /// screen is off. We record a wall-clock anchor whenever the run (re)starts so
  /// [_reconcileClockFromWall] can detect and add back any elapsed wall time the
  /// monotonic clock missed, keeping the displayed timer aligned with the device.
  DateTime? _wallClockAnchor;
  Duration _monotonicAnchor = Duration.zero;

  /// Per-device catch-up added to each device [Stopwatch] to cover sleep time
  /// the monotonic clock didn't count. Keyed by device id.
  final Map<String, Duration> _deviceClockOffset = {};
  int _cycleIndex = 0;
  int _repetition = 0;
  bool _isActive = true; // Guard against state updates after disposal
  bool _historyCaptured = false; // Save session to history only once on start
  bool _pendingOutcomeEnqueued = false; // Queue post-session review once

  /// Client/guest context for this session, set from the setup screen via
  /// [setClientContext]. Threads into the `POST /intake` body (and AI report).
  String? _clientId;
  GuidedAssessmentData? _intake;

  /// Set the client/guest + guided-assessment context for this session. Called
  /// before [start] from the launcher; defaults keep behaviour unchanged
  /// (guest, no intake) when not provided.
  void setClientContext({String? clientId, GuidedAssessmentData? intake}) {
    _clientId = clientId;
    _intake = intake;
  }

  /// Register the admin-defined post-session questions for every protocol used
  /// in this session (protocol name -> questions), set by the launcher before
  /// [start]. Drives the post-session outcomes sheet. Merges so multiple calls
  /// accumulate.
  void setSessionQuestions(Map<String, List<ProtocolQuestion>> byProtocolName) {
    if (byProtocolName.isEmpty) return;
    state = state.copyWith(
      questionsByProtocolName: {
        ...state.questionsByProtocolName,
        ...byProtocolName,
      },
    );
  }

  /// Snapshot the just-completed session into the pending-outcomes queue so the
  /// post-session questions can be asked even after the live card is gone.
  /// Idempotent; only fires for sessions that actually ran (a draft was saved).
  void enqueuePendingOutcome() {
    if (_pendingOutcomeEnqueued) return;
    // Post-session questions are asked for CLIENT sessions only (web parity —
    // guests are never prompted). Guest = no client context.
    if (_clientId == null) return;
    if (!_historyCaptured) return; // never started running
    if (state.protocol == null || state.deviceIds.isEmpty) return;
    _pendingOutcomeEnqueued = true;
    try {
      final snapshot = _buildPendingOutcome();
      unawaited(_ref.read(pendingOutcomesProvider.notifier).enqueue(snapshot));
    } catch (e) {
      _pendingOutcomeEnqueued = false;
      appLogger.e('Session: failed to queue post-session outcome: $e');
    }
  }

  PendingSessionOutcome _buildPendingOutcome() {
    final protocolByDeviceId = <String, ({String name, int durationSeconds})>{};
    final protocolNamesByDeviceId = <String, List<String>>{};
    for (final deviceId in state.deviceIds) {
      final proto = state.protocolByDevice[deviceId];
      final isPlusDevice = _plusDeviceIds().contains(deviceId) ||
          state.protocolPlusNameByDevice.containsKey(deviceId);
      if (isPlusDevice) {
        final plusName = state.protocolPlusNameByDevice[deviceId] ??
            (state.protocolPlusName.isNotEmpty
                ? state.protocolPlusName
                : (proto?.templateName ?? state.protocol!.templateName));
        final devTimer = state.deviceTimers[deviceId];
        // Store how long the device ACTUALLY ran (elapsed at session end), not
        // the planned whole-sequence length — history should reflect real run
        // time even when the session is stopped early.
        final plusDuration = devTimer != null
            ? devTimer.elapsed.inSeconds
            : _effectiveElapsed.inSeconds;
        protocolByDeviceId[deviceId] =
            (name: plusName, durationSeconds: plusDuration);
        // Ordered sub-protocol names drive one question section each.
        final seq = state.protocolPlusSequenceByDevice[deviceId];
        protocolNamesByDeviceId[deviceId] =
            (seq != null && seq.isNotEmpty) ? List<String>.from(seq) : [plusName];
      } else {
        final name = proto?.templateName ?? state.protocol!.templateName;
        final devTimer = state.deviceTimers[deviceId];
        // Actual run time for this device (elapsed at session end), not the
        // configured protocol length.
        final actualElapsed =
            devTimer?.elapsed.inSeconds ?? _effectiveElapsed.inSeconds;
        protocolByDeviceId[deviceId] = (
          name: name,
          durationSeconds: actualElapsed,
        );
        protocolNamesByDeviceId[deviceId] = [name];
      }
    }

    final resolvedClientType = _clientId != null ? 'client' : 'guest';
    return PendingSessionOutcome(
      sessionId: sessionId,
      protocolId: state.protocol!.id,
      protocolName: state.protocol!.templateName,
      deviceIds: List<String>.from(state.deviceIds),
      protocolByDeviceId: protocolByDeviceId,
      protocolNamesByDeviceId: protocolNamesByDeviceId,
      questionsByProtocolName:
          Map<String, List<ProtocolQuestion>>.from(state.questionsByProtocolName),
      clientType: resolvedClientType,
      clientId: _clientId,
      discomfortBefore: null,
      totalDurationSeconds: state.timer.totalDuration.inSeconds,
      elapsedSeconds: _effectiveElapsed.inSeconds,
      createdAt: DateTime.now(),
      intake: _intake,
    );
  }

  /// True for a server-driven Protocol Plus run. While true, the engine must
  /// NOT auto-STOP a device or mark it "completed" when a single protocol's
  /// duration elapses — the firmware finishes that protocol on its own and the
  /// next one arrives via START_PROTOCOL. Sending STOP here would kill the
  /// device mid-sequence (timer keeps running, device goes dark).
  bool _isProtocolPlus = false;

  /// Device ids running a server-driven Protocol Plus sequence. In a mixed
  /// session (some Plus, some normal) only these devices skip the auto-STOP /
  /// "completed" transition when a single protocol's duration elapses.
  final Set<String> _protocolPlusDeviceIds = <String>{};

  /// Device-elapsed at which the CURRENTLY running protocol of a Plus device
  /// finishes on the firmware. Set for protocol[0] when the run starts and
  /// recomputed on every START_PROTOCOL switch. Once the device's elapsed
  /// passes this, the device is in the break window until the next switch
  /// lands — this is what drives the break countdown in the tick loop.
  final Map<String, Duration> _plusSegmentEndByDevice = {};

  /// Wall-clock start of the CURRENT uninterrupted `rs:"stop"` streak per Plus
  /// device. Seeded by the first stop frame, cleared by any play/pause frame, by
  /// a landed switch, and by [reset]. The tick loop turns a long-enough streak
  /// into a device-initiated stop — see [_evaluatePlusDeviceStops].
  final Map<String, DateTime> _plusStopSince = {};

  /// Plus devices whose config+PLAY write is executing RIGHT NOW.
  /// [applyProtocolPlusSwitch] deliberately sends STOP first and waits ~4s
  /// before PLAY, so the device genuinely reports `rs:"stop"` for several
  /// seconds during every healthy switch. Without this flag our own switch would
  /// look exactly like a user stop.
  final Set<String> _plusSwitchInFlight = <String>{};

  /// Plus devices for which [ProtocolPlusController] is HOLDING a switch (the
  /// device was disconnected, or the write failed and it was re-queued). The
  /// controller owns `_pendingSwitches`; the engine has no other way to see that
  /// a switch is outstanding. No time bound — the controller's 4s reconciler is
  /// what clears it.
  final Set<String> _plusSwitchPendingExternal = <String>{};

  /// Fired once a Plus device is confirmed to have been stopped ON THE DEVICE.
  /// [ProtocolPlusController] wires this to stop that device's own server
  /// session (each Plus device has its own `serverSessionId`).
  void Function(String deviceId)? onPlusDeviceStoppedByUser;

  /// How long a Plus device must report `rs:"stop"` uninterrupted, outside the
  /// break window and with no switch pending, before we call it a user stop.
  /// Telemetry streams roughly every 3s, so this is ~2 consecutive frames.
  static const Duration _plusStopConfirmWindow = Duration(seconds: 6);

  /// The same, for a device whose segment end we can't predict — we can't reason
  /// about its break window at all, so wait longer than any plausible
  /// break + switch sequence before acting.
  static const Duration _plusStopConfirmWindowUnknownSegment =
      Duration(seconds: 25);

  /// How far BEFORE the predicted segment end a stop still reads as the break.
  /// [_plusSegmentEndByDevice] is our ESTIMATE of the firmware's runtime and the
  /// device stopwatch can drift across a suspend, so a unit that finishes a few
  /// seconds "early" by our clock must not be mistaken for a user stop.
  static const Duration _plusBreakPreGrace = Duration(seconds: 15);

  /// How far AFTER the nominal break end a stop still reads as the break. A
  /// healthy but late switch costs up to 12s waiting for reconnect
  /// (applyProtocolPlusSwitch) + ~4s for STOP→config→PLAY + a retry ≈ 22s; 30s
  /// leaves headroom for server-side jitter.
  ///
  /// Both graces are deliberately generous: a false positive tears down a live
  /// treatment mid-break, while a false negative only DELAYS detection (the
  /// window always expires and the pending flags always clear).
  static const Duration _plusBreakPostGrace = Duration(seconds: 30);

  Future<void> _stateUpdateQueue = Future.value();

  /// Listens to the BLE notify/status stream and turns telemetry frames into
  /// per-device [DeviceTelemetry] (device→app direction). Wired only for BLE
  /// sessions; Wi-Fi telemetry arrives via the backend channel.
  StreamSubscription<BleNotification>? _telemetrySub;

  static const int _blePauseByte = 0x02;
  static const int _bleResumeByte = 0x04;
  static const int _bleStopByte = 0x03;
  static const String _debugLightProtocolId = 'light-on';

  SessionEngine(this._ref, {required this.sessionId})
      : super(const SessionEngineState());

  /// Public, read-only view of the session transport (the underlying [state] is
  /// protected on StateNotifier). Used by [ProtocolPlusController] to decide
  /// whether a held switch is gated on a BLE link.
  SessionTransport get transport => state.transport;

  Future<void> _enqueueStateUpdate(void Function() fn) {
    _stateUpdateQueue = _stateUpdateQueue.then((_) async {
      if (!_isActive) return;
      fn();
    });
    return _stateUpdateQueue;
  }

  /// Adds [DateTime.now() - anchor] to the running timer so UI matches hardware
  /// when navigation / setup finishes after the device already started.
  void applySessionClockOffsetFromWallAnchor(DateTime anchor) {
    if (!_isActive) return;
    final lag = DateTime.now().difference(anchor);
    _sessionClockOffset = lag.isNegative ? Duration.zero : lag;
    appLogger.i(
      'Session: clock offset $_sessionClockOffset from wall anchor $anchor',
    );
  }

  Duration get _effectiveElapsed => _stopwatch.elapsed + _sessionClockOffset;

  /// Record where the wall clock and the monotonic stopwatch are right now, so
  /// [_reconcileClockFromWall] can measure any divergence later. Called whenever
  /// the run (re)starts ticking.
  void _anchorWallClock() {
    _wallClockAnchor = DateTime.now();
    _monotonicAnchor = _stopwatch.elapsed;
  }

  /// Add back any wall-clock time the monotonic [Stopwatch] missed while the
  /// device was asleep, then re-anchor. Safe to call every tick: while awake
  /// both clocks advance together so the drift is ~0 and this is a no-op. The
  /// drift only grows across a suspend (screen off / app backgrounded), where it
  /// captures exactly the sleep duration and folds it into the session + per-
  /// device offsets so the displayed timer catches up to the running device.
  void _reconcileClockFromWall() {
    if (!_isActive || state.status != SessionStatus.running) return;
    final anchor = _wallClockAnchor;
    if (anchor == null) return;
    final wallElapsed = DateTime.now().difference(anchor);
    final monotonicElapsed = _stopwatch.elapsed - _monotonicAnchor;
    final drift = wallElapsed - monotonicElapsed;
    // Ignore sub-second jitter (and any backwards wall-clock adjustment).
    if (drift <= const Duration(milliseconds: 500)) return;
    _sessionClockOffset += drift;
    for (final id in state.deviceIds) {
      if (state.deviceStatuses[id] == SessionStatus.running) {
        _deviceClockOffset[id] =
            (_deviceClockOffset[id] ?? Duration.zero) + drift;
      }
    }
    _anchorWallClock();
    appLogger.i('Session: reconciled +$drift of missed sleep time after wake');
  }

  /// Call when the app returns to the foreground. The periodic UI ticker is
  /// suspended while the app is backgrounded / the screen is off, and the
  /// monotonic clock skips deep-sleep time — so the displayed timer can be stale
  /// or behind the device. Reconcile against the wall clock and restart the
  /// ticker so the UI jumps straight to the device's true position.
  void onAppResumed() {
    if (!_isActive || state.status != SessionStatus.running) return;
    _reconcileClockFromWall();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 250), _onTick);
    _syncDisplayedTimerFromStopwatch();
  }

  Future<bool> _sendLargePayload(
    String mac,
    String payloadFrame,
  ) async {
    final connector = _ref.read(bleConnectorProvider);

    return await connector.writeJsonToDevice(
      mac,
      utf8.encode(payloadFrame),
    );
  }

  Future<bool> _sendPlayCommand(String mac) async {
    final connector = _ref.read(bleConnectorProvider);
    final ok = await connector.writeToDevice(mac, [0x01]);
    appLogger.i('Session: BLE raw PLAY attempt 1/1 for $mac → $ok');
    return ok;
  }

  Future<void> _publishWifiPlayCmd(int playCmd) async {
    final deviceIds = state.deviceIds;
    if (deviceIds.isEmpty) return;
    try {
      final dio = _ref.read(djangoDioProvider);
      for (final mac in deviceIds) {
        final payloadStr = jsonEncode({'mac': mac, 'playCmd': playCmd});
        appLogger.i(
          'WiFi: Publishing playCmd=$playCmd (topic=HydraWav3Pro/config, mac=$mac, payload=$payloadStr)',
        );
        await postMqttPublishRequest(
          dio,
          data: {
            'topic': 'HydraWav3Pro/config',
            'payload': payloadStr,
          },
        );
      }
    } on DioException catch (e) {
      appLogger.e(
        'WiFi: playCmd publish failed '
        '(cmd=$playCmd, status=${e.response?.statusCode}, data=${e.response?.data}, message=${e.message})',
      );
    } catch (e) {
      appLogger.e('WiFi: playCmd publish failed (cmd=$playCmd): $e');
    }
  }

  Future<void> _publishWifiPlayCmdToMac(String mac, int playCmd) async {
    if (mac.isEmpty) return;
    try {
      final dio = _ref.read(djangoDioProvider);
      final payloadStr = jsonEncode({'mac': mac, 'playCmd': playCmd});
      appLogger.i(
        'WiFi: Publishing playCmd=$playCmd (topic=HydraWav3Pro/config, mac=$mac, payload=$payloadStr)',
      );
      await postMqttPublishRequest(
        dio,
        data: {
          'topic': 'HydraWav3Pro/config',
          'payload': payloadStr,
        },
      );
    } on DioException catch (e) {
      appLogger.e(
        'WiFi: playCmd publish failed (cmd=$playCmd, mac=$mac, status=${e.response?.statusCode}, message=${e.message})',
      );
    } catch (e) {
      appLogger.e(
        'WiFi: playCmd publish failed (cmd=$playCmd, mac=$mac): $e',
      );
    }
  }

  // ───────────────────────── device→app telemetry ─────────────────────────

  /// Subscribe to the BLE notification stream and convert telemetry frames into
  /// per-device [DeviceTelemetry]. Idempotent; only meaningful for BLE sessions
  /// (the handler early-returns for other transports). Wi-Fi telemetry is fed by
  /// the backend channel (socket `SESSION_UPDATED` / active-sessions poll).
  void _ensureBleTelemetrySubscription() {
    if (_telemetrySub != null) return;
    final connector = _ref.read(bleConnectorProvider);
    _telemetrySub = connector.notifications.listen((n) {
      if (!_isActive) return;
      if (state.transport != SessionTransport.ble) return;
      _ingestBleTelemetryFrame(n.deviceId, n.value);
    });
  }

  /// Parse a BLE notify/status payload and, if it carries telemetry, merge it.
  /// Non-telemetry frames (MAC/ACK/sessionId) are ignored here — those are
  /// handled inside the connector. Mirrors the web's EVENT_NOTIFY handler.
  void _ingestBleTelemetryFrame(String deviceId, List<int> value) {
    Map<String, dynamic>? json;
    try {
      final s = utf8.decode(value, allowMalformed: true).trim();
      if (s.isEmpty || !s.startsWith('{')) return;
      final decoded = jsonDecode(s);
      if (decoded is! Map) return;
      json = decoded.cast<String, dynamic>();
    } catch (_) {
      return; // not JSON / not UTF-8
    }
    // Map-key format {"<id>": {...}} — unwrap one level (firmware sometimes
    // namespaces the payload under its device id).
    if (json.length == 1) {
      final only = json.values.first;
      if (only is Map) json = only.cast<String, dynamic>();
    }

    // Reflect a pause/resume/stop pressed ON the device: the firmware reports
    // its run state in `rs` ("play"/"pause"/"stop"). Web parity: session.tsx
    // reconciles this against the session status.
    final rs = json['rs'];
    if (rs is String && rs.trim().isNotEmpty) {
      appLogger
          .i('🔎 rs-frame from $deviceId: rs=$rs (keys=${json.keys.toList()})');
      _reconcileDeviceRunState(deviceId, rs);
    }

    if (!_looksLikeTelemetry(json)) return;
    updateDeviceTelemetry(deviceId, json);
  }

  /// Last `rs` value acted on per device, so a steady stream of identical run
  /// states doesn't re-fire and user-initiated actions aren't double-applied.
  final Map<String, String> _lastRsByDevice = {};

  /// Reconcile a device-reported run state ([rs] = "play"/"pause"/"stop") for the
  /// SINGLE device that sent it — the device→app half of the per-device controls.
  /// In a multi-device session, a stop/pause/resume on one device affects ONLY
  /// that device; the others keep running. BLE only (Wi-Fi lifecycle is handled
  /// by the backend channel).
  ///
  /// Calls the same per-device [pauseDevice]/[resumeDevice]/[stopDevice] the
  /// per-device buttons use. Their status guards + the per-device `rs` dedupe
  /// make this safe against a steady frame stream and against a button the user
  /// just pressed in-app for that device.
  void _reconcileDeviceRunState(String incomingId, String rs) {
    if (!_isActive) return;
    if (state.transport != SessionTransport.ble) {
      appLogger
          .i('🔎 rs-reconcile skip: transport=${state.transport} (not BLE)');
      return; // BLE only
    }

    final deviceId = _resolveTelemetryDeviceId(incomingId);
    if (deviceId == null) {
      appLogger.i(
          '🔎 rs-reconcile skip: $incomingId not matched to session devices=${state.deviceIds}');
      return;
    }

    final normalized = rs.trim().toLowerCase();
    final deviceIsPlus = _isPlusDevice(deviceId);

    // Track the Plus stop STREAK before the dedupe below. A repeated `stop`
    // frame is not a new event, but it must not reset the streak either — and a
    // `play` must break it. This has to run for repeats too, which is why it
    // sits above the dedupe return.
    if (deviceIsPlus) _recordPlusRunState(deviceId, normalized);

    if (_lastRsByDevice[deviceId] == normalized) {
      appLogger.i('🔎 rs-reconcile skip: dedupe (rs=$normalized unchanged)');
      return; // dedupe
    }
    _lastRsByDevice[deviceId] = normalized;
    appLogger.i(
        '🔎 rs-reconcile ACT: $deviceId rs=$normalized (status=${state.deviceStatuses[deviceId]})');

    // Protocol Plus lifecycle is NOT decided here. The firmware PHYSICALLY STOPS
    // between stacked sub-protocols — and our own switch sends STOP first and
    // waits ~4s before PLAY — so a single `rs:stop` frame is ambiguous: it is
    // usually an expected idle, but it is also exactly what the user pressing
    // STOP on the unit looks like. Acting on the frame would tear the sequence
    // down mid-break; ignoring it entirely (what we used to do) left the app
    // counting down forever after a real stop. Instead the tick loop weighs the
    // whole streak against the break window — see [_evaluatePlusDeviceStops].
    if (deviceIsPlus) return;

    final current = state.deviceStatuses[deviceId];
    if (current == null) return;

    switch (normalized) {
      case 'pause':
        if (current == SessionStatus.running) {
          appLogger.i(
              'Session: device $deviceId reported rs=pause → pausing that device');
          unawaited(pauseDevice(deviceId));
          // Web parity: mirror the per-device pause to the backend too.
          unawaited(_mirrorDeviceLifecycleToBackend(deviceId, 'pause'));
        }
        break;
      case 'play':
        if (current == SessionStatus.paused) {
          appLogger.i(
              'Session: device $deviceId reported rs=play → resuming that device');
          unawaited(resumeDevice(deviceId));
          // Web parity: mirror the per-device resume to the backend too.
          unawaited(_mirrorDeviceLifecycleToBackend(deviceId, 'resume'));
        }
        break;
      case 'stop':
        if (current != SessionStatus.stopped &&
            current != SessionStatus.completed) {
          appLogger.i(
              'Session: device $deviceId reported rs=stop → stopping that device');
          // Use the force-stop path (NOT stopDevice): the firmware stops and
          // then drops the BLE link, so by the time this runs the device may
          // already be disconnected — and stopDevice deliberately skips a
          // disconnected device. force-stop registers it regardless and
          // suppresses the auto-reconnect so it doesn't come back.
          _forceDeviceStopped(deviceId);
          // Web parity: also drive the BACKEND stop for just this device
          // (stopAll:false) so the server ends/deducts it and every other
          // client's live feed reconciles — not only our local state.
          unawaited(_mirrorDeviceLifecycleToBackend(deviceId, 'stop'));
        }
        break;
    }
  }

  /// Single source of truth for "is this device running a Plus sequence".
  /// Replaces three divergent inline predicates that had drifted apart.
  bool _isPlusDevice(String id) =>
      _protocolPlusDeviceIds.contains(id) ||
      (_isProtocolPlus && _protocolPlusDeviceIds.isEmpty) ||
      state.protocolPlusSequenceByDevice.containsKey(id);

  /// Maintain [_plusStopSince] — the start of this device's current
  /// uninterrupted `rs:"stop"` streak. Repeat stop frames do NOT restart the
  /// streak; any play/pause frame breaks it.
  void _recordPlusRunState(String id, String normalized) {
    if (normalized == 'stop') {
      _plusStopSince.putIfAbsent(id, DateTime.now);
    } else if (normalized == 'play' || normalized == 'pause') {
      if (_plusStopSince.remove(id) != null) {
        appLogger.i(
            'ProtocolPlus: $id reported $normalized — stop streak cleared');
      }
    }
  }

  /// Drop all Plus stop bookkeeping. Called wherever [_lastRsByDevice] is reset
  /// — a new run must not inherit the last one's half-finished streaks.
  void _clearPlusStopTracking() {
    _plusStopSince.clear();
    _plusSwitchInFlight.clear();
    _plusSwitchPendingExternal.clear();
  }

  /// True when [id]'s elapsed time places it inside the window where an
  /// `rs:"stop"` is the firmware's expected idle between two stacked
  /// sub-protocols rather than a user pressing STOP on the unit.
  bool _isInsidePlusBreakWindow(String id) {
    // Nothing comes after the final sub-protocol, so there is no break to
    // confuse it with — a stop there is either the natural end (the tick loop
    // completes it) or a user stop.
    if (_isPlusDeviceOnFinalProtocol(id)) return false;
    final segEnd = _plusSegmentEndByDevice[id];
    // Segment end unknown → we cannot reason about the break at all; the caller
    // falls back to the much longer unknown-segment confirmation window.
    if (segEnd == null) return false;
    final elapsed = _deviceElapsed(id);
    final delay = Duration(seconds: state.protocolPlusDelayByDevice[id] ?? 0);
    return elapsed >= segEnd - _plusBreakPreGrace &&
        elapsed <= segEnd + delay + _plusBreakPostGrace;
  }

  /// Turn a long-enough `rs:"stop"` streak into a device-initiated stop.
  ///
  /// Called from the tick loop rather than from the frame handler, so the
  /// decision is re-evaluated continuously: a stop that begins during a break
  /// and outlives it (a lost START_PROTOCOL switch) is still caught once the
  /// break window expires, which a one-shot timer armed at the first frame
  /// would miss.
  ///
  /// KNOWN LIMITATION: if the user presses STOP while the device is ALREADY idle
  /// mid-break, the firmware's `rs` never changes and the streak that is running
  /// is the break's own. It is confirmed once the break window expires, which is
  /// the correct outcome, just later than a mid-protocol stop.
  void _evaluatePlusDeviceStops() {
    if (_plusStopSince.isEmpty) return;
    if (!_isActive || state.transport != SessionTransport.ble) return;
    final now = DateTime.now();
    for (final id in _plusStopSince.keys.toList()) {
      final since = _plusStopSince[id];
      if (since == null) continue;
      final status = state.deviceStatuses[id];
      if (status != SessionStatus.running && status != SessionStatus.paused) {
        _plusStopSince.remove(id); // already terminal / not started
        continue;
      }
      // Our own switch sends STOP first and waits ~4s before PLAY, and a held
      // switch leaves the device idle indefinitely — neither is a user stop.
      if (_plusSwitchInFlight.contains(id) ||
          _plusSwitchPendingExternal.contains(id)) {
        continue;
      }
      if (_isInsidePlusBreakWindow(id)) continue;
      final window = _plusSegmentEndByDevice[id] == null
          ? _plusStopConfirmWindowUnknownSegment
          : _plusStopConfirmWindow;
      final streak = now.difference(since);
      if (streak < window) continue;

      appLogger.w(
        'ProtocolPlus: $id reported rs=stop for ${streak.inSeconds}s outside '
        'the break window with no pending switch → treating as a USER STOP ON '
        'THE DEVICE (elapsed=${_deviceElapsed(id)}, '
        'segEnd=${_plusSegmentEndByDevice[id]}, '
        'delay=${state.protocolPlusDelayByDevice[id]})',
      );
      _plusStopSince.remove(id);
      // The same path a normal protocol takes. Once every device is stopped the
      // engine goes terminal, which the controller's engine listener turns into
      // the full teardown (server stop, active-session removal, foreground
      // notification) and the session screen turns into the post-session flow.
      _forceDeviceStopped(id);
      onPlusDeviceStoppedByUser?.call(id);
    }
  }

  /// Mirror a firmware-reported per-device run-state change (`rs:stop` /
  /// `rs:pause` / `rs:play`) to the backend, the way the web does: POST the
  /// matching /sessions/:id/{stop|pause|resume} for JUST this device so the
  /// server updates/deducts only it and broadcasts to every other client's live
  /// feed — not only our local state. No-op when this run has no backend session
  /// (an offline / own-only run), where the local change is already the whole
  /// story. Never throws into the notify stream.
  Future<void> _mirrorDeviceLifecycleToBackend(
    String deviceId,
    String action,
  ) async {
    final backendId = _ref.read(normalServerSessionIdProvider(sessionId));
    if (backendId == null || backendId.isEmpty) return;
    final sync = _ref.read(sessionSyncServiceProvider);
    try {
      switch (action) {
        case 'stop':
          await sync.stopServerSessionDeviceByIdentity(backendId, deviceId);
          break;
        case 'pause':
          await sync.pauseServerSessionDeviceByIdentity(backendId, deviceId);
          break;
        case 'resume':
          await sync.resumeServerSessionDeviceByIdentity(backendId, deviceId);
          break;
      }
      appLogger.i(
          'Session: mirrored rs=$action for $deviceId → backend session $backendId');
    } catch (e) {
      appLogger.e('Session: backend $action mirror failed for $deviceId: $e');
    }
  }

  /// Mark a device stopped because the DEVICE itself stopped (rs=stop) and is
  /// dropping the BLE link. Unlike [stopDevice], this does NOT skip a
  /// disconnected device — the device genuinely stopped, so we must reflect it
  /// even if the link is already gone. Suppresses that device's auto-reconnect
  /// and ends the session when every device is stopped/completed.
  void _forceDeviceStopped(String deviceId) {
    if (!_isActive) return;
    appLogger.i('🔎 _forceDeviceStopped($deviceId) — engineKey=$sessionId '
        'devices=${state.deviceIds} statuses=${state.deviceStatuses}');
    _deviceStopwatches[deviceId]?.stop();
    _suppressDeviceReconnect(deviceId);
    final statuses = Map<String, SessionStatus>.from(state.deviceStatuses)
      ..[deviceId] = SessionStatus.stopped;
    if (statuses.values.every(
      (s) => s == SessionStatus.stopped || s == SessionStatus.completed,
    )) {
      _timer?.cancel();
      _timer = null;
      _stopwatch.stop();
    }
    final overallStatus = _deriveOverallStatus(statuses);
    try {
      state = state.copyWith(deviceStatuses: statuses, status: overallStatus);
    } catch (_) {
      return; // notifier disposed
    }
    appLogger.i('🔎 _forceDeviceStopped done: overall=$overallStatus '
        'newStatuses=$statuses');
    if (overallStatus == SessionStatus.stopped ||
        overallStatus == SessionStatus.completed) {
      unawaited(_syncBackgroundRuntime('stopped'));
    } else {
      _pushNotificationSync();
    }
  }

  /// Stop the BLE connector from auto-reconnecting [deviceId] now that it has
  /// stopped/completed — so a device that drops the link after the session ends
  /// isn't pulled back. BLE only; the next session's connect() re-enables it.
  void _suppressDeviceReconnect(String deviceId) {
    if (state.transport != SessionTransport.ble) return;
    _ref.read(bleConnectorProvider).suppressReconnect(deviceId);
  }

  static const Set<String> _telemetryKeys = {
    'sun',
    'moon',
    'pad',
    'w',
    'faultReason',
    'fr',
    'faultValue',
    'fv',
    'telemetryState',
    's',
  };

  bool _looksLikeTelemetry(Map<String, dynamic> json) =>
      json.keys.any(_telemetryKeys.contains);

  /// Merge a telemetry frame for [incomingId] (BLE remoteId, or a MAC from the
  /// backend) onto that device's [DeviceTelemetry]. Drops frames that don't map
  /// to a device in this session.
  void updateDeviceTelemetry(String incomingId, Map<String, dynamic> json) {
    if (!_isActive) return;
    final deviceId = _resolveTelemetryDeviceId(incomingId);
    if (deviceId == null) return;
    final existing = state.telemetryByDevice[deviceId];
    final merged = (existing ?? const DeviceTelemetry()).mergeJson(json);
    final map = Map<String, DeviceTelemetry>.from(state.telemetryByDevice)
      ..[deviceId] = merged;
    try {
      state = state.copyWith(telemetryByDevice: map);
    } catch (_) {
      // notifier disposed — ignore.
    }
  }

  static String _hexOnly(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');

  /// Resolve an inbound telemetry id to one of this session's device ids. BLE
  /// notifications arrive keyed by remoteId (a direct match); backend frames
  /// arrive keyed by MAC, matched against device ids and the firmware-reported
  /// hardware MAC.
  String? _resolveTelemetryDeviceId(String incoming) {
    if (incoming.isEmpty) return null;
    final ids = state.deviceIds;
    if (ids.contains(incoming)) return incoming;
    final wantHex = _hexOnly(incoming);
    if (wantHex.isEmpty) return null;
    final connector = _ref.read(bleConnectorProvider);
    for (final id in ids) {
      if (_hexOnly(id) == wantHex) return id;
      final hw = connector.getHardwareMac(id);
      if (hw != null && _hexOnly(hw) == wantHex) return id;
    }
    return null;
  }

  /// Apply a remote session lifecycle change (another client / the backend
  /// paused, resumed, or stopped this session) WITHOUT re-issuing device
  /// commands — UI-only reconciliation, mirroring the web's socket handlers.
  void applyRemoteLifecycle(SessionStatus remoteStatus) {
    if (!_isActive) return;
    if (state.status == remoteStatus) return;
    switch (remoteStatus) {
      case SessionStatus.paused:
        if (state.status != SessionStatus.running) return;
        for (final id in state.deviceIds) {
          _deviceStopwatches[id]?.stop();
        }
        final statuses = Map<String, SessionStatus>.from(state.deviceStatuses);
        for (final id in state.deviceIds) {
          if (statuses[id] == SessionStatus.running) {
            statuses[id] = SessionStatus.paused;
          }
        }
        state = state.copyWith(
          deviceStatuses: statuses,
          status: _deriveOverallStatus(statuses),
        );
        break;
      case SessionStatus.running:
        if (state.status != SessionStatus.paused) return;
        for (final id in state.deviceIds) {
          if (state.deviceStatuses[id] == SessionStatus.paused) {
            _deviceStopwatches[id]?.start();
          }
        }
        final statuses = Map<String, SessionStatus>.from(state.deviceStatuses);
        for (final id in state.deviceIds) {
          if (statuses[id] == SessionStatus.paused) {
            statuses[id] = SessionStatus.running;
          }
        }
        state = state.copyWith(
          deviceStatuses: statuses,
          status: _deriveOverallStatus(statuses),
        );
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(milliseconds: 250), _onTick);
        _anchorWallClock();
        _syncDisplayedTimerFromStopwatch();
        break;
      default:
        break;
    }
  }

  /// Set transport/devices before protocol loads.
  /// This prevents accidental BLE-start attempts while protocol is still loading.
  void prepareSession({
    required List<String> deviceIds,
    required SessionTransport transport,
  }) {
    if (!_isActive) return;
    final selectedDeviceIds = List<String>.from(deviceIds);
    state = state.copyWith(
      deviceIds: selectedDeviceIds,
      transport: transport,
    );
    appLogger.i(
      'Session: prepareSession(transport=$transport, deviceIds=$selectedDeviceIds)',
    );
  }

  void loadSession(
    Protocol protocol,
    List<String> deviceIds, {
    SessionTransport transport = SessionTransport.ble,
    AdvancedSettings advancedSettings = const AdvancedSettings(),
    Map<String, AdvancedSettings>? advancedSettingsByDevice,
    Map<String, Protocol>? protocolByDevice,
    bool wifiConfigAlreadyPublished = false,
    String? delayedDeviceId,
  }) {
    if (!_isActive) return; // Guard against updates after disposal

    appLogger.i('═══════════════════════════════════════════════════');
    appLogger.i('Session: loadSession()');
    appLogger.i('  Protocol: ${protocol.templateName} (id=${protocol.id})');
    appLogger.i('  Transport: $transport');
    appLogger.i('  Devices: $deviceIds');
    appLogger.i('  Cycles: ${protocol.cycles.length}');
    final settingsByDevice = <String, AdvancedSettings>{
      for (final id in deviceIds)
        id: advancedSettingsByDevice?[id] ?? advancedSettings,
    };

    if (protocolByDevice == null) {
      state = state.copyWith(
        status: SessionStatus.stopped,
        error: 'No protocol selected per device (protocolByDevice missing).',
      );
      return;
    }

    final resolvedProtocolByDevice = <String, Protocol>{};
    for (final id in deviceIds) {
      final proto = protocolByDevice[id];
      if (proto == null) {
        state = state.copyWith(
          status: SessionStatus.stopped,
          error: 'No protocol selected for device: $id',
        );
        return;
      }
      resolvedProtocolByDevice[id] = proto;
    }
    final selectedDeviceIds = List<String>.from(deviceIds);
    final computedTotalDurationSeconds = selectedDeviceIds.isEmpty
        ? _computeEffectiveTotalDurationSeconds(
            protocol,
            advancedSettings,
            applyStartDelay: false,
          )
        : selectedDeviceIds.map((id) {
            final deviceProtocol = resolvedProtocolByDevice[id]!;
            final deviceSettings = settingsByDevice[id] ?? advancedSettings;
            return _computeEffectiveTotalDurationSeconds(
              deviceProtocol,
              deviceSettings,
              applyStartDelay: _shouldApplyStartDelay(
                transportId: id,
                advancedSettings: deviceSettings,
              ),
            );
          }).reduce((a, b) => a > b ? a : b);
    appLogger
        .i('  Total Duration: ${computedTotalDurationSeconds}s (computed)');
    appLogger.i(
      '  Advanced: cycle1=${advancedSettings.cycle1Initiation}, '
      'cycle5=${advancedSettings.cycle5Completion}, '
      'led=${advancedSettings.lights}, '
      'vibrationMode=${advancedSettings.vibrationMode}, '
      'vibMin=${advancedSettings.vibMin}, vibMax=${advancedSettings.vibMax}, '
      'sweepMin=${advancedSettings.vibrationSweepMin}, '
      'sweepMax=${advancedSettings.vibrationSweepMax}, '
      'singleHz=${advancedSettings.vibrationSingleHz}, '
      'flip=${advancedSettings.flipSettings}',
    );
    appLogger.i('═══════════════════════════════════════════════════');

    final deviceTimers = <String, TimerState>{
      for (final id in selectedDeviceIds)
        id: TimerState(
          totalDuration: Duration(
            seconds: _computeEffectiveTotalDurationSeconds(
              resolvedProtocolByDevice[id]!,
              settingsByDevice[id] ?? advancedSettings,
              applyStartDelay: _shouldApplyStartDelay(
                transportId: id,
                advancedSettings: settingsByDevice[id] ?? advancedSettings,
              ),
            ),
          ),
          totalCycles: resolvedProtocolByDevice[id]!.cycles.length,
          lastVisualCycleIndex:
              resolvedProtocolByDevice[id]!.cycles.isNotEmpty ? 0 : -1,
        ),
    };
    final deviceStatuses = <String, SessionStatus>{
      for (final id in selectedDeviceIds) id: SessionStatus.idle,
    };

    try {
      state = SessionEngineState(
        status: SessionStatus.idle,
        protocol: protocol,
        protocolByDevice: resolvedProtocolByDevice,
        deviceIds: selectedDeviceIds,
        transport: transport,
        wifiConfigAlreadyPublished: wifiConfigAlreadyPublished,
        advancedSettings: advancedSettings,
        advancedSettingsByDevice: settingsByDevice,
        deviceTimers: deviceTimers,
        deviceStatuses: deviceStatuses,
        delayedDeviceId: delayedDeviceId,
        timer: TimerState(
          totalDuration: Duration(seconds: computedTotalDurationSeconds),
          totalCycles: protocol.cycles.length,
          lastVisualCycleIndex: protocol.cycles.isNotEmpty ? 0 : -1,
        ),
        // Preserve post-session questions across the fresh state so calling
        // setSessionQuestions before OR after loadSession both work.
        questionsByProtocolName: state.questionsByProtocolName,
      );
    } catch (e) {
      appLogger
          .d('Session: loadSession state update ignored (notifier disposed)');
    }
    _cycleIndex = -1;
    _repetition = 0;
    _sessionClockOffset = Duration.zero;
    _firstBlePlayAnchor = null;
    _wallClockAnchor = null;
    _monotonicAnchor = Duration.zero;
    _deviceClockOffset.clear();
    _plusSegmentEndByDevice.clear();
    _startInProgress = false;
    _deviceStopwatches
      ..clear()
      ..addEntries(selectedDeviceIds.map((e) => MapEntry(e, Stopwatch())));

    _lastRsByDevice.clear();
    _clearPlusStopTracking();

    // Begin listening for device→app telemetry over BLE. Subscribed
    // unconditionally so no session-entry path can skip it; the listener itself
    // no-ops for non-BLE transports (Wi-Fi telemetry comes from the backend).
    _ensureBleTelemetrySubscription();
  }

  Future<void> start() async {
    if (_startInProgress) {
      appLogger.w('⚠️ Ignoring start() — start sequence already in progress');
      return;
    }
    if (state.status != SessionStatus.idle) {
      appLogger.e("⛔ BLOCKED start() — status: ${state.status}");
      return;
    }
    if (!_isActive) return; // Guard against updates after disposal
    if (state.status == SessionStatus.running ||
        state.status == SessionStatus.paused) {
      appLogger.w("⚠️ Ignoring start() — session already active");
      return;
    }

    appLogger.i(
      'Session: start() transport=${state.transport} deviceIds=${state.deviceIds}',
    );
    _startInProgress = true;

    try {
      if (state.protocol == null) {
        appLogger.w('Session: start() ignored — protocol not loaded yet');
        return;
      }

      // WiFi sessions: command is already sent via MQTT/API from the protocol
      // screen. We just run the timer UI.
      if (state.transport == SessionTransport.wifi) {
        if (!state.wifiConfigAlreadyPublished) {
          // Publish full RS35 session config per device, then start the timer UI.
          // This matches the web flow when starting directly from the session setup screen.
          try {
            final dio = _ref.read(djangoDioProvider);
            for (final mac in state.deviceIds) {
              final deviceProtocol = state.protocolByDevice[mac];
              if (deviceProtocol == null) {
                throw StateError('Missing protocol for device=$mac');
              }

              final payloadObj = _protocolToRs232Json(
                deviceProtocol,
                transportId: mac,
              );
              final payloadStr = jsonEncode(payloadObj);

              await postMqttPublishRequest(
                dio,
                data: {
                  'topic': 'HydraWav3Pro/config',
                  'payload': payloadStr,
                },
              );
            }
          } on DioException catch (e) {
            appLogger.e(
              'WiFi: config publish failed '
              '(status=${e.response?.statusCode}, data=${e.response?.data}, message=${e.message})',
            );
            if (!_isActive) return;
            state = state.copyWith(
              status: SessionStatus.stopped,
              error: 'WiFi publish failed: ${e.message ?? e.toString()}',
            );
            return;
          } catch (e) {
            appLogger.e('WiFi: config publish failed: $e');
            if (!_isActive) return;
            state = state.copyWith(
              status: SessionStatus.stopped,
              error: 'WiFi publish failed: $e',
            );
            return;
          } finally {
            // If we published config ourselves, align UI to "now".
            _sessionClockOffset = Duration.zero;
          }
        }

        appLogger.i(
          'Session: Starting WiFi session timer (devices=${state.deviceIds.length})',
        );
        final statuses = Map<String, SessionStatus>.from(state.deviceStatuses);
        for (final id in state.deviceIds) {
          statuses[id] = SessionStatus.running;
          _deviceStopwatches[id]?.start();
        }
        state = state.copyWith(
          deviceStatuses: statuses,
          status: _deriveOverallStatus(statuses),
        );
        _beginRuntimeTimer();
        return;
      }

      final connector = _ref.read(bleConnectorProvider);
      final targetDeviceIds = state.deviceIds.isNotEmpty
          ? state.deviceIds
          : connector.connectedDeviceIds;

      if (targetDeviceIds.isEmpty) {
        if (!_isActive) return;
        state = state.copyWith(
          error: 'No BLE device selected/connected',
        );
        appLogger.w('Session: Start aborted — no target BLE devices');
        return;
      }

      // CRITICAL FIX: Verify all devices are actually connected before attempting payload send.
      // This fixes the issue where selected devices may have disconnected between device
      // selection and session start.
      final actuallyConnectedIds =
          targetDeviceIds.where((id) => connector.isConnected(id)).toList();

      if (actuallyConnectedIds.isEmpty) {
        if (!_isActive) return;

        state = state.copyWith(
          error: 'No BLE devices connected...',
        );
        return;
      }

      // Log warning if some selected devices disconnected
      final disconnectedIds =
          targetDeviceIds.where((id) => !connector.isConnected(id)).toList();
      if (disconnectedIds.isNotEmpty) {
        appLogger.w(
          'Session: Some selected devices disconnected, proceeding with connected devices only '
          '(disconnected=${disconnectedIds.join(", ")}, connected=${actuallyConnectedIds.join(", ")})',
        );
      }

      if (BleConstants.startSendsOnlyPlayCmd) {
        // This mode is only meant to "turn on" by sending a tiny command.
        // Cancel any previously running timer so we don't tick while
        // `state.protocol` is null (this was causing the crash you pasted).
        _timer?.cancel();
        _timer = null;
        _stopwatch.stop();
        _stopwatch.reset();

        final failed = <String>[];
        final playCmdJson = jsonEncode({'playCmd': 1});
        // Some firmwares only accept specific newline framing. We try a small
        // ordered set to find the exact terminator the device expects.
        final terminatorFrames = <String>[
          '$playCmdJson${BleConstants.sessionJsonLineSuffix}', // current suffix (likely '\n')
          '$playCmdJson\r\n',
          '$playCmdJson\n\n',
        ];

        appLogger.i(
          'Session: Sending playCmd-only (frame variants=$terminatorFrames) '
          'to ${actuallyConnectedIds.length} connected device(s)',
        );

        for (final mac in actuallyConnectedIds) {
          bool anyOk = false;
          for (final frame in terminatorFrames) {
            appLogger.i(
              "Session: playCmd-only sending to $mac frame='${frame.replaceAll('\n', '\\\\n').replaceAll('\r', '\\\\r')}' "
              '(${frame.length} bytes, utf8)',
            );
            final ok = await connector.writeToDevice(mac, utf8.encode(frame));
            anyOk = anyOk || ok;
            appLogger.i('Session: playCmd-only sent to $mac (variant) → $ok');
            // Tiny pause between variants; helps some UART-like bridges.
            await Future<void>.delayed(const Duration(milliseconds: 150));
          }
          if (!anyOk) failed.add(mac);
        }

        if (failed.isNotEmpty) {
          state = state.copyWith(
            error: 'Failed to send playCmd to: ${failed.join(', ')}',
          );
          appLogger.w('Session: playCmd-only failed');
          return;
        }

        // In playCmd-only mode, we don't run the protocol timer.
        if (!_isActive) return;
        state = state.copyWith(status: SessionStatus.stopped, error: null);
        return;
      }

      if (state.protocol == null) return;

      appLogger.i(
        'Session: start payload source '
        '(common protocolId=${state.protocol!.id}, name=${state.protocol!.templateName}, sessions=${state.protocol!.sessions}, cycles=${state.protocol!.cycles.length})',
      );

      // For BLE we intentionally start UI timer only AFTER PLAY succeeds,
      // so elapsed time tracks physical device runtime.
      appLogger
          .i('Session: Starting BLE send sequence (timer starts after PLAY)');

      // Send protocol JSON to all connected devices over BLE (RS232 bridge)
      // first, then do ONE common delay, then send PLAY to all devices together.
      // This matches the web start flow and avoids per-device timing skew.
      _firstBlePlayAnchor = null;

      final failed = <String>[];

      // STEP 1: payload to all devices (concurrently)
      final payloadResults = await Future.wait(
        actuallyConnectedIds.map((mac) async {
          final deviceProtocol = state.protocolByDevice[mac];
          if (deviceProtocol == null) {
            failed.add(mac);
            return MapEntry(mac, false);
          }

          final legacyShape = _protocolToRs232Json(
            deviceProtocol,
            transportId: mac,
          );

          if (deviceProtocol.cycles.isNotEmpty) {
            final c0 = deviceProtocol.cycles.first;
            appLogger.i(
              'Session: protocol first-cycle '
              '(dur=${c0.durationSeconds}, rep=${c0.repetitions}, hot=${c0.hotPwm}, cold=${c0.coldPwm}, left=${c0.leftFunction}, right=${c0.rightFunction})',
            );
          }

          final protocolFrame = jsonEncode(legacyShape);
          final escapedFrame =
              protocolFrame.replaceAll('\r', r'\r').replaceAll('\n', r'\n');
          appLogger.i(
            'Session: BLE request (device=$mac, mac field=$mac): '
            '$escapedFrame',
          );

          appLogger.i(
            'Session: Sending protocol to $mac '
            '(mac key=$mac, ${protocolFrame.length} bytes, shape=web-rs35-flat)',
          );
          appLogger.i('📱 BLE Payload Details for $mac:');
          appLogger.i('   - cycles: ${deviceProtocol.cycles.length}');
          appLogger.i(
              '   - total duration: ${deviceProtocol.totalDurationSeconds}s');
          appLogger.i('   - payload size: ${protocolFrame.length} bytes');
          appLogger.i("🔥 CALLING BLE PAYLOAD NOW");

          final okProtocol = await _sendLargePayload(mac, protocolFrame);
          appLogger.i(
            "🔥 BLE PAYLOAD RESULT: okProtocol=$okProtocol for device=$mac",
          );

          return MapEntry(mac, okProtocol);
        }),
      );

      final payloadSucceeded = payloadResults
          .where((e) => e.value == true)
          .map((e) => e.key)
          .toList();
      final payloadFailed = payloadResults
          .where((e) => e.value == false)
          .map((e) => e.key)
          .toList();

      failed.addAll(payloadFailed);
      if (failed.isNotEmpty) {
        // Abort start if any device never received config.
        _stopwatch.stop();
        _timer?.cancel();
        _timer = null;
        if (!_isActive) return;
        state = state.copyWith(
          status: SessionStatus.stopped,
          error: 'Failed to send protocol payload to: ${failed.join(', ')}',
        );
        return;
      }

      // STEP 2: one common delay (matches web)
      const prePlayDelay = Duration(milliseconds: 2500);
      await Future<void>.delayed(prePlayDelay);

      // STEP 3: PLAY to all devices together (concurrently)
      final commonPlayAnchor = DateTime.now();
      final playResults = await Future.wait(
        payloadSucceeded.map((mac) async {
          appLogger.i('Session: Sending raw PLAY command (0x01) to $mac');
          final okRawPlay = await _sendPlayCommand(mac);
          appLogger.i(
            'Session: BLE raw PLAY command result for $mac → $okRawPlay',
          );
          return MapEntry(mac, MapEntry(okRawPlay, commonPlayAnchor));
        }),
      );

      final playFailed = playResults
          .where((e) => (e.value.key) == false)
          .map((e) => e.key)
          .toList();
      failed.addAll(playFailed);

      if (failed.isNotEmpty) {
        _stopwatch.stop();
        _timer?.cancel();
        _timer = null;
        if (!_isActive) return;
        // Stop whatever did start.
        unawaited(_completeDevices(payloadSucceeded));
        state = state.copyWith(
          status: SessionStatus.stopped,
          error: 'Failed to send PLAY to: ${failed.join(', ')}',
        );
        return;
      }

      // STEP 4: start per-device timers/status after PLAY succeeds for all
      await _enqueueStateUpdate(() {
        final timers = Map<String, TimerState>.from(state.deviceTimers);
        final statuses = Map<String, SessionStatus>.from(state.deviceStatuses);
        for (final mac in payloadSucceeded) {
          _deviceStopwatches[mac]?.start();
          timers[mac] = (timers[mac] ?? const TimerState()).copyWith(
            isRunning: true,
          );
          statuses[mac] = SessionStatus.running;
          _firstBlePlayAnchor = commonPlayAnchor;
        }
        state = state.copyWith(
          deviceTimers: timers,
          deviceStatuses: statuses,
          status: _deriveOverallStatus(statuses),
        );
      });

      _beginRuntimeTimer();
    } finally {
      _startInProgress = false;
    }
  }

  /// Protocol Plus: switch [mac] to [newProtocol] mid-session when the server
  /// emits START_PROTOCOL. Re-sends the full config + PLAY over BLE, or
  /// publishes config via MQTT for WiFi — reusing the exact senders the normal
  /// run uses. Does NOT reset the session timer or disturb the normal flow.
  Future<bool> applyProtocolPlusSwitch(
    String mac,
    Protocol newProtocol,
    int protocolIndex,
  ) async {
    if (!_isActive) return false;
    // Never resurrect a device that has already stopped. A START_PROTOCOL can
    // arrive late — after the user stopped the unit and we ended its run — and
    // without this guard we would happily re-PLAY a dead device.
    final devStatus = state.deviceStatuses[mac];
    if (devStatus == SessionStatus.stopped ||
        devStatus == SessionStatus.completed) {
      appLogger.w(
        'ProtocolPlus: switch for $mac ignored — device already $devStatus',
      );
      return false;
    }
    appLogger.i(
      'ProtocolPlus: switching device=$mac to ${newProtocol.templateName} '
      '(index=$protocolIndex, transport=${state.transport})',
    );

    // The switch itself sends STOP and waits ~4s before PLAY, so the device
    // genuinely reports rs=stop throughout. Mark it in-flight for the whole
    // body so the stop detector doesn't read our own switch as a user stop.
    _plusSwitchInFlight.add(mac);
    try {
      return await _applyProtocolPlusSwitchInner(
        mac,
        newProtocol,
        protocolIndex,
      );
    } finally {
      _plusSwitchInFlight.remove(mac);
    }
  }

  Future<bool> _applyProtocolPlusSwitchInner(
    String mac,
    Protocol newProtocol,
    int protocolIndex,
  ) async {

    // Reflect the new protocol per-device + advance the sequence indicator so
    // the live session screen highlights the now-active protocol chip.
    final updatedByDevice = Map<String, Protocol>.from(state.protocolByDevice)
      ..[mac] = newProtocol;
    // Re-derive this device's advanced settings from the NEW protocol so the
    // switch payload uses that protocol's own cycle1/cycle5 (edge cycle) and
    // vibration range — not the previous protocol's. Otherwise every protocol
    // in the sequence inherits protocol[0]'s edge-cycle flags.
    final updatedSettingsByDevice =
        Map<String, AdvancedSettings>.from(state.advancedSettingsByDevice)
          ..[mac] = _advancedSettingsForProtocol(newProtocol);
    final updatedIndexByDevice =
        Map<String, int>.from(state.protocolPlusIndexByDevice)
          ..[mac] = protocolIndex;

    // The switch landing IS the end of the break: this protocol now runs, so
    // re-base the segment end to "now + this protocol's runtime" and clear any
    // break flag for the device. The next break begins when this elapses.
    _plusSegmentEndByDevice[mac] = _deviceElapsed(mac) +
        Duration(seconds: _plusProtocolDurationSeconds(newProtocol));
    // This switch's PLAY restarts the device, so whatever stop streak was
    // running belonged to the break before it.
    _plusStopSince.remove(mac);
    final clearedOnBreak =
        Map<String, bool>.from(state.protocolPlusOnBreakByDevice)
          ..[mac] = false;
    final clearedBreakRemaining =
        Map<String, int>.from(state.protocolPlusBreakRemainingByDevice)
          ..[mac] = 0;
    try {
      state = state.copyWith(
        protocolByDevice: updatedByDevice,
        advancedSettingsByDevice: updatedSettingsByDevice,
        protocolPlusIndex: protocolIndex,
        protocolPlusIndexByDevice: updatedIndexByDevice,
        protocolPlusOnBreakByDevice: clearedOnBreak,
        protocolPlusBreakRemainingByDevice: clearedBreakRemaining,
      );
      // Reflect the Protocol Plus switch in the foreground notification.
      _pushNotificationSync();
    } catch (_) {}

    final payloadStr =
        jsonEncode(_protocolToRs232Json(newProtocol, transportId: mac));

    if (state.transport == SessionTransport.wifi) {
      try {
        await postMqttPublishRequest(
          _ref.read(djangoDioProvider),
          data: {
            'topic': 'HydraWav3Pro/config',
            'payload': payloadStr,
          },
        );
        appLogger.i('ProtocolPlus: WiFi config published for $mac');
        return true;
      } catch (e) {
        appLogger.e('ProtocolPlus: WiFi switch failed for $mac: $e');
        return false;
      }
    }

    // BLE: full config → settle delay → PLAY (same sequence as a fresh start).
    final connector = _ref.read(bleConnectorProvider);

    // The firmware physically stops when protocol[i-1] finishes and can drop
    // BLE during the gap before this switch. The connector auto-reconnects, so
    // wait briefly for it to come back instead of abandoning the switch.
    if (!connector.isConnected(mac)) {
      appLogger.w(
        'ProtocolPlus: BLE device $mac not connected — waiting for reconnect…',
      );
      const pollEvery = Duration(milliseconds: 500);
      const maxWait = Duration(seconds: 12);
      var waited = Duration.zero;
      while (waited < maxWait && !connector.isConnected(mac)) {
        await Future<void>.delayed(pollEvery);
        waited += pollEvery;
        if (!_isActive) return false;
      }
      if (!connector.isConnected(mac)) {
        appLogger.e(
          'ProtocolPlus: BLE device $mac still not connected after '
          '${maxWait.inSeconds}s — switch skipped',
        );
        return false;
      }
      appLogger.i('ProtocolPlus: BLE device $mac reconnected — switching now');
    }

    // STOP → reset → config → settle → PLAY, with one retry on failure.
    //
    // CRITICAL: a fresh start works because the device is IDLE when it receives
    // config+PLAY. At a Protocol Plus switch the device has just FINISHED
    // protocol[i-1] ("beep + stop") and is in a completed/BUSY state — if we
    // send config+PLAY in that state the firmware only half-accepts it (device
    // "runs a few parts then stops"). Sending STOP first forces the firmware
    // back to idle so the new config+PLAY behaves exactly like a clean start.
    for (var attempt = 1; attempt <= 2; attempt++) {
      // 1) Reset firmware to idle.
      final okStop = await connector.writeToDevice(mac, [_bleStopByte]);
      appLogger.i('ProtocolPlus: BLE pre-switch STOP for $mac → $okStop');
      await Future<void>.delayed(const Duration(milliseconds: 800));

      // 2) Push the new protocol config.
      final okPayload = await _sendLargePayload(mac, payloadStr);
      if (!okPayload) {
        appLogger.e(
          'ProtocolPlus: BLE config send failed for $mac (attempt $attempt)',
        );
        if (attempt == 2 || !connector.isConnected(mac)) return false;
        await Future<void>.delayed(const Duration(milliseconds: 600));
        continue;
      }

      // 3) Settle, then PLAY (same timing as a fresh start).
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      final okPlay = await _sendPlayCommand(mac);
      appLogger.i(
        'ProtocolPlus: BLE switch PLAY for $mac → $okPlay (attempt $attempt)',
      );
      if (okPlay) return true;
      if (attempt == 2) return false;
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return false;
  }

  /// Protocol Plus: make the whole session span [seconds] (the protocol-plus
  /// totalDuration) so it does NOT complete when protocol[0] ends — later
  /// protocols (driven by START_PROTOCOL) keep counting toward this total.
  /// Call right after loadSession(), before start().
  /// Protocol Plus: store the sequence title + ordered sub-protocol names so
  /// the live session screen can render the tracker and highlight the active
  /// protocol.
  void setProtocolPlusSequence(String plusName, List<String> names) {
    if (!_isActive || names.isEmpty) return;
    _isProtocolPlus = true;
    state = state.copyWith(
      protocolPlusName: plusName,
      protocolPlusSequence: List<String>.from(names),
      protocolPlusIndex: 0,
    );
    appLogger.i('ProtocolPlus: "$plusName" sequence → ${names.join(" → ")}');
  }

  /// Per-device Protocol Plus sequences for mixed / multi-Plus sessions. Each
  /// Plus device gets its own tracker; normal devices are absent from these
  /// maps and render normal controls instead of a progress card.
  void setProtocolPlusSequencesByDevice(
    Map<String, String> nameByDevice,
    Map<String, List<String>> sequenceByDevice, {
    Map<String, int> delayByDevice = const {},
    Map<String, List<int>> durationsByDevice = const {},
  }) {
    if (!_isActive || sequenceByDevice.isEmpty) return;
    _isProtocolPlus = true;
    state = state.copyWith(
      protocolPlusNameByDevice: Map<String, String>.from(nameByDevice),
      protocolPlusSequenceByDevice: {
        for (final e in sequenceByDevice.entries)
          e.key: List<String>.from(e.value),
      },
      protocolPlusIndexByDevice: {
        for (final id in sequenceByDevice.keys) id: 0,
      },
      protocolPlusDurationsByDevice: {
        for (final e in durationsByDevice.entries)
          e.key: List<int>.from(e.value),
      },
      protocolPlusDelayByDevice: Map<String, int>.from(delayByDevice),
    );
    appLogger.i(
      'ProtocolPlus: per-device sequences set for ${sequenceByDevice.keys.join(", ")}',
    );
  }

  /// Mark which devices are running a server-driven Protocol Plus sequence so
  /// the tick loop doesn't auto-complete them when one protocol's time elapses.
  void setProtocolPlusDevices(Set<String> deviceIds) {
    if (!_isActive) return;
    _protocolPlusDeviceIds
      ..clear()
      ..addAll(deviceIds);
    if (deviceIds.isNotEmpty) _isProtocolPlus = true;
  }

  /// Called by [ProtocolPlusController] whenever a `START_PROTOCOL` switch for
  /// [mac] starts being applied, is held for a disconnected device, or is
  /// re-queued after a failed write — and again once it lands. While pending,
  /// the device's `rs:"stop"` is read as the expected inter-protocol idle
  /// instead of a user stop. See [_isExpectedPlusBreakStop].
  void setPlusSwitchPending(String mac, bool pending) {
    if (pending) {
      _plusSwitchPendingExternal.add(mac);
      // A switch is outstanding → the idle we're seeing is expected, so the
      // streak we were accumulating belongs to the break.
      _plusStopSince.remove(mac);
    } else {
      _plusSwitchPendingExternal.remove(mac);
    }
  }

  /// Device-elapsed (monotonic + slept-time catch-up) for [id].
  Duration _deviceElapsed(String id) =>
      (_deviceStopwatches[id]?.elapsed ?? Duration.zero) +
      (_deviceClockOffset[id] ?? Duration.zero);

  /// True when [id]'s Protocol Plus sequence has no further sub-protocol to
  /// switch to — i.e. it is running the LAST one, so when that finishes the
  /// whole run is genuinely over (no START_PROTOCOL arrives after it). Handles
  /// both per-device sequences (mixed/multi-Plus) and the single-device
  /// sequence. When the sequence is unknown (length 0) we treat it as final so
  /// an elapsed whole-sequence clock can still end the run rather than hang
  /// "running" forever — the failure mode this guards against.
  bool _isPlusDeviceOnFinalProtocol(String id) {
    final perDeviceSeq = state.protocolPlusSequenceByDevice[id];
    final seqLen = (perDeviceSeq != null && perDeviceSeq.isNotEmpty)
        ? perDeviceSeq.length
        : state.protocolPlusSequence.length;
    if (seqLen <= 1) return true; // single/unknown → nothing comes next
    final index =
        state.protocolPlusIndexByDevice[id] ?? state.protocolPlusIndex;
    return index >= seqLen - 1;
  }

  /// Firmware runtime of a single sub-protocol, in seconds — used to predict
  /// when one protocol in the stack ends and the break to the next begins.
  /// Mirrors the duration the server uses to schedule START_PROTOCOL switches.
  int _plusProtocolDurationSeconds(Protocol p) =>
      _computeFirmwareTotalDurationSeconds(p, _advancedSettingsForProtocol(p));

  /// Seed each Plus device's first-protocol segment end (protocol[0]). Called
  /// once the run starts ticking; the break tracker reads these in [_onTick].
  void _initPlusSegmentEnds() {
    final ids = _plusDeviceIds();
    if (ids.isEmpty) return;
    for (final id in ids) {
      final first = state.protocolByDevice[id];
      if (first == null) continue;
      _plusSegmentEndByDevice[id] =
          Duration(seconds: _plusProtocolDurationSeconds(first));
    }
  }

  /// Devices running a Protocol Plus sequence — the explicit set, falling back
  /// to the per-device sequence map (single-Plus sessions populate one or both).
  Iterable<String> _plusDeviceIds() => _protocolPlusDeviceIds.isNotEmpty
      ? _protocolPlusDeviceIds
      : state.protocolPlusSequenceByDevice.keys;

  /// Override per-device total durations (each Protocol Plus has its own total
  /// length). The overall session timer tracks the longest device. Call after
  /// loadSession(), before start().
  void setDeviceTotalDurations(Map<String, int> secondsByDevice) {
    if (!_isActive || secondsByDevice.isEmpty) return;
    final devTimers = Map<String, TimerState>.from(state.deviceTimers);
    secondsByDevice.forEach((id, secs) {
      if (secs <= 0) return;
      final t = devTimers[id];
      if (t != null) {
        devTimers[id] = t.copyWith(totalDuration: Duration(seconds: secs));
      }
    });
    var maxDur = state.timer.totalDuration;
    for (final t in devTimers.values) {
      if (t.totalDuration > maxDur) maxDur = t.totalDuration;
    }
    state = state.copyWith(
      deviceTimers: devTimers,
      timer: state.timer.copyWith(totalDuration: maxDur),
    );
    appLogger.i(
      'Session: per-device durations set (${secondsByDevice.length} devices, '
      'overall=${maxDur.inSeconds}s)',
    );
  }

  void setSessionTotalDuration(int seconds) {
    if (!_isActive || seconds <= 0) return;
    // Only Protocol Plus extends the session beyond a single protocol, so this
    // is the reliable signal that we're in a server-driven sequence.
    _isProtocolPlus = true;
    final total = Duration(seconds: seconds);
    final devTimers = <String, TimerState>{
      for (final e in state.deviceTimers.entries)
        e.key: e.value.copyWith(totalDuration: total),
    };
    state = state.copyWith(
      timer: state.timer.copyWith(totalDuration: total),
      deviceTimers: devTimers,
    );
    appLogger
        .i('Session: total duration overridden to ${seconds}s (protocol+)');
  }

  void _beginRuntimeTimer() {
    appLogger.i(
      'Session: Runtime timer started (clockOffset=$_sessionClockOffset)',
    );
    if (!_isActive) return;
    try {
      state = state.copyWith(
        status: _deriveOverallStatus(state.deviceStatuses),
        error: null,
      );
    } catch (e) {
      appLogger
          .d('Session: timer start state update ignored (notifier disposed)');
      return;
    }
    final alreadyRunning = _stopwatch.isRunning;
    if (!alreadyRunning) {
      _stopwatch.reset();
      _stopwatch.start();
    }
    _initPlusSegmentEnds();
    _anchorWallClock();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 250), _onTick);
    // Periodic timer does not fire until the first interval; sync once now
    // so remaining time and cycle/pad UI match the device immediately.
    _syncDisplayedTimerFromStopwatch();
    unawaited(_syncBackgroundRuntime('running'));
    unawaited(_captureSessionHistoryOnce());
  }

  /// Persist this session to history exactly once, the moment it starts
  /// running — independent of any screen being open. The repository also
  /// dedupes by session id, so re-opening the live session never creates a
  /// duplicate intake.
  Future<void> _captureSessionHistoryOnce() async {
    if (_historyCaptured) return;
    if (state.protocol == null) return;
    _historyCaptured = true;
    try {
      final userId = _ref.read(authStateProvider).user?.id;
      // clientType / clientId / intake come from the context set on the engine
      // by the launcher (setClientContext) — guest when none was provided.
      // Local-only draft — NO placeholder pain, NO backend POST. The real
      // record (with post-session answers / discomfortAfter / notes) is POSTed
      // once at finalize, after the outcomes sheet. See pendingOutcomesProvider.
      final record = getSessionRecord(
        sessionId: sessionId,
        createdBy: userId,
        updatedBy: userId,
      );
      if (record == null) {
        _historyCaptured = false;
        return;
      }
      await _ref.read(sessionRepositoryProvider).saveSessionDraft(record);
      appLogger.i('Session: draft captured on start for $sessionId');
    } catch (e) {
      appLogger.e('Session: failed to capture history on start: $e');
    }
  }

  Future<void> _syncBackgroundRuntime(String status) async {
    if (!_isActive || state.protocol == null || state.deviceIds.isEmpty) return;
    final startedAtMs = _firstBlePlayAnchor?.millisecondsSinceEpoch ??
        DateTime.now().millisecondsSinceEpoch;
    final snapshot = LiveSessionSnapshot(
      sessionId: sessionId,
      protocolId: state.protocol!.id,
      protocolName: state.protocol!.templateName,
      deviceIds: List<String>.from(state.deviceIds),
      transport: state.transport == SessionTransport.wifi ? 'wifi' : 'ble',
      startedAtEpochMs: startedAtMs,
      delayedDeviceId: state.delayedDeviceId,
      protocolByDeviceId: {
        for (final entry in state.protocolByDevice.entries)
          entry.key: entry.value.id,
      },
      advancedSettings: state.advancedSettings,
      advancedSettingsByDevice:
          Map<String, AdvancedSettings>.from(state.advancedSettingsByDevice),
      fromBackgroundService: true,
    );

    final runtime = _ref.read(backgroundSessionRuntimeProvider.notifier);
    if (status == 'running') {
      await runtime.startService(snapshot);
    } else if (status == 'paused') {
      await runtime.pauseService(sessionId: sessionId);
    } else if (status == 'resumed') {
      await runtime.resumeService(sessionId: sessionId);
    } else if (status == 'stopped') {
      await runtime.stopService(sessionId: sessionId);
    } else {
      await runtime.cacheSnapshotOnly(snapshot);
    }
    // Always refresh the notification's per-device rows + current protocol so it
    // reflects the live in-app state (Protocol Plus switches, per-device status).
    _pushNotificationSync();
  }

  String _bgStatusString(SessionStatus? status) {
    switch (status) {
      case SessionStatus.running:
        return 'running';
      case SessionStatus.paused:
        return 'paused';
      case SessionStatus.completed:
      case SessionStatus.stopped:
        return 'stopped';
      default:
        return 'idle';
    }
  }

  /// Sync the Android foreground-service notification with the current session:
  /// overall status, the protocol each device is running (Protocol Plus aware),
  /// and per-device status. Safe to call often — it no-ops off Android and when
  /// no session is live.
  void _pushNotificationSync() {
    if (!_isActive || state.protocol == null || state.deviceIds.isEmpty) return;
    final ids = List<String>.from(state.deviceIds);
    final names = ids
        .map((id) =>
            state.protocolByDevice[id]?.templateName ??
            state.protocol?.templateName ??
            'Protocol')
        .toList();
    final statuses =
        ids.map((id) => _bgStatusString(state.deviceStatuses[id])).toList();
    final title = state.protocolByDevice[ids.first]?.templateName ??
        state.protocol?.templateName ??
        'Hydrawav Session';
    unawaited(
      _ref.read(backgroundSessionRuntimeProvider.notifier).updateSession(
            sessionId: sessionId,
            status: _bgStatusString(_deriveOverallStatus(state.deviceStatuses)),
            protocolName: title,
            deviceIds: ids,
            deviceNames: names,
            deviceStatuses: statuses,
          ),
    );
  }

  /// Advanced settings derived from a protocol's own fields. Keeps the
  /// edge-cycle flags (cycle1/cycle5) and vibration range in sync with the
  /// protocol so the firmware doesn't run an unexpected initiation cycle.
  /// Mirrors the derivation used when launching a Protocol Plus run.
  AdvancedSettings _advancedSettingsForProtocol(Protocol p) => AdvancedSettings(
        cycle1Initiation: p.cycle1,
        cycle5Completion: p.cycle5,
        vibrationSweepMin: p.vibmin,
        vibrationSweepMax: p.vibmax,
        vibMin: p.vibmin,
        vibMax: p.vibmax,
        hotDrop: p.hotdrop,
        coldDrop: p.colddrop,
      );

  /// Public wrapper over the firmware payload builder, for at-home client
  /// sessions that run a single device directly over BLE (no backend session,
  /// default advanced settings). Mirrors the web `templateToRS35Payload`.
  Map<String, dynamic> buildFirmwarePayload(
    Protocol p, {
    required String mac,
  }) {
    return _protocolToRs35Payload(
      p,
      mac: mac,
      advancedSettings: const AdvancedSettings(),
      applyStartDelay: false,
    );
  }

  Map<String, dynamic> _protocolToRs232Json(
    Protocol p, {
    required String transportId,
  }) {
    final advancedSettings =
        state.advancedSettingsByDevice[transportId] ?? state.advancedSettings;
    final applyDelay = _shouldApplyStartDelay(
      transportId: transportId,
      advancedSettings: advancedSettings,
    );
    return _protocolToRs35Payload(
      p,
      mac: transportId,
      advancedSettings: advancedSettings,
      applyStartDelay: applyDelay,
    );
  }

  Map<String, dynamic> _protocolToRs35Payload(
    Protocol p, {
    required String mac,
    required AdvancedSettings advancedSettings,
    required bool applyStartDelay,
  }) {
    final cycles = p.cycles;

    // Intensity mapping from web sender (0–11).
    const hotMap = <int, int>{
      0: 0,
      1: 50,
      2: 55,
      3: 60,
      4: 65,
      5: 70,
      6: 75,
      7: 80,
      8: 85,
      9: 90,
      10: 95,
      11: 100,
    };
    const coldMap = <int, int>{
      0: 0,
      1: 150,
      2: 160,
      3: 170,
      4: 180,
      5: 190,
      6: 200,
      7: 210,
      8: 220,
      9: 230,
      10: 240,
      11: 250,
    };

    List<String> leftFuncs = cycles.map((c) => c.leftFunction).toList();
    List<String> rightFuncs = cycles.map((c) => c.rightFunction).toList();

    if (advancedSettings.flipSettings) {
      String flip(String fn) {
        if (fn.contains('HotRed')) return fn.replaceAll('HotRed', 'ColdBlue');
        if (fn.contains('ColdBlue')) return fn.replaceAll('ColdBlue', 'HotRed');
        return fn;
      }

      leftFuncs = leftFuncs.map(flip).toList();
      rightFuncs = rightFuncs.map(flip).toList();
    }

    final hotPwm = hotMap[advancedSettings.hotLevel.clamp(0, 11)] ?? 70;
    final coldPwm = coldMap[advancedSettings.coldLevel.clamp(0, 11)] ?? 190;
    final pwmHot = advancedSettings.hotPack
        ? cycles.map((_) => hotPwm).toList()
        : cycles.map((c) => c.hotPwm.toInt()).toList();
    final pwmCold = advancedSettings.coldPack
        ? cycles.map((_) => coldPwm).toList()
        : cycles.map((c) => c.coldPwm.toInt()).toList();

    final vibMode = advancedSettings.vibrationMode;
    final vibMin = switch (vibMode) {
      'Off' => 0,
      'Single' => advancedSettings.vibrationSingleHz.clamp(10, 230).toInt(),
      'Sweep' => advancedSettings.vibrationSweepMin.toInt(),
      _ => advancedSettings.vibMin.toInt(),
    };
    final vibMax = switch (vibMode) {
      'Off' => 1,
      'Single' =>
        (advancedSettings.vibrationSingleHz.clamp(10, 230).toInt() + 10),
      'Sweep' => advancedSettings.vibrationSweepMax.toInt(),
      _ => advancedSettings.vibMax.toInt(),
    };
    final edgeCycleDuration = _effectiveEdgeCycleDurationSeconds(
      p,
      advancedSettings,
    );
    final totalDuration = _computeEffectiveTotalDurationSeconds(
      p,
      advancedSettings,
      applyStartDelay: applyStartDelay,
    );

    return {
      'mac': mac,
      'sessionCount': p.sessions,
      'sessionPause': p.sessionPause.toInt(),
      'sDelay': applyStartDelay ? advancedSettings.startDelay : 0,
      'cycle1': advancedSettings.cycle1Initiation ? 1 : 0,
      'cycle5': advancedSettings.cycle5Completion ? 1 : 0,
      'edgeCycleDuration': edgeCycleDuration,
      'cycleRepetitions': cycles.map((c) => c.repetitions).toList(),
      'cycleDurations': cycles.map((c) => c.durationSeconds.toInt()).toList(),
      'cyclePauses': cycles.map((c) => c.pauseSeconds.toInt()).toList(),
      'pauseIntervals': cycles.map((c) => c.cyclePause.toInt()).toList(),
      'leftFuncs': leftFuncs,
      'rightFuncs': rightFuncs,
      'pwmValues': {
        'hot': pwmHot,
        'cold': pwmCold,
      },
      'playCmd': 1,
      'led': advancedSettings.lights ? 1 : 0,
      'hotDrop': advancedSettings.hotDrop.toInt(),
      'coldDrop': advancedSettings.coldDrop.toInt(),
      'vibMin': vibMin,
      'vibMax': vibMax,
      'totalDuration': totalDuration,
    };
  }

  int _computeFirmwareTotalDurationSeconds(
    Protocol p,
    AdvancedSettings advancedSettings,
  ) {
    final cycles = p.cycles;
    // No cycles to compute from (e.g. a Protocol Plus parent entry) → fall back
    // to the server-provided total. Real sub-protocols always carry cycles here.
    if (cycles.isEmpty) return p.totalDurationSeconds;

    // Mirror web calculateFirmwareTotalDuration: sum EVERY cycle's active time,
    // adding the trailing inter-cycle pause for all cycles except the last. The
    // old code summed only the first three cycles and, for <3-cycle protocols,
    // returned the server's nominal totalDuration — which could leak a whole-
    // sequence (Protocol Plus) total into a single sub-protocol's firmware
    // command, making the firmware's self-stop clock run far past the app's
    // "completed" so the device kept running.
    int baseTimeline = 0;
    for (var i = 0; i < cycles.length; i++) {
      final c = cycles[i];
      baseTimeline +=
          c.repetitions * ((c.durationSeconds + c.pauseSeconds).toInt());
      if (i < cycles.length - 1) {
        baseTimeline += c.cyclePause.toInt();
      }
    }

    if (p.sessions > 1) {
      baseTimeline = (baseTimeline * p.sessions) +
          (p.sessionPause.toInt() * (p.sessions - 1));
    }

    final edgeCycleDuration = _effectiveEdgeCycleDurationSeconds(
      p,
      advancedSettings,
    );

    if (advancedSettings.cycle1Initiation) {
      baseTimeline += edgeCycleDuration + 30;
    }
    if (advancedSettings.cycle5Completion) {
      baseTimeline += edgeCycleDuration + 30;
    }

    return baseTimeline;
  }

  bool _shouldApplyStartDelay({
    required String transportId,
    required AdvancedSettings advancedSettings,
  }) {
    final selectedDelayedDeviceId = state.delayedDeviceId;
    final hasSelectedDelayedDevice = selectedDelayedDeviceId != null &&
        state.deviceIds.contains(selectedDelayedDeviceId);
    return advancedSettings.startDelay > 0 &&
        (!hasSelectedDelayedDevice || selectedDelayedDeviceId == transportId);
  }

  int _computeEffectiveTotalDurationSeconds(
    Protocol p,
    AdvancedSettings advancedSettings, {
    required bool applyStartDelay,
  }) {
    final baseDuration = _computeFirmwareTotalDurationSeconds(
      p,
      advancedSettings,
    );
    return baseDuration + (applyStartDelay ? advancedSettings.startDelay : 0);
  }

  int _effectiveEdgeCycleDurationSeconds(
    Protocol p,
    AdvancedSettings advancedSettings,
  ) {
    return (advancedSettings.cycle1Initiation ||
            advancedSettings.cycle5Completion)
        ? 9
        : p.edgecycleduration.toInt();
  }

  Future<void> pause() async {
    if (!_isActive) return; // Guard against updates after disposal
    if (state.status != SessionStatus.running) return;

    appLogger.i('🔥 PAUSE: Sending pause command to device');
    if (state.transport == SessionTransport.wifi) {
      // WiFi pause command = playCmd=3
      await _publishWifiPlayCmd(3);
      appLogger.i('🔥 PAUSE: WiFi playCmd=3 sent');
    } else if (state.transport == SessionTransport.ble) {
      // Send BLE pause command to session devices only
      if (state.deviceIds.isNotEmpty) {
        final connector = _ref.read(bleConnectorProvider);

        for (final mac in state.deviceIds) {
          await connector.writeToDevice(mac, [_blePauseByte]);
          appLogger.i('🔥 PAUSE: BLE 0x$_blePauseByte sent to $mac');
        }
      }
    }

    for (final id in state.deviceIds) {
      _deviceStopwatches[id]?.stop();
    }
    final statuses = Map<String, SessionStatus>.from(state.deviceStatuses);
    for (final id in state.deviceIds) {
      if (statuses[id] == SessionStatus.running)
        statuses[id] = SessionStatus.paused;
    }
    try {
      state = state.copyWith(
        deviceStatuses: statuses,
        status: _deriveOverallStatus(statuses),
      );
      appLogger.i('🔥 PAUSE: State updated to paused');
      unawaited(_syncBackgroundRuntime('paused'));
    } catch (e) {
      appLogger.d('Session: pause() state update ignored (notifier disposed)');
    }
  }

  Future<void> resume() async {
    if (!_isActive) return; // Guard against updates after disposal
    if (state.status != SessionStatus.paused) return;

    appLogger.i('🔄 RESUME: Sending resume/continue command to device');
    try {
      state = state.copyWith(status: SessionStatus.running);
    } catch (e) {
      appLogger.d('Session: resume() state update ignored (notifier disposed)');
    }

    if (state.transport == SessionTransport.wifi) {
      // WiFi resume/continue command = playCmd=4
      // This continues the session from where it was paused
      await _publishWifiPlayCmd(4);
      appLogger.i('🔄 RESUME: WiFi playCmd=4 sent (continue from pause)');
    } else if (state.transport == SessionTransport.ble) {
      // Send BLE resume/continue command to session devices only
      // 0x04 = Resume/Continue (NOT 0x01 which is start)
      if (state.deviceIds.isNotEmpty) {
        final connector = _ref.read(bleConnectorProvider);

        for (final mac in state.deviceIds) {
          await connector.writeToDevice(mac, [_bleResumeByte]);
          appLogger.i(
            '🔄 RESUME: BLE 0x$_bleResumeByte sent to $mac (continue from pause)',
          );
        }
      }
    }

    for (final id in state.deviceIds) {
      if (state.deviceStatuses[id] == SessionStatus.paused) {
        _deviceStopwatches[id]?.start();
      }
    }
    final statuses = Map<String, SessionStatus>.from(state.deviceStatuses);
    for (final id in state.deviceIds) {
      if (statuses[id] == SessionStatus.paused)
        statuses[id] = SessionStatus.running;
    }
    state = state.copyWith(
      deviceStatuses: statuses,
      status: _deriveOverallStatus(statuses),
    );
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 250), _onTick);
    _anchorWallClock();
    _syncDisplayedTimerFromStopwatch();
    appLogger.i('🔄 RESUME: Timer restarted on app side');
    unawaited(_syncBackgroundRuntime('resumed'));
  }

  Future<void> stop() async {
    // Send stop command to devices via transport-specific method
    appLogger.i('🛑 STOP: Sending stop command to device');
    if (state.transport == SessionTransport.wifi) {
      // WiFi stop command = playCmd=2
      await _publishWifiPlayCmd(2);
      appLogger.i('🛑 STOP: WiFi playCmd=2 sent');
    } else if (state.transport == SessionTransport.ble) {
      // Send BLE stop command to session devices only
      if (state.deviceIds.isNotEmpty) {
        final connector = _ref.read(bleConnectorProvider);

        for (final mac in state.deviceIds) {
          await connector.writeToDevice(mac, [_bleStopByte]);
          appLogger.i('🛑 STOP: BLE 0x$_bleStopByte sent to $mac');
        }
      }
    }

    _stopwatch.stop();
    _timer?.cancel();
    for (final id in state.deviceIds) {
      _deviceStopwatches[id]?.stop();
      // Session ended → don't let the auto-reconnect loop pull devices back.
      _suppressDeviceReconnect(id);
    }
    if (!_isActive) return;
    try {
      final statuses = Map<String, SessionStatus>.from(state.deviceStatuses);
      for (final id in state.deviceIds) {
        statuses[id] = SessionStatus.stopped;
      }
      state = state.copyWith(
        deviceStatuses: statuses,
        status: SessionStatus.stopped,
      );
      unawaited(_syncBackgroundRuntime('stopped'));
    } catch (e) {
      appLogger.d('Session: stop() state update ignored (notifier disposed)');
    }
  }

  Future<void> pauseDevice(String deviceId) async {
    if (state.deviceStatuses[deviceId] != SessionStatus.running) return;
    if (state.transport == SessionTransport.wifi) {
      await _publishWifiPlayCmdToMac(deviceId, 3);
    } else {
      final connector = _ref.read(bleConnectorProvider);
      // Safety net: never write to (or flip the status of) a device whose BLE
      // link is down — the command can't reach it and would desync app/device.
      // The UI also disables the control while disconnected.
      if (!connector.isConnected(deviceId)) {
        appLogger.w('Session: pauseDevice skipped — $deviceId not connected');
        return;
      }
      await connector.writeToDevice(deviceId, [_blePauseByte]);
    }
    _deviceStopwatches[deviceId]?.stop();
    final statuses = Map<String, SessionStatus>.from(state.deviceStatuses)
      ..[deviceId] = SessionStatus.paused;
    state = state.copyWith(
      deviceStatuses: statuses,
      status: _deriveOverallStatus(statuses),
    );
  }

  Future<void> resumeDevice(String deviceId) async {
    if (state.deviceStatuses[deviceId] != SessionStatus.paused) return;
    if (state.transport == SessionTransport.wifi) {
      await _publishWifiPlayCmdToMac(deviceId, 4);
    } else {
      final connector = _ref.read(bleConnectorProvider);
      if (!connector.isConnected(deviceId)) {
        appLogger.w('Session: resumeDevice skipped — $deviceId not connected');
        return;
      }
      await connector.writeToDevice(deviceId, [_bleResumeByte]);
    }
    _deviceStopwatches[deviceId]?.start();
    final statuses = Map<String, SessionStatus>.from(state.deviceStatuses)
      ..[deviceId] = SessionStatus.running;
    state = state.copyWith(
      deviceStatuses: statuses,
      status: _deriveOverallStatus(statuses),
    );
    if (_timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 250), _onTick);
    }
  }

  Future<void> stopDevice(String deviceId) async {
    if (state.transport == SessionTransport.wifi) {
      await _publishWifiPlayCmdToMac(deviceId, 2);
    } else {
      final connector = _ref.read(bleConnectorProvider);
      if (connector.isConnected(deviceId)) {
        await connector.writeToDevice(deviceId, [_bleStopByte]);
      } else if (_protocolPlusDeviceIds.contains(deviceId)) {
        // Protocol Plus between protocols: the firmware has finished the current
        // protocol and is IDLE (BLE link expected to be down during the break),
        // so there's nothing running to desync. Skip the unreachable STOP write
        // but STILL end the run locally — the controller, on the engine's
        // terminal state, cancels the server-scheduled remaining protocols so no
        // further START_PROTOCOL switch fires.
        appLogger.i(
          'Session: stopDevice — $deviceId (Plus) idle/disconnected during '
          'break; ending run + cancelling server schedule',
        );
      } else {
        // Normal run: a disconnected device keeps running autonomously, so
        // flipping it to stopped would desync app vs device. Leave it alone.
        appLogger.w('Session: stopDevice skipped — $deviceId not connected');
        return;
      }
    }
    _deviceStopwatches[deviceId]?.stop();
    // This device is stopping → don't let it auto-reconnect.
    _suppressDeviceReconnect(deviceId);
    final statuses = Map<String, SessionStatus>.from(state.deviceStatuses)
      ..[deviceId] = SessionStatus.stopped;
    if (statuses.values.every(
      (s) => s == SessionStatus.stopped || s == SessionStatus.completed,
    )) {
      _timer?.cancel();
      _timer = null;
      _stopwatch.stop();
    }
    final overallStatus = _deriveOverallStatus(statuses);
    state = state.copyWith(
      deviceStatuses: statuses,
      status: overallStatus,
    );
    if (overallStatus == SessionStatus.stopped ||
        overallStatus == SessionStatus.completed) {
      unawaited(_syncBackgroundRuntime('stopped'));
    }
  }

  /// A BLE disconnect is a CONNECTIVITY event, NOT a session-ending one. The
  /// Hydra firmware keeps running the loaded protocol autonomously after the
  /// link drops, so we keep the session and its timers running and never
  /// force-stop anything — parity with the web app, whose `gattserverdisconnected`
  /// handler only updates a connection badge and leaves the run alive.
  ///
  /// Applies to ALL BLE sessions (normal protocol and Protocol Plus). The BLE
  /// connector auto-reconnects in the background; if a Protocol Plus switch is
  /// due while disconnected, the write path reconnects on demand. The run ends
  /// only on its natural timer completion (or an explicit user stop) — not here.
  Future<void> handleBleDisconnect(String deviceId) async {
    if (!_isActive) return;
    if (state.transport != SessionTransport.ble) return;

    final currentStatus = state.deviceStatuses[deviceId];
    if (currentStatus == null) return;
    if (currentStatus == SessionStatus.stopped ||
        currentStatus == SessionStatus.completed) {
      return;
    }

    // Intentionally do NOT mark the device/session stopped, freeze its timer, or
    // stop the background runtime — the session continues through the disconnect.
    // The live connection state for the UI is tracked separately via
    // bleConnectionStatesProvider; this method must not end the run.
    appLogger.w(
      'Session: BLE device=$deviceId disconnected — keeping the session '
      'running (no forced stop; auto-reconnect in progress; session=$sessionId)',
    );
  }

  SessionRecord? getSessionRecord({
    String? sessionId,
    int? discomfortBefore,
    int? discomfortAfter,
    String? notes,
    String? clientType,
    String? clientId,
    GuidedAssessmentData? intake,
    String? createdBy,
    String? updatedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    if (state.protocol == null) return null;
    final recordedAt = createdAt ?? DateTime.now();
    final protocolByDeviceId = <String, ({String name, int durationSeconds})>{};
    for (final entry in state.protocolByDevice.entries) {
      final deviceId = entry.key;
      final proto = entry.value;
      // If this device is running a Protocol Plus sequence, prefer the
      // protocol-plus template name and the per-device total duration (the
      // server-driven whole-sequence length), otherwise use the local
      // sub-protocol name/duration.
      final isPlusDevice = _plusDeviceIds().contains(deviceId) ||
          state.protocolPlusNameByDevice.containsKey(deviceId);
      if (isPlusDevice) {
        final plusName = state.protocolPlusNameByDevice[deviceId] ??
            state.protocolPlusName ??
            proto.templateName;
        final devTimer = state.deviceTimers[deviceId];
        // Actual run time (elapsed), not the planned whole-sequence length.
        final plusDuration = devTimer != null
            ? devTimer.elapsed.inSeconds
            : _effectiveElapsed.inSeconds;
        protocolByDeviceId[deviceId] = (
          name: plusName,
          durationSeconds: plusDuration,
        );
      } else {
        final devTimer = state.deviceTimers[deviceId];
        protocolByDeviceId[deviceId] = (
          name: proto.templateName,
          durationSeconds:
              devTimer?.elapsed.inSeconds ?? _effectiveElapsed.inSeconds,
        );
      }
    }
    // Resolve client/guest context: explicit args win, else the context set on
    // the engine from the setup screen. clientType is derived from clientId.
    final resolvedClientId = clientId ?? _clientId;
    final resolvedIntake = intake ?? _intake;
    final resolvedClientType =
        clientType ?? (resolvedClientId != null ? 'client' : 'guest');
    return SessionRecord(
      id: sessionId ?? const Uuid().v4(),
      protocolId: state.protocol!.id,
      protocolName: state.protocol!.templateName,
      deviceIds: state.deviceIds,
      protocolByDeviceId: protocolByDeviceId,
      totalDurationSeconds: state.timer.totalDuration.inSeconds,
      elapsedSeconds: _effectiveElapsed.inSeconds,
      discomfortBefore: discomfortBefore,
      discomfortAfter: discomfortAfter,
      notes: notes,
      clientType: resolvedClientType,
      clientId: resolvedClientId,
      intake: resolvedIntake,
      createdBy: createdBy,
      updatedBy: updatedBy,
      createdAt: recordedAt,
      updatedAt: updatedAt ?? recordedAt,
      completedAt: recordedAt,
    );
  }

  void reset() {
    _timer?.cancel();
    _stopwatch.reset();
    _sessionClockOffset = Duration.zero;
    _firstBlePlayAnchor = null;
    _wallClockAnchor = null;
    _monotonicAnchor = Duration.zero;
    _deviceClockOffset.clear();
    _startInProgress = false;
    _historyCaptured = false;
    _cycleIndex = -1;
    _repetition = 0;
    _isProtocolPlus = false;
    _protocolPlusDeviceIds.clear();
    _plusSegmentEndByDevice.clear();
    _lastRsByDevice.clear();
    _clearPlusStopTracking();
    onPlusDeviceStoppedByUser = null;
    try {
      state = const SessionEngineState();
      unawaited(_ref
          .read(backgroundSessionRuntimeProvider.notifier)
          .stopService(sessionId: sessionId));
    } catch (e) {
      appLogger.d('Session: reset() state update ignored (notifier disposed)');
    }
  }

  void _onTick(Timer timer) {
    if (!_isActive || state.status != SessionStatus.running) {
      timer.cancel();
      _timer = null;
      return;
    }
    // Weigh any outstanding Plus `rs:stop` streak FIRST, so a confirmed
    // device-initiated stop lands before this tick paints the timers — the
    // countdown must not advance one more frame after the unit has stopped.
    _evaluatePlusDeviceStops();
    if (!_isActive || state.status != SessionStatus.running) return;
    _reconcileClockFromWall();
    _syncDisplayedTimerFromStopwatch();
  }

  void _syncDisplayedTimerFromStopwatch() {
    if (!_isActive || state.status != SessionStatus.running) return;

    final elapsed = _effectiveElapsed;
    final protocol = state.protocol;
    if (protocol == null) {
      _timer?.cancel();
      _timer = null;
      _stopwatch.stop();
      if (!_isActive) return;
      try {
        state = state.copyWith(
          status: SessionStatus.stopped,
          error: 'Session timer tick ignored — protocol is missing',
        );
      } catch (e) {
        appLogger.d(
          'Session: protocol-missing tick state update ignored (notifier disposed)',
        );
      }
      return;
    }

    final updatedTimers = Map<String, TimerState>.from(state.deviceTimers);
    final updatedStatuses =
        Map<String, SessionStatus>.from(state.deviceStatuses);
    final completedDevices = <String>[];

    for (final id in state.deviceIds) {
      final status = updatedStatuses[id] ?? SessionStatus.idle;
      final sw = _deviceStopwatches[id];
      final timerState = updatedTimers[id];
      if (sw == null || timerState == null) continue;
      if (status == SessionStatus.running) {
        final devElapsed =
            sw.elapsed + (_deviceClockOffset[id] ?? Duration.zero);
        if (devElapsed >= timerState.totalDuration) {
          // Protocol Plus: a MID-sequence protocol finishing is NOT the end of
          // the session — the firmware stops itself and the next protocol
          // arrives via START_PROTOCOL, so we keep the device "running" and just
          // clamp the display while waiting for that switch. But on the LAST
          // sub-protocol nothing comes next, so we MUST complete here — else the
          // engine sits in `running` at 00:00 forever: it never goes terminal,
          // so _finishRun never runs (device never gets a STOP, the foreground
          // notification never clears) and the session screen stays "running"
          // while the live card already reads "completed".
          final deviceIsPlus = _isPlusDevice(id);
          // Decide whether the WHOLE Plus run is genuinely over.
          // `timerState.totalDuration` is the whole-sequence total, so reaching
          // it means every switch should already have happened.
          final segEnd = _plusSegmentEndByDevice[id];
          final onFinal = _isPlusDeviceOnFinalProtocol(id);
          // Clean end: on the last sub-protocol and its own segment has elapsed.
          // The segment-end guard avoids an early cut-off when the last switch
          // landed late (segEnd pushed past the total) — let it finish first.
          final finalProtocolDone =
              onFinal && (segEnd == null || devElapsed >= segEnd);
          // Watchdog: well past the whole-sequence total but NOT on the final
          // sub-protocol → a mid-sequence START_PROTOCOL switch was lost and
          // none is realistically still coming. End the run instead of hanging
          // "running" at 00:00 forever. Switches always occur before the total,
          // so on a healthy run we're already on the final protocol here and
          // this never trips.
          final stuckPastTotal = !onFinal &&
              devElapsed >=
                  timerState.totalDuration + const Duration(seconds: 120);
          final plusRunDone = finalProtocolDone || stuckPastTotal;
          if (deviceIsPlus && !plusRunDone) {
            updatedTimers[id] = timerState.copyWith(
              elapsed: timerState.totalDuration,
              isRunning: true,
            );
          } else {
            completedDevices.add(id);
            updatedStatuses[id] = SessionStatus.completed;
            updatedTimers[id] = timerState.copyWith(
              elapsed: timerState.totalDuration,
              isRunning: false,
            );
            sw.stop();
            // Completed naturally → don't auto-reconnect this device.
            _suppressDeviceReconnect(id);
          }
        } else {
          updatedTimers[id] = timerState.copyWith(
            elapsed: devElapsed,
            isRunning: true,
          );
        }
      }
    }

    if (completedDevices.isNotEmpty) {
      unawaited(_completeDevices(completedDevices));
    }

    _calculateCurrentPosition(elapsed);

    if (!_isActive) return;

    final prevVisual = state.timer.lastVisualCycleIndex;
    final int newVisual;
    if (protocol.cycles.isEmpty) {
      newVisual = -1;
    } else if (_cycleIndex >= 0) {
      newVisual = _cycleIndex;
    } else if (prevVisual >= 0) {
      newVisual = prevVisual;
    } else {
      newVisual = 0;
    }

    final overallStatus = _deriveOverallStatus(updatedStatuses);

    final (onBreakByDevice, breakRemainingByDevice) =
        _computeBreakState(updatedStatuses);

    try {
      state = state.copyWith(
        timer: state.timer.copyWith(
          elapsed: elapsed,
          currentCycleIndex: _cycleIndex,
          currentRepetition: _repetition,
          lastVisualCycleIndex: newVisual,
          isRunning: overallStatus == SessionStatus.running,
        ),
        deviceTimers: updatedTimers,
        deviceStatuses: updatedStatuses,
        status: overallStatus,
        protocolPlusOnBreakByDevice: onBreakByDevice,
        protocolPlusBreakRemainingByDevice: breakRemainingByDevice,
      );
    } catch (e) {
      appLogger.d('Session: tick state update ignored (notifier disposed)');
    }

    if (overallStatus == SessionStatus.completed ||
        overallStatus == SessionStatus.stopped) {
      _timer?.cancel();
      _timer = null;
      _stopwatch.stop();
      enqueuePendingOutcome();
      unawaited(_syncBackgroundRuntime('stopped'));
    } else if (completedDevices.isNotEmpty) {
      // A device finished but the session is still live — refresh the
      // notification so that device shows as completed/stopped.
      _pushNotificationSync();
    }
  }

  /// Derive the live break state for every Plus device: a device is "on break"
  /// once its current protocol's runtime has elapsed but the next protocol's
  /// START_PROTOCOL switch hasn't landed yet. The remaining seconds count down
  /// the [protocolPlusDelayByDevice] gap; they sit at 0 if the server switch is
  /// running late. Returns empty maps when no Plus device is mid-break, so the
  /// state stays referentially stable (no needless rebuilds).
  (Map<String, bool>, Map<String, int>) _computeBreakState(
    Map<String, SessionStatus> statuses,
  ) {
    final onBreak = <String, bool>{};
    final remaining = <String, int>{};
    for (final id in _plusDeviceIds()) {
      if (statuses[id] != SessionStatus.running) continue;
      final sequence = state.protocolPlusSequenceByDevice[id];
      if (sequence == null || sequence.isEmpty) continue;
      final index = state.protocolPlusIndexByDevice[id] ?? 0;
      // No break after the final protocol — nothing comes next.
      if (index >= sequence.length - 1) continue;
      final segEnd = _plusSegmentEndByDevice[id];
      if (segEnd == null) continue;
      final devElapsed = _deviceElapsed(id);
      if (devElapsed < segEnd) continue;
      final delay = state.protocolPlusDelayByDevice[id] ?? 0;
      final left = (segEnd.inSeconds + delay) - devElapsed.inSeconds;
      onBreak[id] = true;
      remaining[id] = left > 0 ? left : 0;
    }
    // Preserve identity when nothing is on break to avoid churn.
    if (onBreak.isEmpty && state.protocolPlusOnBreakByDevice.isEmpty) {
      return (
        state.protocolPlusOnBreakByDevice,
        state.protocolPlusBreakRemainingByDevice,
      );
    }
    return (onBreak, remaining);
  }

  void _calculateCurrentPosition(Duration elapsed) {
    final protocol = state.protocol!;
    int accumulatedSeconds = 0;
    final elapsedSeconds = elapsed.inSeconds;

    for (int s = 0; s < protocol.sessions; s++) {
      for (int c = 0; c < protocol.cycles.length; c++) {
        final cycle = protocol.cycles[c];
        for (int r = 0; r < cycle.repetitions; r++) {
          accumulatedSeconds += cycle.durationSeconds.toInt();
          if (elapsedSeconds < accumulatedSeconds) {
            _cycleIndex = c;
            _repetition = r;
            return;
          }

          // Matches web payload mapping: pauseIntervals = cycle_pause.
          if (r < cycle.repetitions - 1) {
            accumulatedSeconds += cycle.cyclePause.toInt();
            if (elapsedSeconds < accumulatedSeconds) {
              _cycleIndex = -1;
              _repetition = r;
              return;
            }
          }
        }

        // Matches web payload mapping: cyclePauses = pause_seconds.
        accumulatedSeconds += cycle.pauseSeconds.toInt();
        if (elapsedSeconds < accumulatedSeconds) {
          _cycleIndex = -1;
          _repetition = cycle.repetitions > 0 ? cycle.repetitions - 1 : 0;
          return;
        }
      }

      if (s < protocol.sessions - 1) {
        accumulatedSeconds += protocol.sessionPause.toInt();
        if (elapsedSeconds < accumulatedSeconds) {
          _cycleIndex = -1;
          _repetition = 0;
          return;
        }
      }
    }

    _cycleIndex = protocol.cycles.isNotEmpty ? protocol.cycles.length - 1 : -1;
  }

  Future<void> _completeSession() async {
    appLogger.i('✅ SESSION COMPLETED: Time limit reached, stopping device');

    // CRITICAL: Stop the stopwatch and cancel timer FIRST
    _stopwatch.stop();
    _timer?.cancel();
    _timer = null;

    // THEN send STOP command to device (WiFi or BLE)
    appLogger.i('✅ SENDING STOP COMMAND TO DEVICE NOW');
    if (state.transport == SessionTransport.wifi) {
      await _publishWifiPlayCmd(2);
      appLogger.i('✅ WiFi STOP sent (playCmd=2)');
    } else if (state.transport == SessionTransport.ble) {
      if (state.deviceIds.isNotEmpty) {
        final connector = _ref.read(bleConnectorProvider);
        for (final mac in state.deviceIds) {
          await connector.writeToDevice(mac, [_bleStopByte]);
          appLogger.i('✅ BLE STOP sent to $mac (0x$_bleStopByte)');
        }
      }
    }

    // Finally, update UI state
    if (!_isActive) return;
    try {
      state = state.copyWith(
        status: SessionStatus.completed,
        timer: state.timer.copyWith(
          elapsed: state.timer.totalDuration,
          isRunning: false,
        ),
      );
      appLogger.i('✅ SESSION COMPLETED: UI state updated, device stopped');
    } catch (e) {
      appLogger.d(
        'Session: completeSession state update ignored (notifier disposed)',
      );
    }
  }

  Future<void> _completeDevices(List<String> deviceIds) async {
    if (deviceIds.isEmpty) return;
    if (state.transport == SessionTransport.wifi) {
      await Future.wait(
        deviceIds.map((mac) => _publishWifiPlayCmdToMac(mac, 2)),
      );
    } else {
      final connector = _ref.read(bleConnectorProvider);
      for (final id in deviceIds) {
        await connector.writeToDevice(id, [_bleStopByte]);
      }
    }
  }

  SessionStatus _deriveOverallStatus(Map<String, SessionStatus> statuses) {
    if (statuses.values.any((s) => s == SessionStatus.running)) {
      return SessionStatus.running;
    }
    if (statuses.values.any((s) => s == SessionStatus.paused)) {
      return SessionStatus.paused;
    }
    if (statuses.isNotEmpty &&
        statuses.values.every(
          (s) => s == SessionStatus.completed || s == SessionStatus.stopped,
        )) {
      return statuses.values.any((s) => s == SessionStatus.completed)
          ? SessionStatus.completed
          : SessionStatus.stopped;
    }
    return SessionStatus.idle;
  }

  @override
  void dispose() {
    _isActive = false; // Mark as inactive before disposing
    _timer?.cancel();
    _telemetrySub?.cancel();
    _telemetrySub = null;
    _clearPlusStopTracking();
    _stopwatch.stop();
    super.dispose();
  }
}
