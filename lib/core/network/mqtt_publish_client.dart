import 'package:dio/dio.dart';

import '../constants/api_endpoints.dart';

Future<Response<String>> postMqttPublishRequest(
  Dio dio, {
  required Map<String, dynamic> data,
}) {
  return dio.post<String>(
    ApiEndpoints.mqttPublish,
    data: data,
    options: Options(
      responseType: ResponseType.plain,
      headers: const {
        'Accept': 'application/json, text/plain, */*',
      },
    ),
  );
}
