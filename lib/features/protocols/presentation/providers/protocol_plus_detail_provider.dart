import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../session/services/protocol_plus_controller.dart';
import '../../domain/protocol_plus_model.dart';

/// Fetches a Protocol Plus template with its sub-protocols POPULATED (each with
/// cycles + sessions), cached per id. The list / by-id endpoints return ids only
/// for the sequence, so this detail call is what exposes both the total
/// cycle/session counts and the names of the protocols inside the Plus.
final protocolPlusDetailProvider =
    FutureProvider.family<ProtocolPlus, String>((ref, id) {
  return ref.read(protocolPlusControllerProvider).getProtocolPlusDetail(id);
});

/// Summed cycles + sessions across all populated sub-protocols of a Plus
/// sequence. Both are null until the detail resolves or when the payload isn't
/// populated, so callers can simply hide the figures while unknown.
({int? cycles, int? sessions}) protocolPlusTotals(ProtocolPlus detail) {
  if (detail.protocols.isEmpty) return (cycles: null, sessions: null);
  var cycles = 0;
  var sessions = 0;
  for (final p in detail.protocols) {
    cycles += p.cycles.length;
    sessions += p.sessions;
  }
  return (cycles: cycles, sessions: sessions);
}
