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
        e.response?.data?['message'] ?? 'Login failed',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<UserProfile> getProfile() async {
    try {
      final response = await _dio.get(ApiEndpoints.profileMe);
      // return UserProfile.fromJson(response.data);
      final data = response.data;
      print("GET PROFILE RESPONSE: ${response.data}");

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

  // Future<UserProfile> updateProfile(Map<String, dynamic> data) async {
  //   try {
  //     final response = await _dio.put(
  //       ApiEndpoints.profileMe,// "/api/v1/profile/me",
  //       data: data,
  //     );
  //     return UserProfile.fromJson(response.data);
  //   } on DioException catch (e) {
  //     throw ServerException(
  //       e.response?.data?['message'] ?? 'Failed to update profile',
  //       statusCode: e.response?.statusCode,
  //     );
  //   }
  //   print("UPDATE RESPONSE: ${response.data}");
  // }
  Future<UserProfile> updateProfile(Map<String, dynamic> data) async {
  try {
    final response = await _dio.put(
      ApiEndpoints.profileMe,
      data: data,
    );

    print("UPDATE RESPONSE: ${response.data}"); // ✅ HERE

    final res = response.data;
    print("🔥 FULL RESPONSE: $res");

    if (res is List) {
      return UserProfile.fromJson(res[0]);
    } else if (res is Map<String, dynamic>) {
      return UserProfile.fromJson(res);
    } else {
      // Handle unexpected response format
      throw Exception("Unexpected response format:");
    }
        return await getProfile();

  } on DioException catch (e) {
    throw ServerException(
      e.response?.data?['message'] ?? 'Failed to update profile',
      statusCode: e.response?.statusCode,
    );
  }
}


  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      await _dio.put(
        ApiEndpoints.changePassword,
        data: {
          'oldPassword': oldPassword,
          'newPassword': newPassword,
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