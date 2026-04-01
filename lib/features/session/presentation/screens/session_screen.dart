import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/theme/widgets/hw_button.dart';
import '../../../../core/utils/extensions.dart';
import '../../../protocols/presentation/providers/protocol_provider.dart';

enum SessionState { idle, running, paused, stopped, completed }

class SessionScreen extends ConsumerStatefulWidget {
  final String protocolId;
  final List<String> deviceIds;

  const SessionScreen({
    super.key,
    required this.protocolId,
    required this.deviceIds,
  });

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  SessionState _sessionState = SessionState.idle;
  Duration _elapsed = Duration.zero;
  Duration _totalDuration = const Duration(minutes: 5);
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startSession() {
    setState(() => _sessionState = SessionState.running);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _elapsed += const Duration(seconds: 1);
        if (_elapsed >= _totalDuration) {
          _completeSession();
        }
      });
    });
    // TODO: Send BLE start command to devices
  }

  void _pauseSession() {
    _timer?.cancel();
    setState(() => _sessionState = SessionState.paused);
    // TODO: Send BLE pause command
  }

  void _resumeSession() {
    setState(() => _sessionState = SessionState.running);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _elapsed += const Duration(seconds: 1);
        if (_elapsed >= _totalDuration) {
          _completeSession();
        }
      });
    });
    // TODO: Send BLE resume command
  }

  void _stopSession() {
    _timer?.cancel();
    setState(() => _sessionState = SessionState.stopped);
    // TODO: Send BLE stop command, save session
    _showCompletionDialog();
  }

  void _completeSession() {
    _timer?.cancel();
    setState(() => _sessionState = SessionState.completed);
    // TODO: Send BLE stop command, save session
    _showCompletionDialog();
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          _sessionState == SessionState.completed
              ? 'Session Complete!'
              : 'Session Stopped',
        ),
        content: Text(
          'Duration: ${_elapsed.formatted}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Duration get _remaining => _totalDuration - _elapsed;
  double get _progress =>
      _totalDuration.inSeconds > 0
          ? _elapsed.inSeconds / _totalDuration.inSeconds
          : 0;

  @override
  Widget build(BuildContext context) {
    final protocolAsync = ref.watch(protocolDetailProvider(widget.protocolId));

    // Update total duration from protocol
    protocolAsync.whenData((protocol) {
      if (_totalDuration.inSeconds != protocol.totalDurationSeconds &&
          protocol.totalDurationSeconds > 0) {
        _totalDuration = protocol.totalDuration;
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            if (_sessionState == SessionState.running ||
                _sessionState == SessionState.paused) {
              _stopSession();
            } else {
              context.pop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ThemeConstants.spacingLg),
          child: Column(
            children: [
              // Protocol name
              protocolAsync.when(
                data: (p) => Text(
                  p.templateName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: ThemeConstants.spacingSm),
              Text(
                _sessionState.name.toUpperCase(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _sessionState == SessionState.running
                          ? ThemeConstants.success
                          : _sessionState == SessionState.paused
                              ? ThemeConstants.warning
                              : ThemeConstants.textTertiary,
                      fontWeight: FontWeight.bold,
                    ),
              ),

              const Spacer(),

              // Timer display
              SizedBox(
                width: 250,
                height: 250,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 250,
                      height: 250,
                      child: CircularProgressIndicator(
                        value: _progress,
                        strokeWidth: 8,
                        backgroundColor: ThemeConstants.divider,
                        color: ThemeConstants.primaryColor,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _remaining.formatted,
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'remaining',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Control buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (_sessionState == SessionState.idle)
                    Expanded(
                      child: HwButton(
                        label: 'Start',
                        icon: Icons.play_arrow,
                        onPressed: _startSession,
                      ),
                    ),
                  if (_sessionState == SessionState.running) ...[
                    Expanded(
                      child: HwButton(
                        label: 'Pause',
                        icon: Icons.pause,
                        isOutlined: true,
                        onPressed: _pauseSession,
                      ),
                    ),
                    const SizedBox(width: ThemeConstants.spacingMd),
                    Expanded(
                      child: HwButton(
                        label: 'Stop',
                        icon: Icons.stop,
                        backgroundColor: ThemeConstants.error,
                        onPressed: _stopSession,
                      ),
                    ),
                  ],
                  if (_sessionState == SessionState.paused) ...[
                    Expanded(
                      child: HwButton(
                        label: 'Resume',
                        icon: Icons.play_arrow,
                        onPressed: _resumeSession,
                      ),
                    ),
                    const SizedBox(width: ThemeConstants.spacingMd),
                    Expanded(
                      child: HwButton(
                        label: 'Stop',
                        icon: Icons.stop,
                        backgroundColor: ThemeConstants.error,
                        onPressed: _stopSession,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: ThemeConstants.spacingLg),

              // Connected devices
              if (widget.deviceIds.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(ThemeConstants.spacingMd),
                    child: Row(
                      children: [
                        const Icon(Icons.bluetooth_connected,
                            color: ThemeConstants.bleConnected),
                        const SizedBox(width: ThemeConstants.spacingSm),
                        Text(
                          '${widget.deviceIds.length} device(s) connected',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
