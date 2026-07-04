/// Derives the payload for the 3D kinetic-chain viewer from a raw AI report,
/// mirroring the web `anatomyViewerData` memo (Hydrawav3-ai `session.tsx`
/// lines 1018-1072). Pattern A pulls `kinetic_chain_pattern_a`, Pattern B pulls
/// `kinetic_chain_pattern_b`; the same viewer renders whichever slice.
///
/// The returned map is JSON-encoded and injected into the WebView viewer's
/// `window.renderPattern(...)`.
library;

/// [pattern] is `'a'` or `'b'`.
Map<String, dynamic> buildKineticChainPayload(
  Map<String, dynamic> report,
  String pattern,
) {
  final selRaw =
      pattern == 'a' ? report['kinetic_chain_pattern_a'] : report['kinetic_chain_pattern_b'];
  final sel = selRaw is Map ? Map<String, dynamic>.from(selRaw) : <String, dynamic>{};

  final chain = _mapList(sel['primary_kinetic_chain']);
  final driver = (sel['primary_driver_region'] ?? '').toString().toLowerCase();
  final side = driver.contains('left')
      ? 'left'
      : driver.contains('right')
          ? 'right'
          : null;

  // Append a side to a muscle name when the pattern has a driver side and the
  // muscle doesn't already carry one (web `addSideToMuscle`).
  String addSide(String muscle) {
    if (side == null) return muscle;
    final l = muscle.toLowerCase();
    if (l.contains('left') || l.contains('right')) return muscle;
    return '$muscle ($side)';
  }

  final primary = [
    for (final c in chain)
      addSide((c['muscle'] ?? '').toString()),
  ].where((s) => s.trim().isNotEmpty).toList();

  final secondary = [
    for (final c in _mapList(sel['secondary_compensatory_muscles']))
      addSide((c['muscle'] ?? '').toString()),
  ].where((s) => s.trim().isNotEmpty).toList();

  final stabilizing = [
    for (final c in chain)
      if ((c['reason'] ?? '').toString().toLowerCase().contains('stabiliz'))
        addSide((c['muscle'] ?? '').toString()),
  ].where((s) => s.trim().isNotEmpty).toList();

  final spinal = [
    for (final s in _mapList(sel['primary_spinal_segments']))
      (s['segment'] ?? '').toString(),
  ].where((s) => s.trim().isNotEmpty).toList();

  return {
    'kineticChainPathway': primary,
    'primaryMuscles': primary, // web: effectivePrimary == the chain list
    'secondaryMuscles': secondary,
    'stabilizingMuscles': stabilizing,
    'spinalSegments': spinal,
    'hypothesisLabel': (sel['pattern_label'] ?? 'Pattern Analysis').toString(),
  };
}

/// Whether the given pattern slice has any renderable muscle data.
bool kineticChainPatternHasData(Map<String, dynamic> report, String pattern) {
  final payload = buildKineticChainPayload(report, pattern);
  return (payload['primaryMuscles'] as List).isNotEmpty ||
      (payload['secondaryMuscles'] as List).isNotEmpty ||
      (payload['spinalSegments'] as List).isNotEmpty;
}

List<Map<String, dynamic>> _mapList(dynamic v) {
  if (v is! List) return const [];
  return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}
