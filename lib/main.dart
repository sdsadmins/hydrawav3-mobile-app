import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/storage/preferences.dart';
import 'core/utils/logger.dart'; // TEMP-LOG-EXPORT
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/ble/services/auto_connect_manager.dart';
import 'features/payments/presentation/providers/token_balance_provider.dart';
import 'features/session/presentation/providers/active_sessions_provider.dart';
import 'features/session/presentation/providers/live_sessions_provider.dart';
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

  await initFileLogging(); // TEMP-LOG-EXPORT: persist logs to a file for field debugging

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
      // Start the app-wide BLE auto-connect/reconnect manager.
      ref.read(autoConnectManagerProvider);

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

      // Keep the org-wide live-session feed and token balance running while
      // authenticated with an org selected (parity with the web app). The
      // backend is the source of truth: every run creates a backend session and
      // is rendered from this feed. Restarts on org change, tears down on logout.
      void syncOrgScopedFeeds(AuthState auth) {
        final live = ref.read(liveSessionsProvider.notifier);
        final balance = ref.read(tokenBalanceProvider.notifier);
        final orgId = auth.selectedOrgId;
        if (auth.isAuthenticated && orgId != null && orgId.isNotEmpty) {
          live.start(orgId);
          balance.start(orgId);
        } else if (!auth.isAuthenticated) {
          live.stop();
          balance.stop();
        }
      }

      ref.listen<AuthState>(
        authStateProvider,
        (previous, next) => syncOrgScopedFeeds(next),
      );
      // Cover the case where auth is already resolved before this listener wires.
      syncOrgScopedFeeds(ref.read(authStateProvider));
    });
  }

  @override
  Widget build(BuildContext context) {
    return const HydrawavApp();
  }
}
