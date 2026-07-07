import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../auth/presentation/providers/client_auth_provider.dart';
import '../../../ble/data/ble_repository.dart';
import '../../../intake/presentation/widgets/option_picker.dart';
import '../../../protocols/domain/protocol_model.dart';
import '../providers/client_session_controller.dart';

/// At-home client session screen — exact parity with the web `/client` page:
/// Hi {name} header + logout, then Step 1 Connect device, Step 2 body part,
/// Step 3 protocol, Step 4 discomfort + Start, and a live Running/Paused card
/// with Pause/Resume/Stop.
class ClientSessionScreen extends ConsumerStatefulWidget {
  const ClientSessionScreen({super.key});

  @override
  ConsumerState<ClientSessionScreen> createState() =>
      _ClientSessionScreenState();
}

class _ClientSessionScreenState extends ConsumerState<ClientSessionScreen> {
  String? _selectedBodyPart;
  Protocol? _selectedProtocol;
  int _painBefore = 0;

  ClientSessionController get _controller =>
      ref.read(clientSessionControllerProvider.notifier);

  String _fmtDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '—';
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  /// Clock format for the live countdown, e.g. `04:30`.
  String _fmtClock(int totalSeconds) {
    final t = totalSeconds < 0 ? 0 : totalSeconds;
    final m = t ~/ 60;
    final s = t % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _connect(String registeredMac) async {
    final device = await _pickDevice();
    if (device == null) return;
    await _controller.connect(device, expectedMac: registeredMac);
  }

  Future<void> _start() async {
    if (_selectedProtocol == null) {
      _controller.clearError();
      _snack('Choose a protocol.');
      return;
    }
    await _controller.start(_selectedProtocol!);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<BluetoothDevice?> _pickDevice() async {
    final repo = ref.read(bleRepositoryProvider);
    repo.startScan();
    final result = await showModalBottomSheet<BluetoothDevice>(
      context: context,
      backgroundColor: ThemeConstants.surface,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DevicePickerSheet(repo: repo),
    );
    await repo.stopScan();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(clientAuthProvider);
    final session = ref.watch(clientSessionControllerProvider);
    final clientName = auth.session?.clientName ?? 'there';
    final registeredMac = (auth.session?.macAddress ?? '').toString();

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _header(clientName),
            const SizedBox(height: 16),
            if (session.error != null) ...[
              _errorBanner(session.error!),
              const SizedBox(height: 12),
            ],
            _deviceCard(session, registeredMac),
            const SizedBox(height: 16),
            if (session.isLive)
              _liveCard(session)
            else ...[
              _bodyPartCard(session),
              const SizedBox(height: 16),
              _protocolCard(session),
              const SizedBox(height: 16),
              _painAndStartCard(session),
            ],
          ],
        ),
      ),
    );
  }

  // --- Header ---

  Widget _header(String clientName) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hi, $clientName 👋',
                  style: TextStyle(
                      color: ThemeConstants.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Connect your device, choose what to treat, and start your '
                'at-home session.',
                style: TextStyle(
                    color: ThemeConstants.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          // Override the app theme's full-width button min size — this button
          // sits inline in a Row, which measures it with unbounded width.
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          onPressed: () => ref.read(clientAuthProvider.notifier).logout(),
          icon: const Icon(Icons.logout_rounded, size: 16),
          label: const Text('Logout'),
        ),
      ],
    );
  }

  Widget _errorBanner(String msg) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ThemeConstants.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: ThemeConstants.error.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(Icons.error_outline_rounded,
              color: ThemeConstants.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(msg, style: TextStyle(color: ThemeConstants.error))),
        ]),
      );

  // --- Step 1: device ---

  Widget _deviceCard(ClientSessionState session, String registeredMac) {
    return _card(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: session.deviceReady
                  ? ThemeConstants.success.withValues(alpha: 0.12)
                  : ThemeConstants.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              session.deviceReady
                  ? Icons.check_circle_rounded
                  : Icons.bluetooth_rounded,
              color: session.deviceReady
                  ? ThemeConstants.success
                  : ThemeConstants.textTertiary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('1. Your Device',
                    style: TextStyle(
                        color: ThemeConstants.textPrimary,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  session.deviceReady
                      ? 'Connected · ${session.connectedMac}'
                      : registeredMac.isNotEmpty
                          ? 'Registered: $registeredMac'
                          : 'Not connected',
                  style: TextStyle(
                    color: session.deviceReady
                        ? ThemeConstants.success
                        : ThemeConstants.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (!session.isLive)
            session.deviceReady
                // Connected → offer Disconnect.
                ? OutlinedButton.icon(
                    onPressed: session.connecting
                        ? null
                        : () => _controller.disconnect(),
                    icon: const Icon(Icons.bluetooth_disabled_rounded, size: 16),
                    label: const Text('Disconnect'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ThemeConstants.error,
                      side: BorderSide(
                          color: ThemeConstants.error.withValues(alpha: 0.5)),
                      // Inline Row button: override the theme's full-width min.
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                  )
                // Not connected → offer Connect.
                : ElevatedButton.icon(
                    onPressed: session.connecting
                        ? null
                        : () => _connect(registeredMac),
                    icon: session.connecting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.bluetooth_rounded, size: 16),
                    label: Text(session.connecting ? 'Connecting…' : 'Connect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeConstants.navBackground,
                      foregroundColor: ThemeConstants.onNav,
                      // Inline Row button: override the theme's full-width min.
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                  ),
        ],
      ),
    );
  }

  // --- Step 2: body part ---

  Widget _bodyPartCard(ClientSessionState session) {
    final bodyPartsAsync = ref.watch(clientSessionBodyPartsProvider);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('2. What would you like to treat?',
              style: TextStyle(
                  color: ThemeConstants.textPrimary,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          bodyPartsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Failed to load body parts.',
                style: TextStyle(color: ThemeConstants.error, fontSize: 13)),
            data: (parts) {
              if (parts.isEmpty) {
                return Text('No body parts available.',
                    style: TextStyle(
                        color: ThemeConstants.textTertiary, fontSize: 13));
              }
              return PickerField(
                value: _selectedBodyPart,
                placeholder: 'Select a body part',
                onTap: () async {
                  final picked = await showOptionPicker<String>(
                    context,
                    title: 'Select a body part',
                    options: parts,
                    labelOf: (s) => s,
                    selected: _selectedBodyPart,
                  );
                  if (picked != null) {
                    setState(() => _selectedBodyPart = picked);
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // --- Step 3: protocol ---

  Widget _protocolCard(ClientSessionState session) {
    final protocolsAsync = ref.watch(clientSessionProtocolsProvider);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('3. Choose a protocol',
              style: TextStyle(
                  color: ThemeConstants.textPrimary,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          protocolsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Failed to load protocols.',
                style: TextStyle(color: ThemeConstants.error, fontSize: 13)),
            data: (protocols) {
              if (protocols.isEmpty) {
                return Text('No protocols available.',
                    style: TextStyle(
                        color: ThemeConstants.textTertiary, fontSize: 13));
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PickerField(
                    value: _selectedProtocol?.templateName,
                    placeholder: 'Select a protocol',
                    onTap: () async {
                      final picked = await showOptionPicker<Protocol>(
                        context,
                        title: 'Select a protocol',
                        options: protocols,
                        labelOf: (p) => p.templateName,
                        selected: _selectedProtocol,
                      );
                      if (picked != null) {
                        setState(() => _selectedProtocol = picked);
                      }
                    },
                  ),
                  if (_selectedProtocol?.description.isNotEmpty ?? false) ...[
                    const SizedBox(height: 10),
                    Text(_selectedProtocol!.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: ThemeConstants.textSecondary,
                            fontSize: 12)),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // --- Step 4: pain + start ---

  Widget _painAndStartCard(ClientSessionState session) {
    final canStart =
        session.deviceReady && _selectedBodyPart != null && _selectedProtocol != null;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('4. How is your discomfort right now?',
              style: TextStyle(
                  color: ThemeConstants.textPrimary,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _painBefore.toDouble(),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: '$_painBefore',
                  activeColor: ThemeConstants.accent,
                  onChanged: (v) => setState(() => _painBefore = v.round()),
                ),
              ),
              SizedBox(
                width: 32,
                child: Text('$_painBefore',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: ThemeConstants.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          Text('0 = none · 10 = severe',
              style: TextStyle(
                  color: ThemeConstants.textTertiary, fontSize: 11)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: (!canStart || session.starting) ? null : _start,
            style: ElevatedButton.styleFrom(
              backgroundColor: ThemeConstants.navBackground,
              foregroundColor: ThemeConstants.onNav,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            icon: session.starting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.play_arrow_rounded),
            label: Text(session.starting ? 'Starting…' : 'Start Session',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          if (!canStart) ...[
            const SizedBox(height: 8),
            Text(
              'Connect your device, pick a body part and a protocol to begin.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: ThemeConstants.textTertiary, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  // --- Live / running ---

  Widget _liveCard(ClientSessionState session) {
    final running = session.phase == ClientPhase.running;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ThemeConstants.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.monitor_heart_rounded, color: ThemeConstants.accent),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(running ? 'SESSION RUNNING' : 'SESSION PAUSED',
                    style: TextStyle(
                        color: ThemeConstants.textPrimary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (_selectedBodyPart != null) _selectedBodyPart!,
                    if (_selectedProtocol != null)
                      _selectedProtocol!.templateName,
                  ].join(' · '),
                  style: TextStyle(
                      color: ThemeConstants.textSecondary,
                      fontSize: 12),
                ),
              ],
            ),
          ]),
          const SizedBox(height: 20),
          // Circular countdown ring — same style as the practitioner session
          // screen (`_TimerRing`): progress arc + the live time in the centre.
          Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: CustomPaint(
                painter: _ClientTimerRing(
                    progress: session.progress, active: running),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _fmtClock(session.remainingSeconds),
                        style: TextStyle(
                          color: ThemeConstants.textPrimary,
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(running ? 'RUNNING' : 'PAUSED',
                          style: TextStyle(
                              color: ThemeConstants.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: _liveStat('DURATION',
                  _fmtDuration(session.totalDurationSeconds)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _liveStat('DEVICE',
                  session.connectedMac.isEmpty ? '—' : session.connectedMac),
            ),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: running ? _controller.pause : _controller.resume,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeConstants.navBackground,
                  foregroundColor: ThemeConstants.onNav,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: Icon(
                    running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                label: Text(running ? 'Pause' : 'Resume'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _controller.stop,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      ThemeConstants.error.withValues(alpha: 0.85),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.stop_rounded),
                label: const Text('Stop'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _liveStat(String label, String value) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ThemeConstants.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: ThemeConstants.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    color: ThemeConstants.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ThemeConstants.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ThemeConstants.border),
        ),
        child: child,
      );
}

/// Circular countdown ring for the live client session — same shape and colors
/// as the practitioner screen's `_TimerRing` (`accent` arc on a `border` track),
/// so it reads on the light theme card.
class _ClientTimerRing extends CustomPainter {
  final double progress;
  final bool active;
  _ClientTimerRing({required this.progress, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    final bg = Paint()
      ..color = ThemeConstants.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawCircle(center, radius, bg);
    final fg = Paint()
      ..color = ThemeConstants.accent.withValues(alpha: active ? 1 : 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -pi / 2,
        2 * pi * progress, false, fg);
  }

  @override
  bool shouldRepaint(covariant _ClientTimerRing old) =>
      progress != old.progress || active != old.active;
}

/// Bluetooth device picker sheet — streams live scan results and returns the
/// chosen device.
class _DevicePickerSheet extends StatelessWidget {
  final BleRepository repo;
  const _DevicePickerSheet({required this.repo});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select your device',
                style: TextStyle(
                    color: ThemeConstants.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              child: StreamBuilder<List<ScanResult>>(
                stream: repo.scanResults,
                initialData: repo.currentScanResults,
                builder: (context, snapshot) {
                  final results = (snapshot.data ?? const <ScanResult>[])
                      .where((r) =>
                          r.device.platformName.isNotEmpty ||
                          r.advertisementData.advName.isNotEmpty)
                      .toList();
                  if (results.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(height: 12),
                          Text('Scanning for devices…',
                              style: TextStyle(
                                  color: ThemeConstants.textSecondary)),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final r = results[i];
                      final name = r.device.platformName.isNotEmpty
                          ? r.device.platformName
                          : r.advertisementData.advName;
                      return ListTile(
                        leading: Icon(Icons.bluetooth_rounded,
                            color: ThemeConstants.accent),
                        title: Text(name,
                            style:
                                TextStyle(color: ThemeConstants.textPrimary)),
                        subtitle: Text(r.device.remoteId.str,
                            style: TextStyle(
                                color: ThemeConstants.textTertiary,
                                fontSize: 12)),
                        onTap: () => Navigator.of(context).pop(r.device),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
