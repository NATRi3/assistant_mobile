import 'package:flutter_test/flutter_test.dart';
import 'package:assistant/core/platform/platform_gateway.dart';
import 'package:assistant/core/session/session_memory.dart';

import '../support/fixtures.dart';

void main() {
  test('lock drops credentials and rejects delayed unlock from old epoch', () {
    final dto = fixtureSession();
    final m = SessionMemory();
    m.adopt(UnlockResult(7, dto));
    expect(m.current, isNotNull);
    m.lock(const NativeLockEvent(8));
    expect(m.current, isNull);
    expect(m.unlocked, isFalse);
    expect(m.nativeEpoch, 8);
    m.adopt(UnlockResult(7, dto));
    expect(m.current, isNull);
    expect(dto.toString(), isNot(contains(dto.accessToken)));
    expect(dto.toString(), isNot(contains(dto.refreshToken)));
    expect(dto.accessExpiresAt, DateTime.utc(2026, 10, 31, 12, 10));
  });
  test('session rejects decimal TTL despite numeric equality', () {
    expect(
      () => SessionDto.fromJson({
        ...fixtureSession().toJson(),
        'expires_in': 600.0,
      }),
      throwsFormatException,
    );
  });
  test('session rejects unknown fields and non-UUID identity', () {
    expect(
      () => SessionDto.fromJson({...fixtureSession().toJson(), 'owner_id': 1}),
      throwsFormatException,
    );
    expect(
      () => SessionDto.fromJson({
        ...fixtureSession().toJson(),
        'device_id': 'other',
      }),
      throwsFormatException,
    );
  });
}
