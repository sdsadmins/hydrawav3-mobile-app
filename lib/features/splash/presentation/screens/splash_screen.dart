import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while the splash must stay up (its minimum time hasn't passed yet).
/// The router keeps `/` on screen while this is true *or* the stored sign-in
/// is still being checked, then routes on as it always has.
final splashHoldProvider = StateProvider<bool>((ref) => true);

/// How long the splash shows at minimum (v6 `renderSplash`: 1.5s).
const kSplashMinimum = Duration(milliseconds: 1500);

/// v6 launch screen: the navy hero gradient, the white wordmark, the
/// "Performance-First. Recovery-Next." line and three pulsing dots. Shown at
/// app start and after Sign out.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  Timer? _hold;
  late final AnimationController _dots = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    // Arm the hold for this showing, then release it after the minimum.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(splashHoldProvider.notifier).state = true;
      _hold = Timer(kSplashMinimum, () {
        if (mounted) ref.read(splashHoldProvider.notifier).state = false;
      });
    });
    final reduce = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (!reduce) _dots.repeat();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F2B33),
      body: DecoratedBox(
        // `--hero-grad: linear-gradient(150deg,#243541,#1F2B33 55%,#192A35)`
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF243541), Color(0xFF1F2B33), Color(0xFF192A35)],
            stops: [0, .55, 1],
          ),
        ),
        child: SizedBox.expand(
          child: Semantics(
            label: 'Hydrawav3. Performance-First. Recovery-Next. Loading',
            child: ExcludeSemantics(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/White_Hydrawav3_Logo.png',
                    height: 40,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Performance-First. Recovery-Next.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      letterSpacing: .2,
                      color: Color(0xFFDDCABF),
                    ),
                  ),
                  const SizedBox(height: 28),
                  AnimatedBuilder(
                    animation: _dots,
                    builder: (context, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < 3; i++) _dot(i),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// `.typing i` — each dot brightens and lifts in turn.
  Widget _dot(int i) {
    final t = (_dots.value - i * .18) % 1.0;
    final k = t < .5 ? t * 2 : (1 - t) * 2; // 0 → 1 → 0
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.5),
      child: Transform.translate(
        offset: Offset(0, -3 * k),
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.lerp(
              const Color(0x66C69E83),
              const Color(0xFFE0B896),
              k,
            ),
          ),
        ),
      ),
    );
  }
}
