// [FIX-14] Protocol.totalDurationSeconds
// (lib/features/protocols/domain/protocol_model.dart).
//
// The cycle-based total must include each cycle's `pause_seconds` between
// repetitions and the real edge cycles (cycle1 lead-in = edge + 30s; cycle5
// finish = sessionPause + edge). When the backend supplies `totalDuration`
// (Protocol Plus / goal-tag list entries, which carry no cycles) that value is
// used — a protocol with a server total must never read 0.

import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/protocols/domain/protocol_model.dart';

void main() {
  group('[FIX-14] totalDurationSeconds', () {
    // 3 cycles, each 2 reps × 100s with a 10s pause between reps and a 5s
    // cycle pause after cycles 1 and 2:
    //   per cycle: 2×100 + (2-1)×10 = 210; plus 5 after c1 and c2 → 630 + 10
    const cycles = [
      ProtocolCycle(
        durationSeconds: 100,
        repetitions: 2,
        pauseSeconds: 10,
        cyclePause: 5,
      ),
      ProtocolCycle(
        durationSeconds: 100,
        repetitions: 2,
        pauseSeconds: 10,
        cyclePause: 5,
      ),
      ProtocolCycle(
        durationSeconds: 100,
        repetitions: 2,
        pauseSeconds: 10,
        cyclePause: 5, // the last cycle's cyclePause is not added
      ),
    ];
    const oneSession = 3 * 210 + 2 * 5; // 640

    test('[FIX-14] includes pause_seconds between repetitions', () {
      const withPause = Protocol(
        id: 'p',
        templateName: 'With pause',
        cycles: cycles,
      );
      expect(withPause.totalDurationSeconds, oneSession);

      // Same cycles without the rep pause: exactly 3 × 10s shorter.
      final noPause = Protocol(
        id: 'p',
        templateName: 'No pause',
        cycles: [
          for (final c in cycles)
            ProtocolCycle(
              durationSeconds: c.durationSeconds,
              repetitions: c.repetitions,
              pauseSeconds: 0,
              cyclePause: c.cyclePause,
            ),
        ],
      );
      expect(noPause.totalDurationSeconds, oneSession - 3 * 10);
    });

    test('[FIX-14] adds the real edge cycles, not a fixed 30s', () {
      const edge = 45.0;
      const pause = 20.0;

      const lead = Protocol(
        id: 'p',
        templateName: 'cycle1',
        cycles: cycles,
        cycle1: true,
        edgecycleduration: edge,
        sessionPause: pause,
      );
      // Lead-in edge cycle = edge + 30.
      expect(lead.totalDurationSeconds, oneSession + edge.toInt() + 30);

      const finish = Protocol(
        id: 'p',
        templateName: 'cycle5',
        cycles: cycles,
        cycle5: true,
        edgecycleduration: edge,
        sessionPause: pause,
      );
      // Finish edge cycle = this protocol's sessionPause + edge.
      expect(
        finish.totalDurationSeconds,
        oneSession + pause.toInt() + edge.toInt(),
      );

      const both = Protocol(
        id: 'p',
        templateName: 'both',
        cycles: cycles,
        cycle1: true,
        cycle5: true,
        edgecycleduration: edge,
        sessionPause: pause,
        sessions: 2,
      );
      // Two sessions with one session pause between them, plus both edges.
      expect(
        both.totalDurationSeconds,
        2 * oneSession +
            pause.toInt() +
            (edge.toInt() + 30) +
            (pause.toInt() + edge.toInt()),
      );
    });

    test('[FIX-14] uses apiTotalDurationSeconds when present — never 0', () {
      // Protocol Plus / goal-tag entries: no cycles, server total 1730.
      const plus = Protocol(
        id: 'pp',
        templateName: 'Protocol Plus',
        isProtocolPlus: true,
        apiTotalDurationSeconds: 1730,
      );
      expect(plus.totalDurationSeconds, 1730);
      expect(plus.totalDuration, const Duration(seconds: 1730));

      // Parsed from the backend `totalDuration` field.
      final parsed = Protocol.fromJson({
        '_id': 'pp',
        'template_name': 'Protocol Plus',
        'protocolPlus': true,
        'totalDuration': 1730,
      });
      expect(parsed.apiTotalDurationSeconds, 1730);
      expect(parsed.totalDurationSeconds, 1730);

      // Fewer than 3 cycles can't be computed — still falls back to the
      // server total rather than 0.
      const partial = Protocol(
        id: 'p',
        templateName: 'partial',
        cycles: [ProtocolCycle(durationSeconds: 60)],
        apiTotalDurationSeconds: 1730,
      );
      expect(partial.totalDurationSeconds, 1730);

      // Only with no cycles AND no server total is 0 acceptable.
      const empty = Protocol(id: 'e', templateName: 'empty');
      expect(empty.totalDurationSeconds, 0);
    });
  });
}
