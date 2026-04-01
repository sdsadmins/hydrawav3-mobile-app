import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import '../constants/api_endpoints.dart';
import '../constants/app_constants.dart';
import 'auth_interceptor.dart';

final loggerProvider = Provider<Logger>((ref) => Logger(
      printer: PrettyPrinter(methodCount: 0, printTime: true),
    ));

/// Dio instance for Django backend (auth, profile, organizations, sensors)
final djangoDioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: ApiEndpoints.djangoBaseUrl,
    connectTimeout: AppConstants.connectTimeout,
    receiveTimeout: AppConstants.receiveTimeout,
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.add(ref.read(authInterceptorProvider));
  dio.interceptors.add(LogInterceptor(
    requestBody: true,
    responseBody: true,
    logPrint: (obj) => ref.read(loggerProvider).d(obj),
  ));

  return dio;
});

/// Dio instance for Node.js backend (clients, protocols, payments, intake)
final nodeDioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: ApiEndpoints.nodeBaseUrl,
    connectTimeout: AppConstants.connectTimeout,
    receiveTimeout: AppConstants.receiveTimeout,
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.add(ref.read(authInterceptorProvider));
  dio.interceptors.add(LogInterceptor(
    requestBody: true,
    responseBody: true,
    logPrint: (obj) => ref.read(loggerProvider).d(obj),
  ));

  return dio;
});

/// Dio instance for device control (Wi-Fi commands)
final deviceDioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: ApiEndpoints.deviceControlUrl,
    connectTimeout: AppConstants.connectTimeout,
    receiveTimeout: AppConstants.receiveTimeout,
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.add(ref.read(authInterceptorProvider));

  return dio;
});
