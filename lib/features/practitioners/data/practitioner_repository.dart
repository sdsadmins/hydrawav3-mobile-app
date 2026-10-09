import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/utils/extensions.dart';
import '../../auth/presentation/providers/auth_provider.dart';

/// A practitioner login in an organization — a `user_account` row from
/// `GET practitioners/by-org/:orgId` (the web Practitioners page's source).
class Practitioner {
  final int id;
  final String firstName;
  final String lastName;
  final String? userName;
  final String? mail;
  final String? phone;
  final String? title;
  final String? dateOfBirth;
  final String? address;
  final String? city;
  final String? state;
  final String? zip;
  final String? country;
  final bool? isEnabled;

  const Practitioner({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.userName,
    this.mail,
    this.phone,
    this.title,
    this.dateOfBirth,
    this.address,
    this.city,
    this.state,
    this.zip,
    this.country,
    this.isEnabled,
  });

  String get name {
    final n = '$firstName $lastName'.trim();
    return n.isEmpty ? (userName ?? 'Practitioner') : n;
  }

  String get initials {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  static String? _s(dynamic v) {
    final t = v?.toString().trim();
    return (t == null || t.isEmpty || t == 'unknown') ? null : t;
  }

  factory Practitioner.fromJson(Map<String, dynamic> j) => Practitioner(
        id: int.tryParse('${j['id']}') ?? 0,
        firstName: _s(j['firstName'] ?? j['firstname']) ?? '',
        lastName: _s(j['lastName'] ?? j['lastname']) ?? '',
        userName: _s(j['userName'] ?? j['username']),
        mail: _s(j['mail'] ?? j['email']),
        phone: _s(j['phone']),
        title: _s(j['title']),
        dateOfBirth: _s(j['dateOfBirth']),
        address: _s(j['address']),
        city: _s(j['city']),
        state: _s(j['state']),
        zip: _s(j['zip']),
        country: _s(j['country']),
        isEnabled: j['isEnabled'] is bool ? j['isEnabled'] as bool : null,
      );
}

/// Body for `POST secondary/create` — the web's "Create Practitioner".
class NewPractitioner {
  final String firstName;
  final String lastName;
  final String userName;
  final String password;
  final String email;
  final String phone;
  final String title;
  final String address;
  final String city;
  final String? state;
  final String? zip;
  final String country;
  final String? dateOfBirth; // yyyy-MM-dd
  final List<int> organizationIds;

  const NewPractitioner({
    required this.firstName,
    required this.lastName,
    required this.userName,
    required this.password,
    required this.email,
    required this.phone,
    required this.title,
    required this.address,
    required this.city,
    required this.country,
    required this.organizationIds,
    this.state,
    this.zip,
    this.dateOfBirth,
  });

  Map<String, dynamic> toJson() => {
        'firstname': firstName,
        'lastname': lastName,
        'userName': userName,
        'password': password,
        'email': email,
        'phone': phone,
        'practitionerType': title,
        'address': address,
        'city': city,
        if (state != null && state!.isNotEmpty) 'state': state,
        if (zip != null && zip!.isNotEmpty) 'zip': zip,
        'country': country,
        if (dateOfBirth != null && dateOfBirth!.isNotEmpty)
          'dateOfBirth': dateOfBirth,
        'addOrganisations': organizationIds,
      };
}

class PractitionerRepository {
  final Dio _node;
  const PractitionerRepository(this._node);

  /// Everyone with a login in [orgId]. The endpoint answers 404 when the
  /// organization has no accounts yet — that's an empty team, not an error.
  Future<List<Practitioner>> byOrg(String orgId) async {
    try {
      final res = await _node.get('practitioners/by-org/$orgId');
      final data = res.data;
      final list = data is List
          ? data
          : (data is Map && data['data'] is List ? data['data'] as List : []);
      return [
        for (final e in list)
          if (e is Map) Practitioner.fromJson(Map<String, dynamic>.from(e)),
      ];
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const [];
      rethrow;
    }
  }

  /// Creates the login and links it to [NewPractitioner.organizationIds].
  Future<void> create(NewPractitioner p) async {
    try {
      final res = await _node.post('secondary/create', data: p.toJson());
      final data = res.data;
      if (data is Map && data['success'] == false) {
        throw Exception(data['message'] ?? 'Could not create practitioner');
      }
    } on DioException catch (e) {
      final body = e.response?.data;
      final msg = body is Map ? body['message'] : null;
      throw Exception(msg is List
          ? msg.join('\n')
          : (msg?.toString() ?? 'Could not create practitioner'));
    }
  }
}

final practitionerRepositoryProvider = Provider<PractitionerRepository>(
  (ref) => PractitionerRepository(ref.read(nodeDioProvider)),
);

final practitionersByOrgProvider = FutureProvider.autoDispose
    .family<List<Practitioner>, String>((ref, orgId) {
  return ref.read(practitionerRepositoryProvider).byOrg(orgId);
});

/// The roles carried in the signed-in practitioner's access token. The
/// profile endpoints don't return roles, so this reads the JWT's `roles`
/// claim (e.g. `PRIMARY ACCOUNT - ADMIN`, `PRACTITIONER`).
final sessionRolesProvider = FutureProvider<List<String>>((ref) async {
  final auth = ref.watch(authStateProvider);
  if (!auth.isAuthenticated) return const [];
  final fromProfile = [
    ...?auth.user?.roles,
    if (auth.user?.role != null) auth.user!.role!,
  ];
  if (fromProfile.isNotEmpty) return fromProfile;
  try {
    final token =
        (await ref.read(secureStorageProvider).getAccessToken())
            ?.withoutBearerPrefix;
    return rolesFromJwt(token);
  } catch (_) {
    return const [];
  }
});

/// The `roles` (or `role`) claim of a JWT, or empty when unreadable.
List<String> rolesFromJwt(String? token) {
  if (token == null) return const [];
  final parts = token.split('.');
  if (parts.length < 2) return const [];
  try {
    final claims = jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
        as Map<String, dynamic>;
    final roles = claims['roles'];
    if (roles is List) return roles.map((e) => '$e').toList();
    if (claims['role'] != null) return ['${claims['role']}'];
  } catch (_) {}
  return const [];
}

/// True for the account owner (`PRIMARY ACCOUNT - ADMIN`) — the only role
/// the web shows Practitioners and Organizations management to.
final isPrimaryAdminProvider = Provider<bool>((ref) {
  final roles = ref.watch(sessionRolesProvider).valueOrNull ?? const [];
  return roles
      .any((r) => r.toUpperCase().trim() == 'PRIMARY ACCOUNT - ADMIN');
});
