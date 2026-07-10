import 'package:flutter/material.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../ai_report/presentation/widgets/client_reports_section.dart';
import '../widgets/client_lease_section.dart';

/// Combined client detail screen (parity with the web `clientDetails.tsx`):
/// the device-lease card on top, followed by the client's AI report history.
/// Opened when a client is tapped in the clients list.
class ClientDetailScreen extends StatelessWidget {
  final String clientId;
  final String? title;

  const ClientDetailScreen({super.key, required this.clientId, this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(
        backgroundColor: ThemeConstants.surface,
        foregroundColor: ThemeConstants.textPrimary,
        title: Text(title ?? 'Client'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Lease first.
            ClientLeaseSection(clientId: clientId),
            const SizedBox(height: 24),
            // Reports below.
            Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 2),
              child: Text(
                'AI Reports',
                style: TextStyle(
                  color: ThemeConstants.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ClientReportsSection(clientId: clientId),
          ],
        ),
      ),
    );
  }
}
