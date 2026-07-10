import 'package:flutter/material.dart';

import '../../../../core/constants/theme_constants.dart';
import '../widgets/client_lease_section.dart';

/// Standalone device-lease screen for a single client. The lease UI + BLE/API
/// handshake now lives in [ClientLeaseSection] (shared with the combined client
/// detail screen); this screen just wraps it in a Scaffold + AppBar.
class ClientLeaseScreen extends StatelessWidget {
  final String clientId;
  final String? title;

  const ClientLeaseScreen({super.key, required this.clientId, this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(
        backgroundColor: ThemeConstants.surface,
        foregroundColor: ThemeConstants.textPrimary,
        title: Text(title ?? 'Device Lease'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          ClientLeaseSection(clientId: clientId),
        ],
      ),
    );
  }
}
