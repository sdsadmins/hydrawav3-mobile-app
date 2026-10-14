import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../storage/preferences.dart';
import '../theme/hw_tokens.dart';
import 'app_config_store.dart';

/// Sits above every route (MaterialApp.builder). When the server's
/// `mobile-app-config` says this build is below `minAppVersion`, or
/// `maintenance.enabled` is on, it covers the app with the matching screen.
/// Both come from the config loaded at launch, so neither can appear in the
/// middle of a running session.
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
    if (AppConfigStore.updateRequired) {
      final store = c.storeUrl.current;
      return _GateScreen(
        icon: Icons.system_update_rounded,
        title: 'Update required',
        message: 'This version of Hydrawav3 is no longer supported. '
            'Please update to continue.',
        action: store.isEmpty ? null : 'Update',
        onAction: store.isEmpty
            ? null
            : () => launchUrl(Uri.parse(store),
                mode: LaunchMode.externalApplication),
        footnote: store.isEmpty
            ? 'Update Hydrawav3 from the '
                '${defaultTargetPlatform == TargetPlatform.iOS ? 'App Store' : 'Google Play'}.'
            : null,
      );
    }
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
    return widget.child;
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
