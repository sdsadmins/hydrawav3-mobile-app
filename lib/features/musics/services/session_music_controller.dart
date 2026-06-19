import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/utils/logger.dart';
import '../domain/music_model.dart';

/// UI-facing state of the session "Atmosphere" music.
class SessionMusicState {
  final String? activeTrackId;
  final String? activeTrackName;
  final bool isMuted;

  /// True when the player is actually producing (audible) playback.
  final bool isPlaying;

  const SessionMusicState({
    this.activeTrackId,
    this.activeTrackName,
    this.isMuted = false,
    this.isPlaying = false,
  });

  bool get hasTrack => activeTrackId != null;

  SessionMusicState copyWith({
    String? activeTrackId,
    String? activeTrackName,
    bool clearTrack = false,
    bool? isMuted,
    bool? isPlaying,
  }) {
    return SessionMusicState(
      activeTrackId: clearTrack ? null : (activeTrackId ?? this.activeTrackId),
      activeTrackName:
          clearTrack ? null : (activeTrackName ?? this.activeTrackName),
      isMuted: isMuted ?? this.isMuted,
      isPlaying: isPlaying ?? this.isPlaying,
    );
  }
}

/// One app-scoped controller that owns the single [AudioPlayer]. Plays a looping
/// "Atmosphere" track during a live session, gated on the session being running
/// and the app being foreground (foreground-only by design — see plan).
///
/// EVERY audio operation is wrapped so a device/OEM audio quirk can never crash
/// or stall a session: failures are logged and swallowed, and the session
/// engine / timer / BLE never depend on this.
final sessionMusicControllerProvider =
    StateNotifierProvider<SessionMusicController, SessionMusicState>((ref) {
  final controller = SessionMusicController();
  ref.onDispose(controller.shutdown);
  return controller;
});

class SessionMusicController extends StateNotifier<SessionMusicState> {
  SessionMusicController() : super(const SessionMusicState());

  final AudioPlayer _player = AudioPlayer();

  bool _disposed = false;
  bool _sessionConfigured = false;
  String? _loadedUrl;

  // Latest gating conditions, so mute/select can re-evaluate immediately.
  bool _sessionRunning = false;
  bool _appForeground = true;

  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<bool>? _playingSub;

  /// One-time audio-session + player setup. Configures the iOS category to
  /// `music`/playback so audio is audible through the silent switch, and wires
  /// interruption (calls/Siri) handling. Best-effort: failures don't block.
  Future<void> _ensureReady() async {
    if (_sessionConfigured || _disposed) return;
    _sessionConfigured = true; // set first so we don't re-enter on failure
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _interruptionSub = session.interruptionEventStream.listen((event) {
        if (_disposed) return;
        if (event.begin) {
          unawaited(_safePause());
        } else {
          unawaited(_evaluate()); // resume only if conditions still hold
        }
      });
    } catch (e) {
      appLogger.w('Music: audio session config failed (continuing): $e');
    }
    try {
      await _player.setLoopMode(LoopMode.one);
      await _player.setVolume(state.isMuted ? 0 : 1);
    } catch (e) {
      appLogger.w('Music: player init failed (continuing): $e');
    }
    _playingSub ??= _player.playingStream.listen((playing) {
      if (_disposed || !mounted) return;
      if (state.isPlaying != playing) {
        state = state.copyWith(isPlaying: playing);
      }
    });
  }

  /// Choose (or switch to) a track. Loads its URL and starts playing if the
  /// session conditions allow it.
  Future<void> selectTrack(Music track) async {
    if (_disposed || !track.isPlayable) return;
    await _ensureReady();
    if (_disposed || !mounted) return;
    state = state.copyWith(
      activeTrackId: track.id,
      activeTrackName: track.name,
    );
    try {
      if (_loadedUrl != track.url) {
        await _player.setUrl(track.url);
        _loadedUrl = track.url;
        await _player.setVolume(state.isMuted ? 0 : 1);
      }
    } catch (e) {
      appLogger.w('Music: failed to load "${track.name}" (ignored): $e');
    }
    await _evaluate();
  }

  /// Deselect the current track and stop playback.
  Future<void> clear() async {
    if (_disposed) return;
    if (mounted) state = state.copyWith(clearTrack: true, isPlaying: false);
    _loadedUrl = null;
    await _safeStop();
  }

  /// Mute keeps the track "running" but silent (volume 0), mirroring the web.
  Future<void> toggleMute() async {
    if (_disposed || !mounted) return;
    final muted = !state.isMuted;
    state = state.copyWith(isMuted: muted);
    try {
      await _player.setVolume(muted ? 0 : 1);
    } catch (e) {
      appLogger.w('Music: setVolume failed (ignored): $e');
    }
  }

  /// Update the play/pause gate from the session + app state. Called from the
  /// session screen on every status change and app-lifecycle transition.
  Future<void> applyConditions({
    required bool sessionRunning,
    required bool appForeground,
  }) async {
    _sessionRunning = sessionRunning;
    _appForeground = appForeground;
    await _evaluate();
  }

  /// Stop everything and drop the selection — used when the session ends or the
  /// session screen is left (music must never outlive the session).
  Future<void> stopAndReset() async {
    if (_disposed) return;
    _sessionRunning = false;
    if (mounted) state = state.copyWith(clearTrack: true, isPlaying: false);
    _loadedUrl = null;
    await _safeStop();
  }

  bool get _shouldPlay =>
      state.activeTrackId != null &&
      _loadedUrl != null &&
      _sessionRunning &&
      _appForeground;

  Future<void> _evaluate() async {
    if (_disposed) return;
    if (_shouldPlay) {
      await _safePlay();
    } else {
      await _safePause();
    }
  }

  Future<void> _safePlay() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (_) {
      // Activation failure shouldn't stop us from attempting playback.
    }
    try {
      if (!_player.playing) {
        // play() completes only when playback ends; with LoopMode.one it never
        // does, so fire-and-forget instead of awaiting.
        unawaited(_player.play());
      }
    } catch (e) {
      appLogger.w('Music: play failed (ignored): $e');
    }
  }

  Future<void> _safePause() async {
    try {
      if (_player.playing) await _player.pause();
    } catch (e) {
      appLogger.w('Music: pause failed (ignored): $e');
    }
  }

  Future<void> _safeStop() async {
    try {
      await _player.stop();
    } catch (e) {
      appLogger.w('Music: stop failed (ignored): $e');
    }
  }

  Future<void> shutdown() async {
    _disposed = true;
    await _interruptionSub?.cancel();
    await _playingSub?.cancel();
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
