import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../widgets/client_reports_section.dart';

/// The AI reports list — the UI handoff's `renderReports()` (app.js:2763).
///
/// The list itself (including the Generating / Ready / Failed states and the
/// merge with in-flight generations) lives in [ClientReportsSection], which is
/// shared with the client detail screen; this screen supplies the spec's chrome:
/// a back bar carrying a `+ New report` action.
class AiReportsListScreen extends StatelessWidget {
  /// When set, lists this client's reports. When null, the current user/org.
  final String? clientId;
  final String? title;

  const AiReportsListScreen({super.key, this.clientId, this.title});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: HwSpace.s4),
              child: HwBackBar(
                title: title ?? 'AI Reports',
                subtitle: 'Kinetic-chain reports with placements & at-home plans',
                onBack: () => Navigator.of(context).maybePop(),
                // The spec's `+` in the back bar, titled "New report". There is
                // no plus in the HwIcons asset set, so this uses the Material
                // glyph inside the same 34×34 chrome the other icon buttons use.
                trailing: HwPress(
                  onTap: () => context.push(RoutePaths.guidedAssessment),
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: BorderRadius.circular(HwRadius.sm),
                      border: Border.all(color: p.line),
                    ),
                    child: Icon(Icons.add_rounded,
                        size: 18, color: p.copperInk),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    HwSpace.s4, 0, HwSpace.s4, HwSpace.s5),
                child: ClientReportsSection(clientId: clientId),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
