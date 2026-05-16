import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/storage/preferences.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/session/presentation/providers/active_sessions_provider.dart';
import 'features/session/services/background_session_runtime.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation on mobile only (not web)
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  // Initialize SharedPreferences
  final sharedPrefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPrefs),
      ],
      child: const _AppBootstrap(),
    ),
  );
}

class _AppBootstrap extends ConsumerStatefulWidget {
  const _AppBootstrap();

  @override
  ConsumerState<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<_AppBootstrap> {
  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      ref.read(authStateProvider.notifier).checkAuthStatus();
      ref.read(backgroundSessionRuntimeProvider.notifier).initialize();

      ref.listen<BackgroundSessionState>(
        backgroundSessionRuntimeProvider,
        (previous, next) {
          if (previous == null) return;
          final prevSnapshot = previous.snapshot;
          if (prevSnapshot == null) return;

          final wasLive = previous.isLive;
          final isStopped = next.status == 'stopped';

          if (wasLive && isStopped) {
            ref
                .read(activeSessionsProvider.notifier)
                .removeSession(prevSnapshot.sessionId);
          }
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const HydrawavApp();
  }
}
