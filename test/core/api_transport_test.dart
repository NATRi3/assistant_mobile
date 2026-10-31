import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:assistant/core/api/api_client.dart';
import 'package:assistant/core/api/api_error.dart';
import 'package:assistant/core/config/app_config.dart';
import 'package:assistant/core/platform/platform_gateway.dart';
import 'package:assistant/core/session/session_memory.dart';

import '../support/fakes.dart';
import '../support/fixtures.dart';

void main() {
  // Contract statuses come from the checked-in OpenAPI, independent of routing.
  for (final entry in [
    (ApiOperation.submitChat, 202, 200),
    (ApiOperation.recordNotificationReceipt, 202, 200),
    (ApiOperation.deletePushRegistration, 200, 204),
  ]) {
    test(
      '${entry.$1.name} accepts only its contractual success status',
      () async {
        final p = FakePlatform(), t = FakeTransport(), m = SessionMemory();
        m.adopt(UnlockResult(7, fixtureSession()));
        final api = ApiClient(
          AppConfig.parse('https://mobile.example.invalid'),
          p,
          t,
          m,
        );
        t.handler = (_) async => ApiResponse(entry.$2, {}, utf8.encode('{}'));
        expect(await api.call(entry.$1, actionKey: deviceId), isEmpty);
        t.handler = (_) async =>
            ApiResponse(entry.$3, {}, entry.$3 == 204 ? [] : utf8.encode('{}'));
        await expectLater(
          api.call(entry.$1, actionKey: deviceId),
          throwsA(isA<ApiError>()),
        );
      },
    );
  }

  test(
    'allowed routes bind method, body, access and stable action key',
    () async {
      final p = FakePlatform(), t = FakeTransport(), m = SessionMemory();
      m.adopt(UnlockResult(7, fixtureSession()));
      t.handler = (_) async => const ApiResponse(204, {}, []);
      final api = ApiClient(
        AppConfig.parse('https://mobile.example.invalid'),
        p,
        t,
        m,
      );
      await api.call(ApiOperation.revokeSelfDevice, actionKey: deviceId);
      final req = t.requests.single;
      expect(req.method, 'DELETE');
      expect(
        req.uri.toString(),
        'https://mobile.example.invalid/mobile/v1/devices/self',
      );
      expect(
        req.headers['Authorization'],
        'DPoP ${fixtureSession().accessToken}',
      );
      expect(req.headers['Idempotency-Key'], deviceId);
      expect(req.headers['DPoP'], 'proof');
      expect(utf8.decode(req.body!), '{}');
    },
  );
  test(
    'transport cannot bypass absent config, limits, redirect or stale epoch',
    () async {
      final p = FakePlatform(), t = FakeTransport(), m = SessionMemory();
      m.adopt(UnlockResult(7, fixtureSession()));
      await expectLater(
        ApiClient(
          AppConfig.parse(''),
          p,
          t,
          m,
        ).call(ApiOperation.getSelfDevice),
        throwsA(isA<ApiError>()),
      );
      expect(t.requests, isEmpty);
      expect(p.trace, isEmpty);
      final api = ApiClient(
        AppConfig.parse('https://mobile.example.invalid'),
        p,
        t,
        m,
      );
      await expectLater(
        api.call(ApiOperation.createPairing, body: {'x': 'x' * 16384}),
        throwsA(isA<ApiError>()),
      );
      expect(t.requests, isEmpty);
      t.handler = (_) async => ApiResponse(200, {}, List.filled(262145, 32));
      await expectLater(
        api.call(ApiOperation.getSelfDevice),
        throwsA(isA<ApiError>()),
      );
      t.handler = (_) async => ApiResponse(302, {
        'location': 'https://other.invalid',
      }, utf8.encode('{}'));
      await expectLater(
        api.call(ApiOperation.getSelfDevice),
        throwsA(isA<ApiError>()),
      );
      final late = Completer<ApiResponse>();
      t.handler = (_) => late.future;
      final future = api.call(ApiOperation.getSelfDevice);
      await Future<void>.delayed(Duration.zero);
      m.lock(const NativeLockEvent(8));
      api.cancelPrivateRequests();
      late.complete(ApiResponse(200, {}, utf8.encode('{}')));
      await expectLater(future, throwsA(isA<ApiError>()));
      expect(t.aborted, isTrue);
    },
  );
  test(
    'duplicate keys and deep response cannot silently replace security fields',
    () async {
      final p = FakePlatform(), t = FakeTransport(), m = SessionMemory();
      m.adopt(UnlockResult(7, fixtureSession()));
      final api = ApiClient(
        AppConfig.parse('https://mobile.example.invalid'),
        p,
        t,
        m,
      );
      t.handler = (_) async => ApiResponse(
        200,
        {},
        utf8.encode('{"device_id":"a","device_id":"b"}'),
      );
      await expectLater(
        api.call(ApiOperation.getSelfDevice),
        throwsA(isA<ApiError>()),
      );
    },
  );
}
