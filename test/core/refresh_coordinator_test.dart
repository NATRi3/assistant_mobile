import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:assistant/core/api/api_error.dart';
import 'package:assistant/core/platform/platform_gateway.dart';
import 'package:assistant/core/session/session_memory.dart';
import 'package:assistant/core/session/session_controller.dart';
import 'package:assistant/core/session/refresh_coordinator.dart';

import '../support/fakes.dart';
import '../support/fixtures.dart';

void main() {
  test(
    'persist rotation before request; lost response resumes SAME key and body',
    () async {
      final p = FakePlatform(), m = SessionMemory(), api = FakeApi();
      m.adopt(UnlockResult(7, fixtureSession()));
      final store = SessionStore(p, m);
      await store.install(fixtureSession(), 7);
      api.handler = (op, key, body) async {
        expect(p.saved!.value['pending_refresh'], isNotNull);
        throw const ApiError(0, 'TIMEOUT');
      };
      final c = RefreshCoordinator(
        api,
        m,
        store,
        now: () => DateTime.utc(2026, 10, 31, 12),
      );
      await expectLater(c.resumeOrRefresh(), throwsA(isA<ApiError>()));
      expect(api.calls, hasLength(1));
      api.handler = (op, key, body) async => fixtureSession().toJson();
      await RefreshCoordinator(
        api,
        m,
        store,
        now: () => DateTime.utc(2026, 10, 31, 12, 0, 30),
      ).resumeOrRefresh();
      expect(api.calls, hasLength(2));
      expect(api.calls[1].key, api.calls[0].key);
      expect(api.calls[1].body, api.calls[0].body);
      expect(p.saved!.value['pending_refresh'], isNull);
    },
  );
  test('singleflight and late lock prevent installed response', () async {
    final p = FakePlatform(), m = SessionMemory(), api = FakeApi();
    m.adopt(UnlockResult(7, fixtureSession()));
    final barrier = Completer<Map<String, Object?>>();
    api.handler = (_, key, body) => barrier.future;
    final c = RefreshCoordinator(
      api,
      m,
      SessionStore(p, m),
      now: () => DateTime.utc(2026, 10, 31, 12),
    );
    final one = c.resumeOrRefresh(), two = c.resumeOrRefresh();
    await Future<void>.delayed(Duration.zero);
    expect(api.calls, hasLength(1));
    final a = expectLater(one, throwsA(isA<StateError>())),
        b = expectLater(two, throwsA(isA<StateError>()));
    m.lock(const NativeLockEvent(8));
    p.unlocked = false;
    barrier.complete(fixtureSession().toJson());
    await Future.wait([a, b]);
    expect(m.current, isNull);
  });
  test('expired refresh receipt fails closed without outgoing retry', () async {
    final p = FakePlatform(), m = SessionMemory(), api = FakeApi();
    m.adopt(UnlockResult(7, fixtureSession()));
    p.saved = PrivateCacheRead(
      {
        'session': fixtureSession().toJson(),
        'pending_refresh': {
          'action_key': deviceId,
          'refresh_token': fixtureSession().refreshToken,
          'started_at': '2026-10-31T12:00:00Z',
        },
      },
      DateTime.utc(2026, 10, 31, 12),
      1,
    );
    final c = RefreshCoordinator(
      api,
      m,
      SessionStore(p, m),
      now: () => DateTime.utc(2026, 10, 31, 12, 1),
    );
    await expectLater(c.resumeOrRefresh(), throwsA(isA<ApiError>()));
    expect(api.calls, isEmpty);
    expect(m.current, isNull);
    expect(m.unlocked, isFalse);
  });
}
