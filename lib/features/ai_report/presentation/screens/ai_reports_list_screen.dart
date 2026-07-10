import 'package:flutter/material.dart';

import '../../../../core/constants/theme_constants.dart';
import '../widgets/client_reports_section.dart';

/// Paginated history of generated AI reports (parity with the web Client‑Details
/// table). The list itself lives in [ClientReportsSection] (shared with the
/// combined client detail screen); this screen just wraps it in a Scaffold.
class AiReportsListScreen extends StatelessWidget {
  /// When set, lists this client's reports (web parity: `ai-reports/all`
  /// queried by the client id). When null, falls back to the current user/org.
  final String? clientId;
  final String? title;

  const AiReportsListScreen({super.key, this.clientId, this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(
        backgroundColor: ThemeConstants.surface,
        foregroundColor: ThemeConstants.textPrimary,
        title: Text(title ?? 'AI Reports'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: ClientReportsSection(clientId: clientId),
      ),
    );
  }
}
