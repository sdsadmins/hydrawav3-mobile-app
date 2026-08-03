import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../clients/domain/client_model.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../protocols/domain/protocol_model.dart';
import '../../../protocols/presentation/providers/protocol_provider.dart';
import '../../domain/performance_models.dart';
import '../providers/performance_session_provider.dart';

/// The performance default in the UI spec — `startSessionFromFlow()` loads the
/// `perfActivation` stack ("Performance Activation") when a placement flow hands
/// off to the session. Matched by name, never by a hardcoded id, because the
/// template list is per-organization.
const String kPerformanceStackName = 'Performance Activation';

/// "Go to Session" — the spec's `startSessionFromFlow()`.
///
/// Sets who the session is for, pre-loads the performance protocol, remembers
/// which chain produced the placement, then lands on the device picker (the
/// mobile equivalent of the spec's `go('scr-setup')`, since a device is chosen
/// before session setup opens).
///
/// The pad-set service returns no protocol, duration, or intensity — so nothing
/// about the session is inferred from the chain.
/// [preloadProtocol] is off for a RECOVERY placement. The handoff is otherwise
/// identical — same pad set, same client, same destination — but the stack this
/// pre-loads is named "Performance Activation", and loading it off a recovery
/// placement announces a protocol nothing in that flow asked for.
Future<void> goToSessionFromPlacement(
  BuildContext context,
  WidgetRef ref, {
  required PadSetPayload payload,
  Client? client,
  String? clientName,
  bool preloadProtocol = true,
}) async {
  ref.read(activePadSetProvider.notifier).state = payload;

  if (client != null) {
    ref.read(selectedClientProvider.notifier).state = client;
    ref.read(sessionClientModeProvider.notifier).state = ClientMode.client;
  } else if (_isGuest(clientName)) {
    ref.read(sessionClientModeProvider.notifier).state = ClientMode.guest;
  }

  final protocol =
      preloadProtocol ? await _resolvePerformanceProtocol(ref) : null;
  if (protocol != null) {
    ref.read(pendingSessionProtocolProvider.notifier).state = protocol.id;
  }

  if (!context.mounted) return;
  context.goNamed(RouteNames.devices);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        protocol == null
            // Don't claim a load that didn't happen.
            ? 'Placement saved — pick your device and protocol'
            : '${protocol.templateName} loaded — pick your device & start',
      ),
    ),
  );
}

bool _isGuest(String? name) =>
    name == null || name.trim().isEmpty || name.toLowerCase() == 'guest';

/// The org's "Performance Activation" template, or null when its catalogue has
/// no match (free tiers don't get the Protocol Plus stacks).
Future<Protocol?> _resolvePerformanceProtocol(WidgetRef ref) async {
  try {
    final protocols = await ref.read(protocolListProvider.future);
    final target = kPerformanceStackName.toLowerCase();
    for (final p in protocols) {
      if (p.templateName.trim().toLowerCase() == target) return p;
    }
    // Fall back to any Protocol Plus stack whose name reads as performance prep.
    for (final p in protocols) {
      final name = p.templateName.toLowerCase();
      if (p.isProtocolPlus &&
          (name.contains('performance') || name.contains('activation'))) {
        return p;
      }
    }
  } catch (_) {
    // Offline or gated — the toast degrades and the practitioner picks manually.
  }
  return null;
}
