import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/session/presentation/providers/active_sessions_provider.dart';
import '../router/app_router.dart';
import '../router/route_names.dart';
import '../storage/preferences.dart';
import '../theme/hw_tokens.dart';
import 'app_config_store.dart';

/// Sits above every route (MaterialApp.builder).
///
/// Update required (server `mobile-app-config`, checked once per app start):
/// when this build is older than `latestAppVersion`, a full-screen card with
/// only an Update button covers the app — no skip. It waits until the user
/// is past the splash, and until any session running on this phone has
/// ended, so a live run is never left without its controls.
///
/// Maintenance (`maintenance.enabled`) replaces the app with its screen.
class AppConfigGate extends ConsumerStatefulWidget {
  final Widget child;
  const AppConfigGate({super.key, required this.child});

  @override
  ConsumerState<AppConfigGate> createState() => _AppConfigGateState();
}

class _AppConfigGateState extends ConsumerState<AppConfigGate> {
  bool _maintenanceCleared = false;
  bool _checking = false;
  String? _note;

  /// The router and a late config answer can change while the app below is
  /// building (the router announces a new screen mid-build), so the gate
  /// re-checks on the next frame rather than rebuilding right then.
  late final Listenable _changes;
  bool _recheckQueued = false;

  @override
  void initState() {
    super.initState();
    _changes = Listenable.merge([
      AppConfigStore.versionGate,
      ref.read(routerProvider).routerDelegate,
    ])
      ..addListener(_queueRecheck);
  }

  void _queueRecheck() {
    if (_recheckQueued) return;
    _recheckQueued = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _recheckQueued = false;
        if (mounted) setState(() {});
      })
      // A late config answer can land on an idle screen: make sure a frame
      // comes, or the card would wait for the next touch.
      ..ensureVisualUpdate();
  }

  @override
  void dispose() {
    _changes.removeListener(_queueRecheck);
    super.dispose();
  }

  Future<void> _retry() async {
    setState(() {
      _checking = true;
      _note = null;
    });
    final fresh =
        await AppConfigStore.fetch(ref.read(sharedPreferencesProvider));
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (fresh != null && !fresh.maintenance) {
        // Only the maintenance flag is lifted for this run; any new URLs are
        // saved and used from the next launch.
        _maintenanceCleared = true;
      } else {
        _note = fresh == null
            ? 'Couldn’t reach Hydrawav3. Check your connection.'
            : 'Still under maintenance. Please try again soon.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppConfigStore.current;
    if (c.maintenance && !_maintenanceCleared) {
      return _GateScreen(
        icon: Icons.construction_rounded,
        title: 'Down for maintenance',
        message: c.maintenanceMessage.trim().isNotEmpty
            ? c.maintenanceMessage.trim()
            : 'Hydrawav3 is being updated. Please try again in a few minutes.',
        action: _checking ? 'Checking…' : 'Try again',
        onAction: _checking ? null : _retry,
        footnote: _note,
      );
    }
    final sessionRunning = ref.watch(activeSessionsProvider).isNotEmpty;
    final location =
        ref.read(routerProvider).routerDelegate.currentConfiguration.uri.path;
    // Empty = the router hasn't settled on a screen yet (first frames).
    final pastSplash = location.isNotEmpty && location != RoutePaths.splash;
    final show =
        AppConfigStore.updateRequired && pastSplash && !sessionRunning;
    return Stack(
      children: [
        widget.child,
        if (show)
          Positioned.fill(
            child: _UpdateRequired(
                store: AppConfigStore.versionGate.value.storeUrl.current),
          ),
      ],
    );
  }
}

/// The no-skip update card: one Update button to the store, nothing else.
class _UpdateRequired extends StatelessWidget {
  final String store;
  const _UpdateRequired({required this.store});

  @override
  Widget build(BuildContext context) {
    final storeName = defaultTargetPlatform == TargetPlatform.iOS
        ? 'App Store'
        : 'Google Play';
    return _GateScreen(
      icon: Icons.system_update_rounded,
      title: 'Update required',
      message: 'A new version of Hydrawav3 is available. '
          'Please update to continue.',
      action: store.isEmpty ? null : 'Update',
      onAction: store.isEmpty
          ? null
          : () => launchUrl(Uri.parse(store),
              mode: LaunchMode.externalApplication),
      footnote:
          store.isEmpty ? 'Update Hydrawav3 from $storeName.' : null,
    );
  }
}

class _GateScreen extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? action;
  final VoidCallback? onAction;
  final String? footnote;

  const _GateScreen({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.onAction,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: p.tanSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 36, color: p.copperInk),
                  ),
                  const SizedBox(height: 20),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: p.ink)),
                  const SizedBox(height: 10),
                  Text(message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 15, height: 1.45, color: p.ink2)),
                  if (action != null) ...[
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      child: Opacity(
                        opacity: onAction == null ? .6 : 1,
                        child: Material(
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: Ink(
                            decoration: BoxDecoration(gradient: p.sunGrad),
                            child: InkWell(
                              onTap: onAction,
                              child: SizedBox(
                                height: 52,
                                child: Center(
                                  child: Text(action!,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF2A1A12))),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (footnote != null) ...[
                    const SizedBox(height: 14),
                    Text(footnote!,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: p.ink3)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
