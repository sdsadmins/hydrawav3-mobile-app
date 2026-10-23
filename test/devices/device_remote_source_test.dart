// DeviceRemoteSource: the statuses the web app treats as "no devices to show"
// (401 / 403 / 404 / 204) come back as an empty list, not an error.
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/core/constants/api_endpoints.dart';
import 'package:hydrawav3/features/devices/data/device_remote_source.dart';

import '../helpers/fake_http.dart';

void main() {
  const orgId = '7';

  for (final status in [401, 403, 404]) {
    test('[FIX-18] getDevices and getDevicesByOrg return [] on $status',
        () async {
      final server = FakeHttp()
        ..onStatus('GET', ApiEndpoints.sensors, status)
        ..onStatus('GET', ApiEndpoints.sensorsByOrg(orgId), status);
      final source = DeviceRemoteSource(server.dio());

      expect(await source.getDevices(), isEmpty);
      expect(await source.getDevicesByOrg(orgId), isEmpty);
      expect(server.requestsTo(ApiEndpoints.sensors, method: 'GET'),
          hasLength(1));
      expect(
          server.requestsTo(ApiEndpoints.sensorsByOrg(orgId), method: 'GET'),
          hasLength(1));
    });
  }

  test(
    '[FIX-18] getDevices and getDevicesByOrg return [] on 204 No Content',
    () async {
      final server = FakeHttp()
        ..onStatus('GET', ApiEndpoints.sensors, 204)
        ..onStatus('GET', ApiEndpoints.sensorsByOrg(orgId), 204);
      final source = DeviceRemoteSource(server.dio());

      expect(await source.getDevices(), isEmpty);
      expect(await source.getDevicesByOrg(orgId), isEmpty);
    },
    // device_remote_source.dart:47 lists 204 among the empty-result statuses,
    // but Dio treats 204 as a success, so the `on DioException` branch never
    // runs: the empty body reaches line 53 / 72 as '' and `data['data']`
    // throws "type 'String' is not a subtype of type 'int' of 'index'".
    tags: ['qa-known-bug'],
  );

  test('[FIX-18] a populated 200 still parses into devices', () async {
    final server = FakeHttp()
      ..onJson('GET', ApiEndpoints.sensorsByOrg(orgId), [
        {'id': 1, 'name': 'Hydra-Unit 1', 'macAddress': '48:CA:43:B0:02:B1'},
      ]);
    final source = DeviceRemoteSource(server.dio());

    final devices = await source.getDevicesByOrg(orgId);
    expect(devices, hasLength(1));
    expect(devices.single.name, 'Hydra-Unit 1');
    expect(devices.single.macAddress, '48:CA:43:B0:02:B1');
  });
}
