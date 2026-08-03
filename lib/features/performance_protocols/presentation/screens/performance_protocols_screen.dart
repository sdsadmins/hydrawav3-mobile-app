import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../data/performance_remote_source.dart';
import '../../domain/performance_models.dart';
import '../providers/performance_catalog_providers.dart';
import '../providers/performance_session_provider.dart';
import 'pad_map_screen.dart';

/// Way in A, for browsing: discipline → role → chain as dependent selects, plus
/// a search box that runs the ranked query. Both land on the same pad map as the
/// Assistant's chip flow.
///
/// Dropdown values bind to `discipline` (the match key) while the labels show
/// `display_name` — the key is "track", the label "Track & Field", and binding
/// the label breaks matching.
class PerformanceProtocolsScreen extends ConsumerStatefulWidget {
  const PerformanceProtocolsScreen({super.key});

  @override
  ConsumerState<PerformanceProtocolsScreen> createState() =>
      _PerformanceProtocolsScreenState();
}

class _PerformanceProtocolsScreenState
    extends ConsumerState<PerformanceProtocolsScreen> {
  String? _discipline;
  String? _role;
  String? _subtype;
  String? _chainId;

  final _search = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Ranked query hits — these carry scores, unlike the chain menu.
  List<RankedChain> _matches = const [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final disciplines = ref.watch(disciplinesProvider);

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              HwSpace.s4, 0, HwSpace.s4, HwSpace.s6),
          children: [
            HwBackBar(
              title: 'Protocol chains',
              subtitle: 'Pick a discipline and position, or ask a question',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            const HwEyebrow('Browse the catalogue'),
            HwCard(
              child: disciplines.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: HwSpace.s5),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => _retry(
                  p,
                  'Couldn’t load disciplines. ${_reason(e)}',
                  () => ref.invalidate(disciplinesProvider),
                ),
                data: (list) => _selects(p, list),
              ),
            ),
            const SizedBox(height: HwSpace.s5),
            const HwEyebrow('Or ask'),
            HwCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HwField(
                    label: 'Your question',
                    controller: _search,
                    hint: 'how do i avoid elbow injury',
                  ),
                  HwButton(
                    label: 'Search chains',
                    filled: false,
                    busy: _busy,
                    onTap: _busy ? null : _runQuery,
                  ),
                  if (_matches.isNotEmpty) ...[
                    const SizedBox(height: HwSpace.s4),
                    // Honest ranking language: query results are scored.
                    Text(
                      'Best matches',
                      style: TextStyle(
                        fontSize: HwType.cap,
                        fontWeight: FontWeight.w800,
                        color: p.ink2,
                      ),
                    ),
                    const SizedBox(height: HwSpace.s2),
                    for (final m in _matches) _matchRow(p, m),
                  ],
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: HwSpace.s4),
              Container(
                padding: const EdgeInsets.all(HwSpace.s3),
                decoration: BoxDecoration(
                  color: p.midSoft,
                  borderRadius: BorderRadius.circular(HwRadius.lg),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                      fontSize: HwType.cap, color: p.mid, height: 1.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── the three selects ──────────────────────────────────────────────────────

  Widget _selects(RefPalette p, List<Discipline> disciplines) {
    final roles = _discipline == null
        ? const AsyncValue<List<RoleOption>>.data([])
        : ref.watch(rolesProvider(_discipline!));
    final chains = (_discipline == null || _role == null)
        ? const AsyncValue<List<ChainSummary>>.data([])
        : ref.watch(chainsProvider(
            ChainsQuery(_discipline!, _role!, subtype: _subtype)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _select<Discipline>(
          p,
          label: 'Discipline',
          hint: 'Select a discipline',
          value: disciplines
              .where((d) => d.discipline == _discipline)
              .cast<Discipline?>()
              .firstWhere((_) => true, orElse: () => null),
          items: disciplines,
          labelOf: (d) => d.label,
          onChanged: (d) => setState(() {
            _discipline = d?.discipline;
            _role = null;
            _subtype = null;
            _chainId = null;
          }),
        ),
        _asyncSelect<RoleOption>(
          p,
          label: 'Position',
          hint: _discipline == null
              ? 'Pick a discipline first'
              : 'Select a position',
          enabled: _discipline != null,
          async: roles,
          value: (list) => list
              .where((r) => r.role == _role)
              .cast<RoleOption?>()
              .firstWhere((_) => true, orElse: () => null),
          labelOf: (r) => r.label,
          onChanged: (r) => setState(() {
            _role = r?.role;
            _subtype = r?.subtype;
            _chainId = null;
          }),
          onRetry: () => ref.invalidate(rolesProvider(_discipline!)),
        ),
        _asyncSelect<ChainSummary>(
          p,
          label: 'Chain',
          hint: _role == null ? 'Pick a position first' : 'Select a chain',
          enabled: _role != null,
          async: chains,
          value: (list) => list
              .where((c) => c.chainId == _chainId)
              .cast<ChainSummary?>()
              .firstWhere((_) => true, orElse: () => null),
          labelOf: (c) => c.label,
          onChanged: (c) => setState(() => _chainId = c?.chainId),
          onRetry: () => ref.invalidate(chainsProvider(
              ChainsQuery(_discipline!, _role!, subtype: _subtype))),
        ),
        const SizedBox(height: HwSpace.s2),
        HwButton(
          label: 'Show pad set',
          busy: _busy,
          onTap: (_chainId == null || _busy) ? null : _showPadSet,
        ),
      ],
    );
  }

  Widget _select<T>(
    RefPalette p, {
    required String label,
    required String hint,
    required T? value,
    required List<T> items,
    required String Function(T) labelOf,
    required ValueChanged<T?> onChanged,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: HwType.cap,
              fontWeight: FontWeight.w700,
              color: enabled ? p.ink2 : p.ink3,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: p.card2,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: p.line, width: 1.5),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                hint: Text(
                  hint,
                  style: TextStyle(fontSize: HwType.base, color: p.ink3),
                ),
                icon: Icon(Icons.expand_more_rounded, color: p.ink3),
                dropdownColor: p.card,
                borderRadius: BorderRadius.circular(HwRadius.md),
                style: TextStyle(fontSize: HwType.base, color: p.ink),
                items: [
                  for (final item in items)
                    DropdownMenuItem<T>(
                      value: item,
                      child: Text(labelOf(item), overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: enabled && items.isNotEmpty ? onChanged : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _asyncSelect<T>(
    RefPalette p, {
    required String label,
    required String hint,
    required bool enabled,
    required AsyncValue<List<T>> async,
    required T? Function(List<T>) value,
    required String Function(T) labelOf,
    required ValueChanged<T?> onChanged,
    required VoidCallback onRetry,
  }) {
    return async.when(
      loading: () => _select<T>(
        p,
        label: label,
        hint: 'Loading…',
        value: null,
        items: const [],
        labelOf: labelOf,
        onChanged: onChanged,
        enabled: false,
      ),
      error: (e, _) =>
          _retry(p, 'Couldn’t load ${label.toLowerCase()}s. ${_reason(e)}',
              onRetry),
      data: (list) => _select<T>(
        p,
        label: label,
        hint: enabled && list.isEmpty ? 'Nothing authored yet' : hint,
        value: value(list),
        items: list,
        labelOf: labelOf,
        onChanged: onChanged,
        enabled: enabled,
      ),
    );
  }

  /// The server's own words. Without them "couldn't load" gives the practitioner
  /// nothing to act on — a wrong base URL and a timeout read identically.
  static String _reason(Object error) =>
      error is ServerException ? error.message : error.toString();

  Widget _retry(RefPalette p, String message, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HwSpace.s2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: HwType.cap, color: p.ink2),
            ),
          ),
          TextButton(
            onPressed: onTap,
            child: Text(
              'Retry',
              style: TextStyle(
                fontSize: HwType.cap,
                fontWeight: FontWeight.w700,
                color: p.copperInk,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _matchRow(RefPalette p, RankedChain match) {
    final chain = match.payload.chain;
    return Padding(
      padding: const EdgeInsets.only(bottom: HwSpace.s2),
      child: HwRow(
        title: chain?.name ?? 'Chain',
        subtitle: [
          match.payload.contextLine,
          if (chain != null && chain.movement.trim().isNotEmpty) chain.movement,
        ].where((s) => s.trim().isNotEmpty).join(' · '),
        onTap: () => _openPadMap(match.payload),
      ),
    );
  }

  // ── calls ──────────────────────────────────────────────────────────────────

  Future<void> _showPadSet() async {
    final discipline = _discipline;
    final role = _role;
    final chainId = _chainId;
    if (discipline == null || role == null || chainId == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final payload = await ref.read(performanceRemoteSourceProvider).chain(
            discipline: discipline,
            role: role,
            chainId: chainId,
            subtype: _subtype,
            sessionId: ref.read(performanceSessionIdProvider),
          );
      if (!mounted) return;
      setState(() => _busy = false);
      // The catalogue is gated too: a block answers `chain: null`, not pads.
      if (payload.isRefusal) {
        setState(() => _error = payload.refusalMessage ??
            'I can’t bring up a placement for that right now.');
        return;
      }
      _openPadMap(payload);
    } on PerformanceRefusal catch (r) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = r.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Couldn’t load the pad set. $e';
      });
    }
  }

  Future<void> _runQuery() async {
    final text = _search.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
      _matches = const [];
    });
    try {
      final results = await ref.read(performanceRemoteSourceProvider).query(
            query: text,
            role: _role,
            subtype: _subtype,
            sessionId: ref.read(performanceSessionIdProvider),
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _matches = results;
        _error = results.isEmpty ? 'No chains matched that yet.' : null;
      });
    } on PerformanceRefusal catch (r) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = r.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Couldn’t run that search. $e';
      });
    }
  }

  void _openPadMap(PadSetPayload payload) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PadMapScreen(payload: payload),
      ),
    );
  }
}
