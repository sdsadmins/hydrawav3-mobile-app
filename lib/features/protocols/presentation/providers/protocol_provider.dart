import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/protocol_repository.dart';
import '../../domain/protocol_model.dart';

final protocolListProvider = FutureProvider<List<Protocol>>((ref) async {
  try {
    final repository = ref.read(protocolRepositoryProvider);
    final protocols = await repository.getProtocols();
    return _mergeBuiltIns(protocols);
  } catch (_) {
    // Return demo protocols when backend/DB unavailable
    return _mergeBuiltIns(_demoProtocols);
  }
});

final protocolDetailProvider =
    FutureProvider.family<Protocol, String>((ref, id) async {
  try {
    final repository = ref.read(protocolRepositoryProvider);
    // If user is asking for a built-in protocol, return it directly.
    final builtIn = _builtInById(id);
    if (builtIn != null) return builtIn;
    return await repository.getProtocol(id);
  } catch (_) {
    return _demoProtocols.firstWhere(
      (p) => p.id == id,
      orElse: () => _demoProtocols.first,
    );
  }
});

List<Protocol> _mergeBuiltIns(List<Protocol> fromApiOrCache) {
  // Always include built-ins (without duplicates).
  final list = [...fromApiOrCache];
  if (!list.any((p) => p.id == _deepSession.id || p.templateName == _deepSession.templateName)) {
    list.add(_deepSession);
  }
  if (!list.any((p) => p.id == _lightOn.id || p.templateName == _lightOn.templateName)) {
    list.add(_lightOn);
  }
  return list;
}

Protocol? _builtInById(String id) {
  if (id == _deepSession.id) return _deepSession;
  if (id == _lightOn.id) return _lightOn;
  return null;
}

/// Minimal built-in protocol used for brute-testing "turn light on".
///
/// When you press "Start Session", the app will send the session JSON which
/// includes `"led": 1` and `"playCmd": 1` (see session payload builder).
const Protocol _lightOn = Protocol(
  id: 'light-on',
  templateName: 'Light On (Debug)',
  sessions: 1,
  description:
      'Minimal debug protocol to test a working BLE command path. Sends a tiny session payload with led=1.',
  cycles: [
    ProtocolCycle(
      hotPwm: 0,
      coldPwm: 0,
      cyclePause: 0,
      repetitions: 1,
      rightFunction: '',
      pauseSeconds: 0,
      leftFunction: '',
      durationSeconds: 1,
    ),
  ],
  hotdrop: 0,
  colddrop: 0,
  vibmin: 0,
  vibmax: 0,
  cycle1: false,
  cycle5: false,
  edgecycleduration: 0,
  sessionPause: 0,
);

const Protocol _deepSession = Protocol(
  id: 'deep-session',
  templateName: 'Deep Session',
  sessions: 1,
  description:
      'HOT/COLD, RED/BLUE, VIBRATION (18 SEC SWITCH)\nGood for people with long standing discomfort. Works deep into the tissues.',
  cycles: [
    ProtocolCycle(
      hotPwm: 80,
      coldPwm: 220,
      cyclePause: 60,
      repetitions: 6,
      rightFunction: 'rightHotRed',
      pauseSeconds: 18,
      leftFunction: 'leftColdBlue',
      durationSeconds: 18,
    ),
    ProtocolCycle(
      hotPwm: 80,
      coldPwm: 220,
      cyclePause: 60,
      repetitions: 6,
      rightFunction: 'rightColdBlue',
      pauseSeconds: 18,
      leftFunction: 'leftHotRed',
      durationSeconds: 18,
    ),
    ProtocolCycle(
      hotPwm: 80,
      coldPwm: 220,
      cyclePause: 60,
      repetitions: 3,
      rightFunction: 'rightColdBlue',
      pauseSeconds: 18,
      leftFunction: 'leftColdBlue',
      durationSeconds: 18,
    ),
  ],
  hotdrop: 5,
  colddrop: 0,
  vibmin: 20,
  vibmax: 222,
  cycle1: true,
  cycle5: true,
  edgecycleduration: 9,
  sessionPause: 18,
);

final _demoProtocols = [
  Protocol(
    id: 'demo-1',
    templateName: 'Full Body Recovery',
    sessions: 1,
    description: 'Comprehensive recovery protocol targeting major muscle groups with alternating hot and cold therapy.',
    cycles: [
      const ProtocolCycle(hotPwm: 70, coldPwm: 30, durationSeconds: 300, repetitions: 3, cyclePause: 30, leftFunction: 'heat', rightFunction: 'cool'),
      const ProtocolCycle(hotPwm: 50, coldPwm: 50, durationSeconds: 180, repetitions: 2, cyclePause: 20, leftFunction: 'heat', rightFunction: 'cool'),
    ],
    hotdrop: 5,
    colddrop: 3,
    vibmin: 20,
    vibmax: 80,
  ),
  Protocol(
    id: 'demo-2',
    templateName: 'Lower Back Relief',
    sessions: 1,
    description: 'Targeted protocol for lumbar region discomfort with gentle vibration and thermal contrast.',
    cycles: [
      const ProtocolCycle(hotPwm: 60, coldPwm: 40, durationSeconds: 240, repetitions: 4, cyclePause: 15, leftFunction: 'heat', rightFunction: 'heat'),
    ],
    vibmin: 30,
    vibmax: 60,
  ),
  Protocol(
    id: 'demo-3',
    templateName: 'Neck & Shoulder',
    sessions: 2,
    description: 'Gentle protocol designed for cervical and upper trapezius areas.',
    cycles: [
      const ProtocolCycle(hotPwm: 45, coldPwm: 25, durationSeconds: 180, repetitions: 3, cyclePause: 10, leftFunction: 'heat', rightFunction: 'cool'),
      const ProtocolCycle(hotPwm: 55, coldPwm: 35, durationSeconds: 120, repetitions: 2, cyclePause: 15, leftFunction: 'heat', rightFunction: 'cool'),
    ],
    vibmin: 15,
    vibmax: 50,
    sessionPause: 60,
  ),
  Protocol(
    id: 'demo-4',
    templateName: 'Athletic Performance',
    sessions: 1,
    description: 'High-intensity contrast therapy for post-workout recovery and muscle performance optimization.',
    cycles: [
      const ProtocolCycle(hotPwm: 85, coldPwm: 70, durationSeconds: 360, repetitions: 5, cyclePause: 20, leftFunction: 'heat', rightFunction: 'cool'),
    ],
    vibmin: 40,
    vibmax: 100,
  ),
  Protocol(
    id: 'demo-5',
    templateName: 'Relaxation',
    sessions: 1,
    description: 'Gentle warming protocol with mild vibration for stress relief and general relaxation.',
    cycles: [
      const ProtocolCycle(hotPwm: 40, coldPwm: 10, durationSeconds: 600, repetitions: 1, leftFunction: 'heat', rightFunction: 'heat'),
    ],
    vibmin: 10,
    vibmax: 30,
  ),
];
