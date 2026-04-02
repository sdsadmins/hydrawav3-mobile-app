import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/protocol_repository.dart';
import '../../domain/protocol_model.dart';

final protocolListProvider = FutureProvider<List<Protocol>>((ref) async {
  try {
    final repository = ref.read(protocolRepositoryProvider);
    return await repository.getProtocols();
  } catch (_) {
    // Return demo protocols when backend/DB unavailable
    return _demoProtocols;
  }
});

final protocolDetailProvider =
    FutureProvider.family<Protocol, String>((ref, id) async {
  try {
    final repository = ref.read(protocolRepositoryProvider);
    return await repository.getProtocol(id);
  } catch (_) {
    return _demoProtocols.firstWhere(
      (p) => p.id == id,
      orElse: () => _demoProtocols.first,
    );
  }
});

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
