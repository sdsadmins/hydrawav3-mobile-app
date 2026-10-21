import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/utils/logger.dart';
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

  /// True while the OS owns the audio route (phone call, Siri, alarm). The
  /// therapy session keeps running throughout — only the audio is paused.
  final bool isInterrupted;

  /// True when an interruption ended but we could not get the audio route
  /// back, so the user has to resume audio by hand.
  final bool needsManualResume;

  const SessionMusicState({
    this.activeTrackId,
    this.activeTrackName,
    this.isMuted = false,
    this.isPlaying = false,
    this.isInterrupted = false,
    this.needsManualResume = false,
  });

  bool get hasTrack => activeTrackId != null;

  SessionMusicState copyWith({
    String? activeTrackId,
    String? activeTrackName,
    bool clearTrack = false,
    bool? isMuted,
    bool? isPlaying,
    bool? isInterrupted,
    bool? needsManualResume,
  }) {
    return SessionMusicState(
      activeTrackId: clearTrack ? null : (activeTrackId ?? this.activeTrackId),
      activeTrackName:
          clearTrack ? null : (activeTrackName ?? this.activeTrackName),
      isMuted: isMuted ?? this.isMuted,
      isPlaying: isPlaying ?? this.isPlaying,
      // Interruption flags are lifecycle state, not track state, so
      // `clearTrack` deliberately resets them: dropping the selection means
      // any pending "resume the audio" affordance is moot.
      isInterrupted: clearTrack ? false : (isInterrupted ?? this.isInterrupted),
      needsManualResume:
          clearTrack ? false : (needsManualResume ?? this.needsManualResume),
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

  // Latest gating condition, so mute/select can re-evaluate immediately.
  bool _sessionRunning = false;

  /// True while the OS owns the audio route. Gates [_evaluate] so nothing
  /// tries to play against a route we don't hold.
  bool _interrupted = false;

  /// Android transient-duck: play at reduced volume instead of pausing.
  bool _ducked = false;

  /// Picked on Session Setup before a session runs: plays straight away so
  /// the practitioner hears it there, and carries on into the session. Ends
  /// once the session is running (the session gate takes over, so Pause
  /// pauses it), on [stopPreview], or when the session ends.
  bool _preview = false;

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
          // Ducking means "keep playing, quieter" — never a full pause.
          // (Android-only in practice: iOS always reports `unknown` on begin.)
          if (event.type == AudioInterruptionType.duck) {
            unawaited(_duck(true));
            return;
          }
          // A call/Siri/alarm took the audio route. Pause ONLY the audio.
          // The therapy session and its BLE link deliberately keep running —
          // the `bluetooth-central` background grant keeps servicing them,
          // and the engine advances its schedule off inbound telemetry
          // frames while iOS has us suspended. Pausing the session here is
          // what used to stop the device mid-treatment.
          _interrupted = true;
          if (mounted) state = state.copyWith(isInterrupted: true);
          appLogger.i('Music: audio interrupted (session left running)');
          unawaited(_safePause());
        } else {
          if (event.type == AudioInterruptionType.duck) {
            unawaited(_duck(false));
            return;
          }
          // audio_session 0.1.x has NO `shouldResume` field — the flag is
          // encoded in `type` on the END event: `pause` => the OS says we may
          // resume, `unknown` => it does not. See audio_session 0.1.25
          // lib/src/core.dart:73-79.
          final osSaysResume = event.type == AudioInterruptionType.pause;
          _interrupted = false;
          if (mounted) state = state.copyWith(isInterrupted: false);
          unawaited(_resumeAfterInterruption(osSaysResume: osSaysResume));
        }
      });
    } catch (e) {
      appLogger.w('Music: audio session config failed (continuing): $e');
    }
    try {
      await _player.setLoopMode(LoopMode.one);
      await _applyVolume();
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

  /// Restore playback after an interruption ends.
  ///
  /// The keep-alive ambient is a background-survival lifeline, not media, so
  /// when a session is still running we attempt resume even if iOS withholds
  /// `shouldResume` — that flag is a courtesy hint about *user* media.
  /// `setActive(true)` can still fail while the call tail releases the route,
  /// so retry with a short backoff before giving up and asking the user.
  Future<void> _resumeAfterInterruption({required bool osSaysResume}) async {
    if (_disposed) return;
    if (!_sessionRunning && !osSaysResume) {
      await _evaluate();
      return;
    }
    const delays = [
      Duration.zero,
      Duration(milliseconds: 400),
      Duration(seconds: 1),
      Duration(seconds: 3),
    ];
    for (final delay in delays) {
      // A second interruption starting mid-retry wins: bail and let its own
      // end event drive the next attempt.
      if (_disposed || _interrupted) return;
      if (delay != Duration.zero) await Future<void>.delayed(delay);
      if (_disposed || _interrupted) return;
      await _evaluate();
      if (_player.playing) {
        appLogger.i('Music: resumed after interruption');
        if (mounted && state.needsManualResume) {
          state = state.copyWith(needsManualResume: false);
        }
        return;
      }
    }
    appLogger.w('Music: could not resume audio after interruption');
    if (mounted) state = state.copyWith(needsManualResume: true);
  }

  /// Android transient-duck: keep playing at a reduced volume rather than
  /// pausing outright.
  Future<void> _duck(bool ducked) async {
    if (_disposed) return;
    _ducked = ducked;
    await _applyVolume();
  }

  /// Choose (or switch to) a track. Loads its URL and starts playing if the
  /// session conditions allow it. With [preview] (Session Setup, no session
  /// running yet) it plays right away instead of waiting for Start.
  Future<void> selectTrack(Music track, {bool preview = false}) async {
    if (_disposed || !track.isPlayable) return;
    if (preview && !_sessionRunning) _preview = true;
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
        await _applyVolume();
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
    _preview = false;
    if (mounted) state = state.copyWith(clearTrack: true, isPlaying: false);
    _loadedUrl = null;
    await _safeStop();
    await _evaluate();
  }

  /// Mute keeps the track "running" but silent (volume 0), mirroring the web.
  /// Deliberately does NOT pause — the audio session (and with it the iOS
  /// background grant) must stay active. See the class doc.
  Future<void> toggleMute() async {
    if (_disposed || !mounted) return;
    state = state.copyWith(isMuted: !state.isMuted);
    await _applyVolume();
  }

  /// The single source of truth for player volume. The keep-alive ambient
  /// plays quieter than a user-selected track; ducking scales whichever
  /// applies.
  double get _targetVolume {
    if (state.isMuted) return 0;
    final base = _loadedUrl == _kFallbackTrackKey ? 0.35 : 1.0;
    return _ducked ? base * 0.3 : base;
  }

  Future<void> _applyVolume() async {
    try {
      await _player.setVolume(_targetVolume);
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
    // The session is running: it owns playback from here on (a later Pause
    // pauses the music). Before that — the session screen's idle start — a
    // Setup preview keeps playing so there's no gap.
    if (sessionRunning) _preview = false;
    await _ensureReady();
    await _evaluate();
  }

  /// Leaving Session Setup without starting: stop the preview. The track
  /// stays selected, so it plays when a session does start.
  Future<void> stopPreview() async {
    if (_disposed || !_preview || _sessionRunning) return;
    _preview = false;
    await _evaluate();
  }

  /// Stop everything and drop the selection â€” used when the session ends or the
  /// session screen is left (music must never outlive the session).
  Future<void> stopAndReset() async {
    if (_disposed) return;
    _sessionRunning = false;
    _preview = false;
    if (mounted) state = state.copyWith(clearTrack: true, isPlaying: false);
    _loadedUrl = null;
    await _safeStop();
  }

  bool get _shouldPlay =>
      state.activeTrackId != null &&
      _loadedUrl != null &&
      (_sessionRunning || _preview);

  /// iOS-only keep-alive: a session is running but the user hasn't picked an
  /// Atmosphere track, so there's nothing else holding audio focus.
  bool get _shouldPlayFallback =>
      Platform.isIOS && _sessionRunning && state.activeTrackId == null;

  Future<void> _evaluate() async {
    if (_disposed) return;
    // The OS owns the route mid-interruption — don't fight it. A selectTrack
    // or applyConditions arriving during a call lands here.
    if (_interrupted) {
      await _safePause();
      return;
    }
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
        await _applyVolume();
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
