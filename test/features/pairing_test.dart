import 'dart:async';

import 'package:assistant/core/platform/platform_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:assistant/core/config/app_config.dart';
import 'package:assistant/core/api/api_client.dart';
import 'package:assistant/core/api/api_error.dart';
import 'package:assistant/core/session/session_memory.dart';
import 'package:assistant/core/session/session_controller.dart';
import 'package:assistant/features/pairing/pairing_controller.dart';

import '../support/fakes.dart';
import '../support/fixtures.dart';

void main() {
  test('unconfigured begin never contacts signer or API', () async {
    final p = FakePlatform(), a = FakeApi(), m = SessionMemory();
    final c = PairingController(
      AppConfig.parse(''),
      a,
      p,
      m,
      SessionStore(p, m),
    );
    await c.begin();
    expect(c.phase, PairingPhase.unconfigured);
    expect(a.calls, isEmpty);
    expect(p.trace, isEmpty);
  });
  test(
    'genuine pairing remains pending; complete loss reuses key; poll >=3s',
    () async {
      var now = DateTime.utc(2026, 10, 31, 12);
      final p = FakePlatform(), a = FakeApi(), m = SessionMemory();
      var completes = 0;
      a.handler = (op, key, body) async {
        switch (op) {
          case ApiOperation.createPairing:
            return {
              'pairing_id': deviceId,
              'code': 'ABCDEFG2',
              'fingerprint': 'A' * 43,
              'expires_at': '2026-10-31T12:05:00Z',
              'poll_after_seconds': 3,
            };
          case ApiOperation.getPairing:
            return {
              'pairing_id': deviceId,
              'status': 'approved',
              'expires_at': '2026-10-31T12:05:00Z',
              'poll_after_seconds': 3,
            };
          case ApiOperation.getSelfDevice:
            return fixtureDevice();
          case ApiOperation.completePairing:
            if (completes++ == 0) throw const ApiError(0, 'TIMEOUT');
            return fixtureSession().toJson();
          default:
            throw StateError('unexpected');
        }
      };
      final c = PairingController(
        AppConfig.parse('https://mobile.example.invalid'),
        a,
        p,
        m,
        SessionStore(p, m),
        now: () => now,
      );
      await c.begin();
      expect(c.phase, PairingPhase.pending);
      expect(m.current, isNull);
      await c.complete();
      expect(completes, 0);
      await c.poll();
      expect(a.calls, hasLength(1));
      now = now.add(const Duration(seconds: 3));
      await c.poll();
      expect(c.phase, PairingPhase.approved);
      await c.complete();
      expect(c.phase, PairingPhase.approved);
      expect(m.current, isNull);
      await c.complete();
      expect(c.phase, PairingPhase.paired);
      expect(m.current, isNotNull);
      final calls = a.calls
          .where((v) => v.op == ApiOperation.completePairing)
          .toList();
      expect(calls[0].key, calls[1].key);
    },
  );
  test(
    'DEVICE_LIMIT recovery preserves approved code; expiry never auto-revokes',
    () async {
      var now = DateTime.utc(2026, 10, 31, 12);
      final p = FakePlatform(), a = FakeApi(), m = SessionMemory();
      a.handler = (op, key, body) async {
        if (op == ApiOperation.createPairing) {
          return {
            'pairing_id': deviceId,
            'code': 'ABCDEFG2',
            'fingerprint': 'A' * 43,
            'expires_at': '2026-10-31T12:05:00Z',
            'poll_after_seconds': 3,
          };
        }
        if (op == ApiOperation.getPairing) {
          return {
            'pairing_id': deviceId,
            'status': 'approved',
            'expires_at': '2026-10-31T12:05:00Z',
            'poll_after_seconds': 3,
          };
        }
        throw const ApiError(409, 'DEVICE_LIMIT');
      };
      final c = PairingController(
        AppConfig.parse('https://mobile.example.invalid'),
        a,
        p,
        m,
        SessionStore(p, m),
        now: () => now,
      );
      await c.begin();
      now = now.add(const Duration(seconds: 3));
      await c.poll();
      await c.complete();
      expect(c.phase, PairingPhase.approved);
      expect(c.message, contains('/mobile_pair ABCDEFG2'));
      expect(c.message, isNot(contains('/mobile_revoke $deviceId')));
      final firstKey = a.calls.last.key;
      await c.complete();
      expect(a.calls.last.key, firstKey);
      now = DateTime.utc(2026, 10, 31, 12, 6);
      await c.complete();
      expect(c.phase, PairingPhase.expired);
      expect(
        a.calls.where((v) => v.op == ApiOperation.revokeSelfDevice),
        isEmpty,
      );
    },
  );
  test(
    'Telegram round trip retains challenge/key and rejects prior epoch poll',
    () async {
      var now = DateTime.utc(2026, 10, 31, 12);
      final p = FakePlatform(), a = FakeApi(), m = SessionMemory();
      final oldPoll = Completer<Map<String, Object?>>();
      var polls = 0;
      a.handler = (op, key, body) async {
        if (op == ApiOperation.createPairing) {
          return {
            'pairing_id': deviceId,
            'code': 'ABCDEFG2',
            'fingerprint': 'A' * 43,
            'expires_at': '2026-10-31T12:05:00Z',
            'poll_after_seconds': 3,
          };
        }
        if (op == ApiOperation.getPairing) {
          if (polls++ == 0) return oldPoll.future;
          return {
            'pairing_id': deviceId,
            'status': 'approved',
            'expires_at': '2026-10-31T12:05:00Z',
            'poll_after_seconds': 3,
          };
        }
        if (op == ApiOperation.completePairing) {
          return fixtureSession().toJson();
        }
        if (op == ApiOperation.getSelfDevice) return fixtureDevice();
        throw StateError('unexpected');
      };
      final c = PairingController(
        AppConfig.parse('https://mobile.example.invalid'),
        a,
        p,
        m,
        SessionStore(p, m),
        now: () => now,
      );
      await c.begin();
      final challenge = c.challenge;
      now = now.add(const Duration(seconds: 3));
      final stale = c.poll();
      p.unlocked = false;
      p.epoch = 8;
      p.events.add(const NativeLockEvent(8));
      expect(c.phase, PairingPhase.locked);
      expect(m.current, isNull);
      // Genuine owner confirmation happens in Telegram while native is locked.
      now = now.add(const Duration(seconds: 10));
      p.unlocked = true;
      p.epoch = 9;
      await c.begin();
      expect(identical(c.challenge, challenge), isTrue);
      expect(c.phase, PairingPhase.pending);
      expect(m.current, isNull);
      oldPoll.complete({
        'pairing_id': deviceId,
        'status': 'approved',
        'expires_at': '2026-10-31T12:05:00Z',
        'poll_after_seconds': 3,
      });
      await stale;
      expect(c.phase, PairingPhase.pending);
      expect(m.current, isNull);
      await c.poll();
      expect(c.phase, PairingPhase.approved);
      await c.complete();
      expect(c.phase, PairingPhase.paired);
      expect(m.nativeEpoch, 9);
      expect(
        a.calls.where((v) => v.op == ApiOperation.createPairing),
        hasLength(1),
      );
      expect(p.keyExists, isTrue);
      expect(p.saved!.value['session'], fixtureSession().toJson());
      c.dispose();
    },
  );
  test('restored credential DTO alone is not fresh connected status', () async {
    final p = FakePlatform(), a = FakeApi(), m = SessionMemory();
    p.saved = PrivateCacheRead(
      {'session': fixtureSession().toJson(), 'pending_refresh': null},
      DateTime.utc(2026, 10, 31, 12),
      1,
    );
    a.handler = (op, key, body) async {
      throw const ApiError(401, 'UNAUTHORIZED');
    };
    final c = PairingController(
      AppConfig.parse('https://mobile.example.invalid'),
      a,
      p,
      m,
      SessionStore(p, m),
      now: () => DateTime.utc(2026, 10, 31, 12),
    );
    await c.begin();
    expect(c.phase, PairingPhase.revoked);
    expect(m.current, isNull);
    expect(a.calls.single.op, ApiOperation.getSelfDevice);
    c.dispose();
  });
  test(
    'old poll cleanup cannot cancel a new native credential challenge',
    () async {
      var now = DateTime.utc(2026, 10, 31, 12);
      final p = FakePlatform(), a = FakeApi(), m = SessionMemory();
      final old = Completer<Map<String, Object?>>(),
          unlock = Completer<UnlockResult>();
      a.handler = (op, key, body) async {
        if (op == ApiOperation.createPairing) {
          return {
            'pairing_id': deviceId,
            'code': 'ABCDEFG2',
            'fingerprint': 'A' * 43,
            'expires_at': '2026-10-31T12:05:00Z',
            'poll_after_seconds': 3,
          };
        }
        return old.future;
      };
      final c = PairingController(
        AppConfig.parse('https://mobile.example.invalid'),
        a,
        p,
        m,
        SessionStore(p, m),
        now: () => now,
      );
      await c.begin();
      now = now.add(const Duration(seconds: 3));
      final oldCall = c.poll();
      p.events.add(const NativeLockEvent(8));
      p.unlockHandler = () => unlock.future;
      final newCall = c.begin();
      old.complete({
        'pairing_id': deviceId,
        'status': 'approved',
        'expires_at': '2026-10-31T12:05:00Z',
        'poll_after_seconds': 3,
      });
      await oldCall;
      // Expected native Keyguard challenge pause during the newer explicit unlock.
      p.events.add(const NativeLockEvent(9));
      p.epoch = 10;
      unlock.complete(const UnlockResult(10, null));
      await newCall;
      expect(c.phase, PairingPhase.pending);
      expect(m.nativeEpoch, 10);
      expect(m.current, isNull);
      expect(
        a.calls.where((v) => v.op == ApiOperation.createPairing),
        hasLength(1),
      );
      c.dispose();
    },
  );
  test('fresh pairing cannot admit Today before actual own GETself; cold offline never becomes paired', () async {
    var now = DateTime.utc(2026, 10, 31, 12);
    final p = FakePlatform(), a = FakeApi(), m = SessionMemory();
    final self = Completer<Map<String, Object?>>();
    a.handler = (op, key, body) async {
      if (op == ApiOperation.createPairing) {
        return {
          'pairing_id': deviceId,
          'code': 'ABCDEFG2',
          'fingerprint': 'A' * 43,
          'expires_at': '2026-10-31T12:05:00Z',
          'poll_after_seconds': 3,
        };
      }
      if (op == ApiOperation.getPairing) {
        return {
          'pairing_id': deviceId,
          'status': 'approved',
          'expires_at': '2026-10-31T12:05:00Z',
          'poll_after_seconds': 3,
        };
      }
      if (op == ApiOperation.completePairing) return fixtureSession().toJson();
      if (op == ApiOperation.getSelfDevice) return self.future;
      throw StateError('Unexpected');
    };
    final c = PairingController(
      AppConfig.parse('https://synthetic.invalid'),
      a,
      p,
      m,
      SessionStore(p, m),
      now: () => now,
    );
    await c.begin();
    now = now.add(const Duration(seconds: 3));
    await c.poll();
    final completion = c.complete();
    await Future<void>.delayed(Duration.zero);
    expect(m.current, isNotNull);
    expect(c.phase, isNot(PairingPhase.paired));
    expect(a.calls.last.op, ApiOperation.getSelfDevice);
    self.completeError(const ApiError(0, 'TRANSPORT_UNAVAILABLE'));
    await completion;
    expect(c.phase, isNot(PairingPhase.paired));
    c.dispose();
    final restored = PairingController(
      AppConfig.parse('https://synthetic.invalid'),
      a,
      p,
      m,
      SessionStore(p, m),
      now: () => now,
    );
    a.handler = (op, key, body) async =>
        throw const ApiError(0, 'TRANSPORT_UNAVAILABLE');
    p.epoch = 9;
    await restored.begin();
    expect(restored.phase, isNot(PairingPhase.paired));
    expect(restored.message, contains('нужно проверить подключение'));
    restored.dispose();
  });
}
