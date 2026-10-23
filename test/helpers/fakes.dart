// Shared test doubles. These were copy-pasted (as `_FakeAuth`, `_FakeScanner`,
// `_FakeTokens`, ...) across most widget tests; import this file instead.
//
// Every fake answers unimplemented members through `noSuchMethod`, so a screen
// that calls something the test doesn't care about gets `null` instead of a
// crash. Calls are recorded in [invocations] where that is useful to assert on.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hydrawav3/features/auth/data/auth_remote_source.dart';
import 'package:hydrawav3/features/auth/domain/auth_models.dart';
import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';
import 'package:hydrawav3/features/ble/services/ble_scanner.dart';
import 'package:hydrawav3/features/clients/data/client_repository.dart';
import 'package:hydrawav3/features/clients/domain/client_model.dart';
import 'package:hydrawav3/features/clients/presentation/providers/lease_controller.dart';
import 'package:hydrawav3/features/history/data/history_repository.dart';
import 'package:hydrawav3/features/history/domain/session_history_model.dart';
import 'package:hydrawav3/features/notifications/data/notification_remote_source.dart';
import 'package:hydrawav3/features/notifications/domain/app_notification.dart';
import 'package:hydrawav3/features/payments/presentation/providers/token_balance_provider.dart';
import 'package:hydrawav3/features/session/domain/active_session_model.dart';
import 'package:hydrawav3/features/session/presentation/providers/live_sessions_provider.dart';

/// A signed-in [AuthNotifier] with a fixed [AuthState]; nothing hits the
/// network or secure storage.
///
/// ```dart
/// authStateProvider.overrideWith((ref) => FakeAuth(orgName: 'Gulf Coast Tarpons'))
/// ```
class FakeAuth extends StateNotifier<AuthState> implements AuthNotifier {
  FakeAuth({
    String userId = '7',
    String firstName = 'Marcus',
    String? lastName,
    String orgId = '1',
    String? orgName,
    String? orgType,
    List<String>? roles,
  }) : super(AuthState(
          isAuthenticated: true,
          isInitialized: true,
          selectedOrgId: orgId,
          selectedOrgName: orgName,
          user: UserProfile(
            id: userId,
            firstName: firstName,
            lastName: lastName,
            organizationType: orgType,
            roles: roles,
          ),
        ));

  /// Any state at all, e.g. signed out: `FakeAuth.withState(const AuthState())`.
  FakeAuth.withState(super.state);

  final invocations = <Invocation>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    invocations.add(invocation);
    return null;
  }
}

/// `GET /profile/me` without a server.
class FakeAuthSource implements AuthRemoteSource {
  FakeAuthSource([
    this.profile = const UserProfile(id: '7', firstName: 'Marcus'),
  ]);

  final UserProfile profile;

  @override
  Future<UserProfile> getProfile() async => profile;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// No Bluetooth on the test machine: scans are no-ops.
class FakeScanner implements BleScanner {
  final invocations = <Invocation>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    invocations.add(invocation);
    return null;
  }
}

/// A token balance that never opens a socket.
class FakeTokens extends StateNotifier<double?>
    implements TokenBalanceNotifier {
  FakeTokens([super.balance]);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Live sessions with no socket behind them.
class FakeLiveSessions extends StateNotifier<List<ActiveSession>>
    implements LiveSessionsNotifier {
  FakeLiveSessions([super.sessions = const []]);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// An idle lease flow; lease actions are recorded, not performed.
class FakeLease extends StateNotifier<LeaseFlowState>
    implements LeaseController {
  FakeLease([super.state = const LeaseFlowState()]);

  final invocations = <Invocation>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    invocations.add(invocation);
    return null;
  }
}

/// Serves one client by id; everything else is a no-op.
class FakeClientRepo implements ClientRepository {
  FakeClientRepo(this.client);

  final Client client;

  @override
  Future<Client> getById(String clientId) async => client;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Serves [items] and swallows mark-read POSTs (recorded in [read]) so a test
/// never leaves a request in flight.
class FakeNotificationSource implements NotificationRemoteSource {
  FakeNotificationSource([this.items = const []]);

  final List<AppNotification> items;
  final read = <String>[];

  @override
  Future<List<AppNotification>> getNotifications(String userId) async => items;

  @override
  Future<void> markRead(String id) async => read.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The paginated history list ("All" chip) serving a fixed list, no network.
///
/// ```dart
/// historyPagingProvider.overrideWith((ref) => FixedHistory(ref, items))
/// ```
class FixedHistory extends HistoryPagingNotifier {
  FixedHistory(super.ref, List<SessionHistoryItem> items) {
    state = HistoryPageState(items: items, page: 1, hasMore: false);
  }

  @override
  Future<void> loadFirstPage() async {}

  @override
  Future<void> loadMore() async {}
}
