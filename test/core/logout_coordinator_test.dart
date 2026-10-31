import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:assistant/core/api/api_client.dart';
import 'package:assistant/core/config/app_config.dart';
import 'package:assistant/core/platform/platform_gateway.dart';
import 'package:assistant/core/session/session_memory.dart';
import 'package:assistant/core/session/logout_coordinator.dart';

import '../support/fakes.dart';
import '../support/fixtures.dart';

void main() {
  test(
    'HTTP 200 cannot confirm revoke and still destroys local state',
    () async {
      final p = FakePlatform(), m = SessionMemory(), t = FakeTransport();
      m.adopt(UnlockResult(7, fixtureSession()));
      t.handler = (_) async => ApiResponse(200, {}, utf8.encode('{}'));
      bool? recorded;
      final c = LogoutCoordinator(
        p,
        m,
        FakeApi(),
        (session) => ApiClient(
          AppConfig.parse('https://mobile.example.invalid'),
          p,
          t,
          m,
          revokeSession: session,
        ),
        recordResult: (value) async {
          recorded = value;
        },
      );
      final confirmed = await c.logout();
      expect(p.keyExists, isFalse);
      expect(m.current, isNull);
      expect(p.trace.last, 'destroy');
      expect(confirmed, isFalse);
      expect(recorded, isFalse);
    },
  );
  for (final success in [true, false]) {
    test(
      'logout covers then signs with retained key then destroys (success=$success)',
      () async {
        final p = FakePlatform(),
            m = SessionMemory(),
            t = FakeTransport(),
            normal = FakeApi();
        m.adopt(UnlockResult(7, fixtureSession()));
        bool? confirmed;
        t.handler = (req) async {
          p.trace.add('DELETE');
          expect(m.current, isNull);
          expect(p.keyExists, isTrue);
          if (!success) throw StateError('offline');
          return const ApiResponse(204, {}, []);
        };
        final c = LogoutCoordinator(
          p,
          m,
          normal,
          (session) => ApiClient(
            AppConfig.parse('https://mobile.example.invalid'),
            p,
            t,
            m,
            revokeSession: session,
          ),
          recordResult: (v) async {
            confirmed = v;
          },
        );
        expect(await c.logout(), success);
        expect(p.trace, [
          'cover',
          'sign:revokeSelfDevice',
          'DELETE',
          'destroy',
        ]);
        expect(p.keyExists, isFalse);
        expect(confirmed, success);
      },
    );
  }
  test('locked logout destroys without unlock or sign', () async {
    final p = FakePlatform()..unlocked = false, m = SessionMemory();
    bool? confirmed;
    final c = LogoutCoordinator(
      p,
      m,
      FakeApi(),
      (_) => throw StateError('must not create transport'),
      recordResult: (v) async {
        confirmed = v;
      },
    );
    expect(await c.logout(), isFalse);
    expect(p.trace, ['cover', 'destroy']);
    expect(confirmed, isFalse);
  });
  test('five-second logout deadline aborts and always destroys', () async {
    final p = FakePlatform(), m = SessionMemory(), t = FakeTransport();
    m.adopt(UnlockResult(7, fixtureSession()));
    t.handler = (_) => Completer<ApiResponse>().future;
    final c = LogoutCoordinator(
      p,
      m,
      FakeApi(),
      (session) => ApiClient(
        AppConfig.parse('https://mobile.example.invalid'),
        p,
        t,
        m,
        revokeSession: session,
      ),
      recordResult: (_) async {},
    );
    expect(await c.logout(), isFalse);
    expect(t.aborted, isTrue);
    expect(p.keyExists, isFalse);
    expect(p.trace.last, 'destroy');
  });
}
