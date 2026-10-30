import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../clients/presentation/providers/client_providers.dart';
import '../../../history/data/history_repository.dart';
import '../../../protocols/domain/protocol_model.dart';
import '../../../protocols/presentation/providers/protocol_provider.dart';
import 'session_plan_widgets.dart';

/// "Continue with Deep-Tension Recovery": when the selected client has run a
/// protocol before, one tap puts that same protocol on every switched-on
/// unit — the way to pick up where their last session left off.
///
/// Server history stores the protocol's NAME, so it's matched back to a
/// protocol the org can run (and has unlocked) by name. Hidden when there's
/// no client, no history, no match, or every unit already runs it.
class ContinueLastProtocol extends ConsumerStatefulWidget {
  /// The units that will run (Use on, connected, free).
  final List<String> unitIds;

  /// What each unit is set to now.
  final Map<String, String> protocolIdByUnit;

  /// Puts a protocol on one unit (the unit picker's own path).
  final Future<bool> Function(String unitId, String protocolId) onApply;

  const ContinueLastProtocol({
    super.key,
    required this.unitIds,
    required this.protocolIdByUnit,
    required this.onApply,
  });

  @override
  ConsumerState<ContinueLastProtocol> createState() =>
      _ContinueLastProtocolState();
}

class _ContinueLastProtocolState extends ConsumerState<ContinueLastProtocol> {
  bool _busy = false;

  static String _norm(String s) => s.trim().toLowerCase();

  static String _when(DateTime at) {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day)
        .difference(DateTime(at.year, at.month, at.day))
        .inDays;
    if (d <= 0) return 'Today';
    if (d == 1) return 'Yesterday';
    if (d < 7) return DateFormat('EEEE').format(at);
    return DateFormat('MMM d').format(at);
  }

  Future<void> _apply(ProtocolSelectionOption option) async {
    if (_busy) return;
    setState(() => _busy = true);
    var done = 0;
    for (final id in widget.unitIds) {
      if (await widget.onApply(id, option.id)) done++;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(
            'Set ${option.templateName} on $done unit${done == 1 ? '' : 's'}'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(selectedClientProvider);
    final mode = ref.watch(sessionClientModeProvider);
    if (client == null || mode != ClientMode.client || widget.unitIds.isEmpty) {
      return const SizedBox.shrink();
    }
    final history = ref.watch(clientHistoryProvider(client.id)).valueOrNull;
    final last = history
        ?.where((s) => s.protocols.any((p) => (p.protocol ?? '').isNotEmpty))
        .firstOrNull;
    final name = last?.protocols
        .map((p) => p.protocol ?? '')
        .firstWhere((n) => n.isNotEmpty, orElse: () => '');
    if (last == null || name == null || name.isEmpty) {
      return const SizedBox.shrink();
    }
    final options =
        ref.watch(protocolSelectionOptionsProvider(null)).valueOrNull;
    final option = options
        ?.where((o) => o.active && _norm(o.templateName) == _norm(name))
        .firstOrNull;
    if (option == null) return const SizedBox.shrink();
    // nothing to do when every unit already runs it
    if (widget.unitIds
        .every((id) => widget.protocolIdByUnit[id] == option.id)) {
      return const SizedBox.shrink();
    }

    final dark = PlanTones.dark(context);
    final first = client.displayName.split(RegExp(r'\s+')).first;
    final n = widget.unitIds.length;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        button: true,
        label: 'Continue with ${option.templateName} on $n units',
        child: PlanPress(
          onTap: _busy ? null : () => _apply(option),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
            decoration: BoxDecoration(
              color: dark
                  ? const Color.fromRGBO(198, 158, 131, .1)
                  : const Color(0xFFFBF5EE),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: dark
                    ? const Color.fromRGBO(192, 157, 132, .35)
                    : const Color.fromRGBO(198, 158, 131, .6),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFDEB393), Color(0xFFB27D5C)],
                    ),
                  ),
                  child: _busy
                      ? const Padding(
                          padding: EdgeInsets.all(9),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF2B1D12)),
                        )
                      : const Icon(Icons.replay_rounded,
                          size: 18, color: Color(0xFF2B1D12)),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Continue with ${option.templateName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: dark
                              ? const Color(0xFFF1E4D6)
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "$first's last session · ${_when(last.createdAt ?? DateTime.now())}"
                        ' · on $n unit${n == 1 ? '' : 's'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: PlanTones.sub(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: PlanTones.sub(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
