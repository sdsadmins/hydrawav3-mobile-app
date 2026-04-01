class LoginRequest {
  final String username;
  final String password;
  final bool rememberMe;

  const LoginRequest({
    required this.username,
    required this.password,
    this.rememberMe = false,
  });

  Map<String, dynamic> toJson() => {
        'username': username,
        'password': password,
        'rememberMe': rememberMe,
      };
}

class AuthTokens {
  final String accessToken;
  final String refreshToken;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: json['JWT_ACCESS_TOKEN'] as String,
        refreshToken: json['JWT_REFRESH_TOKEN'] as String,
      );
}

class UserProfile {
  final String? id;
  final String? username;
  final String? email;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? role;
  final List<String>? roles;
  final String? profilePicture;
  final String? organizationId;

  const UserProfile({
    this.id,
    this.username,
    this.email,
    this.firstName,
    this.lastName,
    this.phone,
    this.role,
    this.roles,
    this.profilePicture,
    this.organizationId,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id']?.toString(),
        username: json['username'] as String?,
        email: json['email'] as String?,
        firstName: json['firstName'] as String?,
        lastName: json['lastName'] as String?,
        phone: json['phone'] as String?,
        role: json['role'] as String?,
        roles: (json['roles'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
        profilePicture: json['profilePicture'] as String?,
        organizationId: json['organization']?['id']?.toString(),
      );

  String get displayName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    }
    return username ?? email ?? 'User';
  }
}
