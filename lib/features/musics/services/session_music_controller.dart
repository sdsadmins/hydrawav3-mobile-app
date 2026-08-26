import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/utils/logger.dart';
import '../../session/domain/active_session_model.dart' as active_session;
import '../../session/presentation/providers/active_sessions_provider.dart';
import '../../session/services/session_engine.dart';
import '../domain/music_model.dart';

/// Sentinel [_loadedUrl] value marking "the bundled iOS keep-alive ambient
/// asset is loaded", as opposed to a real user-selected track URL.
const _kFallbackTrackKey = 'asset:session_ambient_fallback';

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
/// "Atmosphere" track during a live session and keeps it alive across app
/// navigation/background while the session is running.
///
/// **iOS background keep-alive.** iOS has no foreground-service equivalent to
/// Android's — a backgrounded/locked app is suspended within seconds unless it
/// holds active audio focus (`UIBackgroundModes: audio`). That's what makes
/// Protocol Plus's socket-driven sub-protocol switching and BLE reconnect keep
/// working while the phone is locked on iOS. Rather than run a second,
/// competing [AudioPlayer] purely for that purpose, this controller falls back
/// to a bundled quiet ambient loop (`assets/audio/session_ambient.wav`) on iOS
/// whenever a session is running but the user hasn't picked an Atmosphere
/// track — see [_shouldPlay]/[_evaluate]. The existing session-screen mute
/// button covers "I don't want to hear anything": muting sets volume to 0
/// without pausing, so the audio session (and therefore the background grant)
/// stays active. Explain this in App Store Connect review notes: background
/// audio keeps protocol timing synced with a connected Bluetooth therapy
/// device during an active session.
///
/// EVERY audio operation is wrapped so a device/OEM audio quirk can never crash
/// or stall a session: failures are logged and swallowed, and the session
/// engine / timer / BLE never depend on this.
final sessionMusicControllerProvider =
    StateNotifierProvider<SessionMusicController, SessionMusicState>((ref) {
  final controller = SessionMusicController(ref);
  ref.onDispose(controller.shutdown);
  return controller;
});

class SessionMusicController extends StateNotifier<SessionMusicState> {
  SessionMusicController(this._ref) : super(const SessionMusicState());

  final Ref _ref;
  final AudioPlayer _player = AudioPlayer();

  bool _disposed = false;
  bool _sessionConfigured = false;
  String? _loadedUrl;

  // Latest gating condition, so mute/select can re-evaluate immediately.
  bool _sessionRunning = false;

  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<bool>? _playingSub;

  /// One-time audio-session + player setup. Configures the iOS category to
  /// `playback`/music so audio is audible through the silent switch, and
  /// wires interruption (calls/Siri) handling. Best-effort: failures don't
  /// block.
  ///
  /// `mixWithOthers` lets our loop keep playing underneath whatever the user
  /// already has running in Spotify/Apple Music/YouTube/etc. instead of iOS
  /// forcing an exclusive-focus interruption between the two — that
  /// interruption is exactly the kind of gap that can let iOS suspend us in
  /// the background. (A phone/FaceTime call is a different, OS-level
  /// reservation that `mixWithOthers` cannot avoid — we still pause/resume
  /// around those via the interruption stream below.)
  Future<void> _ensureReady() async {
    if (_sessionConfigured || _disposed) return;
    _sessionConfigured = true; // set first so we don't re-enter on failure
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
      ));
      _interruptionSub = session.interruptionEventStream.listen((event) {
        if (_disposed) return;
        if (event.begin) {
          unawaited(_safePause());
          if (event.type != AudioInterruptionType.duck) {
            _pauseAllLiveSessions();
          }
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

  /// iOS-only: pause every currently-running session app-wide, device
  /// included, not just whichever session screen happens to be mounted.
  /// [activeSessionsProvider] is the app-wide registry of live sessions, so
  /// this reaches every one of them regardless of which screen (if any) is
  /// on screen at the moment the call arrives. Android already survives a
  /// call via its foreground service, so it isn't at risk of the process
  /// being suspended and doesn't need this.
  void _pauseAllLiveSessions() {
    if (!Platform.isIOS) return;
    try {
      final sessions = _ref.read(activeSessionsProvider);
      for (final session in sessions) {
        if (session.status != active_session.SessionStatus.running) continue;
        appLogger.i(
          'Music: pausing session ${session.id} for a call/Siri interruption',
        );
        unawaited(
          _ref.read(sessionEngineFamilyProvider(session.id).notifier).pause(),
        );
      }
    } catch (e) {
      appLogger.w('Music: failed to pause live sessions on interruption: $e');
    }
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

  /// Deselect the current track and stop playback. If a session is still
  /// running on iOS, [_evaluate] immediately falls back to the ambient
  /// keep-alive loop rather than leaving audio focus dropped.
  Future<void> clear() async {
    if (_disposed) return;
    if (mounted) state = state.copyWith(clearTrack: true, isPlaying: false);
    _loadedUrl = null;
    await _safeStop();
    await _evaluate();
  }

  /// Mute keeps the track "running" but silent (volume 0), mirroring the web.
  Future<void> toggleMute() async {
    if (_disposed || !mounted) return;
    final muted = !state.isMuted;
    state = state.copyWith(isMuted: muted);
    final unmutedVolume = _loadedUrl == _kFallbackTrackKey ? 0.35 : 1.0;
    try {
      await _player.setVolume(muted ? 0 : unmutedVolume);
    } catch (e) {
      appLogger.w('Music: setVolume failed (ignored): $e');
    }
  }

  /// Update the play/pause gate from the session + app state. Called from the
  /// session screen on every status change and app-lifecycle transition.
  Future<void> applyConditions({
    required bool sessionRunning,
  }) async {
    _sessionRunning = sessionRunning;
    await _ensureReady();
    await _evaluate();
  }

  /// Stop everything and drop the selection â€” used when the session ends or the
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
      _sessionRunning;

  /// iOS-only keep-alive: a session is running but the user hasn't picked an
  /// Atmosphere track, so there's nothing else holding audio focus.
  bool get _shouldPlayFallback =>
      Platform.isIOS && _sessionRunning && state.activeTrackId == null;

  Future<void> _evaluate() async {
    if (_disposed) return;
    if (_shouldPlay) {
      await _safePlay();
    } else if (_shouldPlayFallback) {
      await _playFallback();
    } else {
      await _safePause();
    }
  }

  Future<void> _playFallback() async {
    try {
      if (_loadedUrl != _kFallbackTrackKey) {
        await _player.setAsset('assets/audio/session_ambient.wav');
        _loadedUrl = _kFallbackTrackKey;
        await _player.setVolume(state.isMuted ? 0 : 0.35);
      }
    } catch (e) {
      appLogger.w('Music: fallback ambient load failed (ignored): $e');
      return;
    }
    await _safePlay();
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
