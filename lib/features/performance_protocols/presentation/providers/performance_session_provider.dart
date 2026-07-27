import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../domain/performance_models.dart';

const _uuid = Uuid();

/// The conversation id sent on EVERY performance-protocols call.
///
/// A tier-1 safety lock is per session: without a stable id, an emergency named
/// in turn 1 doesn't stick in turn 2. So this is minted once and only rotated on
/// an explicit "start over" / client switch — never per request.
final performanceSessionIdProvider = StateProvider<String>((ref) => _uuid.v4());

/// Rotates the session id. Call this when the practitioner explicitly starts a
/// new conversation or switches to a different client — not between steps of the
/// same flow, or the safety lock is lost.
void resetPerformanceSession(Ref ref) {
  ref.read(performanceSessionIdProvider.notifier).state = _uuid.v4();
}

/// The pad set the practitioner last accepted, so the session surface can name
/// the chain that produced the placement. The service returns no protocol, so
/// nothing about the session is inferred from it.
final activePadSetProvider = StateProvider<PadSetPayload?>((ref) => null);

/// Protocol pre-loaded by "Go to Session" (the reference's `SS.proto`). Session
/// setup consumes it once and clears it, so it never leaks into a later session.
final pendingSessionProtocolProvider = StateProvider<String?>((ref) => null);
