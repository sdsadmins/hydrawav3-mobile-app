import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/history/data/history_remote_source.dart';
import 'package:hydrawav3/features/history/domain/session_history_model.dart';
import 'package:hydrawav3/features/session/domain/pending_session_outcome_model.dart';
import 'package:hydrawav3/features/session/domain/session_model.dart';
import 'package:hydrawav3/features/session_coach/data/coach_plan_store.dart';
import 'package:hydrawav3/features/session_coach/data/session_coach_repository.dart';
import 'package:hydrawav3/features/session_coach/domain/session_coach_models.dart';

const _coachRun = SessionCoachRun(
  sessionCoachId: 'coach-1',
  bodyPartId: 'body-1',
  bodyPartName: 'Knee',
  supportType: 'Support recovery',
  sets: [
    SessionCoachRunSet(
      index: 0,
      setId: 'set-1',
      name: 'Calf',
      protocolId: 'protocol-1',
      protocolName: 'Recovery',
      macAddress: 'AA:BB:CC',
      startDelay: 0,
    ),
  ],
);

final _protocolMetadata = {
  'AA:BB:CC': {
    'protocolId': 'protocol-1',
    'macAddress': 'AA:BB:CC',
    'advancedSettings': {'lights': false, 'startDelay': 0},
  },
};

SessionRecord _record({SessionCoachRun? coach}) {
  final now = DateTime.utc(2026, 11, 6);
  return SessionRecord(
    id: 'session-1',
    protocolId: 'protocol-1',
    protocolName: 'Recovery',
    deviceIds: const ['AA:BB:CC'],
    protocolByDeviceId: const {
      'AA:BB:CC': (name: 'Recovery', durationSeconds: 120),
    },
    protocolMetadataByDeviceId: _protocolMetadata,
    sessionCoach: coach,
    totalDurationSeconds: 120,
    elapsedSeconds: 120,
    createdAt: now,
    updatedAt: now,
    completedAt: now,
  );
}

void main() {
  test('intake POST carries coach details and per-protocol metadata', () {
    final json = _record(coach: _coachRun).toIntakeJson();
    expect(json['sessionType'], 'session_coach');
    expect(json['sessionCoach'], _coachRun.toJson());
    expect((json['protocols'] as List).single, {
      'bodyPart': 'General',
      'protocol': 'Recovery',
      'duration': 120,
      'deviceName': 'AA:BB:CC',
      ..._protocolMetadata['AA:BB:CC']!,
    });
  });

  test('normal sessions keep their type and advanced settings', () {
    final json = _record().toIntakeJson();
    expect(json['sessionType'], 'session');
    expect(json.containsKey('sessionCoach'), isFalse);
    expect((json['protocols'] as List).single['advancedSettings'],
        {'lights': false, 'startDelay': 0});
  });

  test('pending outcomes retain coach and protocol metadata for retry', () {
    final now = DateTime.utc(2026, 11, 6);
    final pending = PendingSessionOutcome(
      sessionId: 'session-1',
      protocolId: 'protocol-1',
      protocolName: 'Recovery',
      deviceIds: const ['AA:BB:CC'],
      protocolMetadataByDeviceId: _protocolMetadata,
      sessionCoach: _coachRun,
      createdAt: now,
    );
    final restored = PendingSessionOutcome.fromJson(pending.toJson());
    final record = SessionRecord.fromPending(restored, null);
    expect(record.sessionCoach?.toJson(), _coachRun.toJson());
    expect(record.protocolMetadataByDeviceId, _protocolMetadata);
  });

  test('history recognizes and parses a coached intake', () {
    final item = SessionHistoryItem.fromJson({
      '_id': 'session-1',
      'sessionType': 'session_coach',
      'sessionCoach': _coachRun.toJson(),
    });
    expect(item.isSessionCoach, isTrue);
    expect(item.sessionCoach?.sets.single.macAddress, 'AA:BB:CC');
  });

  test('saved intake restores each set advanced settings by MAC', () {
    final plan = CoachPlanRecord.fromIntake({
      'createdAt': '2026-11-06T10:00:00Z',
      'sessionCoach': _coachRun.toJson(),
      'protocols': [
        {
          'protocolId': 'protocol-1',
          'macAddress': 'aa:bb:cc',
          'advancedSettings': {
            'lights': false,
            'vibrationMode': 'Single',
          },
        },
      ],
    });

    expect(plan, isNotNull);
    expect(plan!.sets.single.unitId, 'AA:BB:CC');
    expect(plan.sets.single.advancedSettings, {
      'lights': false,
      'vibrationMode': 'Single',
    });
    expect(
      CoachPlanRecord.fromJson(plan.toJson())?.sets.single.advancedSettings,
      plan.sets.single.advancedSettings,
    );
  });

  test('recent Session Coach endpoint returns plan settings per MAC', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        data: {
          'data': [
            {
              'createdAt': '2026-11-06T10:00:00Z',
              'sessionCoach': _coachRun.toJson(),
              'protocols': [
                {
                  'protocolId': 'protocol-1',
                  'macAddress': 'AA:BB:CC',
                  'advancedSettings': {
                    'lights': false,
                    'vibrationMode': 'Single',
                  },
                },
              ],
            },
          ],
        },
      ));
    }));

    final plan = await SessionCoachRepository(dio).recentPlan('client-1');

    expect(plan?.sets.single.unitId, 'AA:BB:CC');
    expect(plan?.sets.single.advancedSettings, {
      'lights': false,
      'vibrationMode': 'Single',
    });
  });

  test('client history enriches missing coach fields from the recent endpoint',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.path.endsWith('/intake/client/client-1')) {
        handler.resolve(Response(
          requestOptions: options,
          data: {
            'data': [
              {
                '_id': 'session-1',
                'clientId': 'client-1',
                'clientType': 'client',
                'protocols': [],
              },
            ],
          },
        ));
      } else {
        handler.resolve(Response(
          requestOptions: options,
          data: [
            {
              '_id': 'session-1',
              'clientId': 'client-1',
              'clientType': 'client',
              'sessionType': 'session_coach',
              'sessionCoach': _coachRun.toJson(),
              'protocols': [
                {
                  'protocolId': 'protocol-1',
                  'macAddress': 'AA:BB:CC',
                  'advancedSettings': {
                    'lights': false,
                    'vibrationMode': 'Single',
                  },
                },
              ],
            },
          ],
        ));
      }
    }));

    final sessions =
        await HistoryRemoteSource(dio).getClientHistory('client-1');
    expect(sessions, hasLength(1));
    expect(sessions.single.isSessionCoach, isTrue);
    expect(sessions.single.sessionCoach?.sessionCoachId, 'coach-1');
    expect(sessions.single.protocols.single.advancedSettings, {
      'lights': false,
      'vibrationMode': 'Single',
    });
  });
}
