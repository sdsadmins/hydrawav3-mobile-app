// [FIX-23] SessionEngine.applyIndividualPercent — per-cycle PWM scaling.
//
// `new = base × (1 + percent / 100)`, clamped to [0, maxPwm]. 0% must be the
// identity for every non-zero base, and a base of 0 must stay 0 at any percent
// (lib/features/session/services/session_engine.dart, applyIndividualPercent).

import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/session/services/session_engine.dart';

void main() {
  group('[FIX-23] applyIndividualPercent', () {
    test('[FIX-23] 0% leaves every non-zero base unchanged', () {
      for (final base in [1.0, 7.0, 42.0, 99.0, 100.0, 250.0]) {
        expect(
          SessionEngine.applyIndividualPercent(
            base,
            0,
            SessionEngine.kMaxColdPwm,
          ),
          base.round(),
          reason: 'base $base at 0% must be identity',
        );
      }
      // Hot ceiling too, not just cold.
      expect(
        SessionEngine.applyIndividualPercent(60, 0, SessionEngine.kMaxHotPwm),
        60,
      );
    });

    test('[FIX-23] a base of 0 stays 0 at any percent', () {
      for (final percent in [-100.0, -50.0, 0.0, 25.0, 100.0, 400.0]) {
        expect(
          SessionEngine.applyIndividualPercent(
            0,
            percent,
            SessionEngine.kMaxColdPwm,
          ),
          0,
          reason: 'base 0 at $percent% must stay 0',
        );
      }
    });

    test('[FIX-23] scales by the percent and clamps to the hardware ceiling',
        () {
      expect(
        SessionEngine.applyIndividualPercent(50, 50, SessionEngine.kMaxHotPwm),
        75,
      );
      expect(
        SessionEngine.applyIndividualPercent(50, -50, SessionEngine.kMaxHotPwm),
        25,
      );
      // Over the ceiling clamps, never exceeds.
      expect(
        SessionEngine.applyIndividualPercent(90, 50, SessionEngine.kMaxHotPwm),
        SessionEngine.kMaxHotPwm,
      );
      // Below 0 clamps to 0.
      expect(
        SessionEngine.applyIndividualPercent(
          40,
          -150,
          SessionEngine.kMaxColdPwm,
        ),
        0,
      );
    });
  });
}
