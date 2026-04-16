import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/protocol_repository.dart';
import '../../domain/protocol_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart'; // ✅ ADD THIS

final protocolListProvider = FutureProvider<List<Protocol>>((ref) async {
  final auth = ref.watch(authStateProvider);

  final repository = ref.read(protocolRepositoryProvider);

  try {
    List<Protocol> protocols;

    if (auth.selectedOrgId != null) {
      protocols = await repository.getProtocols(
        orgId: auth.selectedOrgId!,
      );
    } else {
      protocols = await repository.getProtocols();
    }

    return _mergeBuiltIns(protocols);
  } catch (_) {
    return _mergeBuiltIns(_demoProtocols);
  }
});
final protocolDetailProvider =
    FutureProvider.family<Protocol, String>((ref, id) async {
  try {
    final repository = ref.read(protocolRepositoryProvider);

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
  final list = [...fromApiOrCache];

  if (!list.any((p) =>
      p.id == _deepSession.id ||
      p.templateName == _deepSession.templateName)) {
    list.add(_deepSession);
  }

  if (!list.any((p) =>
      p.id == _lightOn.id ||
      p.templateName == _lightOn.templateName)) {
    list.add(_lightOn);
  }

  return list;
}

Protocol? _builtInById(String id) {
  if (id == _deepSession.id) return _deepSession;
  if (id == _lightOn.id) return _lightOn;
  return null;
}

/// Built-in Protocols

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
      'HOT/COLD, RED/BLUE, VIBRATION (18 SEC SWITCH)\nGood for people with long standing discomfort.',
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

/// Demo fallback
final _demoProtocols = [
  Protocol(
    id: 'demo-1',
    templateName: 'Full Body Recovery',
    sessions: 1,
    description: 'Comprehensive recovery protocol',
    cycles: [
      const ProtocolCycle(
          hotPwm: 70,
          coldPwm: 30,
          durationSeconds: 300,
          repetitions: 3),
    ],
    hotdrop: 5,
    colddrop: 3,
    vibmin: 20,
    vibmax: 80,
  ),
];