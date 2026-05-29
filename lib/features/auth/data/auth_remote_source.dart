import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../domain/auth_models.dart';

final authRemoteSourceProvider = Provider<AuthRemoteSource>((ref) {
  return AuthRemoteSource(ref.read(djangoDioProvider));
});

class AuthRemoteSource {
  final Dio _dio;

  AuthRemoteSource(this._dio);

  Future<AuthTokens> login(LoginRequest request) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.login,
        data: request.toJson(),
      );
      return AuthTokens.fromJson(response.data);
    } on DioException catch (e) {
      throw AuthException(
        _loginErrorMessage(e),
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Translate a login [DioException] into a clear, user-facing message.
  String _loginErrorMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Please check your internet and try again.';
      case DioExceptionType.connectionError:
        return 'Unable to reach the server. Please check your connection.';
      default:
        break;
    }

    final status = e.response?.statusCode;
    if (status == 400 || status == 401 || status == 403) {
      return 'Incorrect username or password. Please try again.';
    }
    if (status == 404) {
      return 'Account not found. Please check your username.';
    }
    if (status != null && status >= 500) {
      return 'Server error. Please try again in a moment.';
    }

    final data = e.response?.data;
    final serverMessage = data is Map ? data['message'] : null;
    if (serverMessage is String && serverMessage.trim().isNotEmpty) {
      return serverMessage;
    }
    return 'Login failed. Please try again.';
  }

  Future<UserProfile> getProfile() async {
    try {
      final response = await _dio.get(ApiEndpoints.profileMe);
      // return UserProfile.fromJson(response.data);
      final data = response.data;
      print("GET PROFILE RESPONSE: ${response.data}");
      //  appLogger.i("GET PROFILE RESPONSE: $data");r
      if (data is List) {
        return UserProfile.fromJson(data[0]); // ✅ FIX
      } else {
        return UserProfile.fromJson(data);
      }
    } on DioException catch (e) {
      throw ServerException(
        e.response?.data?['message'] ?? 'Failed to fetch profile',
        statusCode: e.response?.statusCode,
      );
    }
  }

//   Future<UserProfile> updateProfile(Map<String, dynamic> data) async {
//   try {
//     final response = await _dio.put(
//       ApiEndpoints.profileMe,
//       data: data,
//     );

//     print("UPDATE RESPONSE: ${response.data}"); // ✅ HERE

//     final res = response.data;
//     print("🔥 FULL RESPONSE: $res");

//     if (res is List) {
//       return UserProfile.fromJson(res[0]);
//     } else if (res is Map<String, dynamic>) {
//       return UserProfile.fromJson(res);
//     } else {
//       // Handle unexpected response format
//       throw Exception("Unexpected response format:");
//     }
//         return await getProfile();

//   } on DioException catch (e) {
//     throw ServerException(
//       e.response?.data?['message'] ?? 'Failed to update profile',
//       statusCode: e.response?.statusCode,
//     );
//   }
// }
  Future<UserProfile> updateProfile(Map<String, dynamic> data) async {
    try {
      final response = await _dio.put(
        ApiEndpoints.profileMe,
        data: data,
      );

      print("UPDATE RESPONSE: ${response.data}");

      final res = response.data;

      // ✅ Handle null or empty response (e.g., 204 No Content or 403)
      if (res == null || res == '' || res == []) {
        // Server returned no body — refetch the profile
        return await getProfile();
      }

      if (res is List && res.isNotEmpty) {
        return UserProfile.fromJson(res[0] as Map<String, dynamic>);
      } else if (res is Map<String, dynamic>) {
        return UserProfile.fromJson(res);
      } else {
        // Fallback: just refetch instead of crashing
        return await getProfile();
      }
    } on DioException catch (e) {
      print("DIO ERROR: ${e.response?.statusCode} - ${e.response?.data}");
      throw ServerException(
        e.response?.data?['message'] ?? 'Failed to update profile',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getOrganizations() async {
    final response = await _dio.get('/api/v1/admin/organizations');
    return List<Map<String, dynamic>>.from(response.data);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    try {
      await _dio.put(
        ApiEndpoints.changePassword,
        data: {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
          'confirmPassword': confirmPassword,
        },
      );
    } on DioException catch (e) {
      throw ServerException(
        e.response?.data?['message'] ?? 'Failed to change password',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> forgotPassword(String userId) async {
    final response = await _dio.put(
      "/api/v1/profile/me/forget-password/$userId",
    );

    print("FORGOT PASSWORD: ${response.data}");
  }
}
