import 'package:assistant/core/cache/domain_cache.dart';
import 'package:assistant/core/platform/platform_gateway.dart';
import 'package:assistant/core/session/session_memory.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/domain_fakes.dart';
import '../support/fixtures.dart';

class RacingDomain extends FakeDomainPlatform {
  int active = 0, maxActive = 0, attempts = 0;
  bool conflict = true;
  final List<Map<String, Object?>> seen = [];
  @override
  Future<void> writePrivateCache(PrivateCacheWrite v) async {
    active++;
    if (active > maxActive) maxActive = active;
    attempts++;
    seen.add(v.value);
    await Future<void>.delayed(Duration.zero);
    active--;
    if (conflict) {
      conflict = false;
      revision++;
      throw PlatformException(code: 'DOMAIN_REVISION_CONFLICT');
    }
    return super.writePrivateCache(v);
  }
}

void main() {
  test('single writer retries only original immutable patch and keeps session slot separate', () async {
    final p = RacingDomain(),
        m = SessionMemory()..adopt(UnlockResult(7, fixtureSession()));
    p.saved = PrivateCacheRead(
      {'session': fixtureSession().toJson(), 'pending_refresh': null},
      DateTime.utc(2026),
      11,
    );
    final cache = DomainCache(p, p, m);
    final first = DomainCache.patch(invalidate: []);
    final a = cache.transact(7, first);
    (first['invalidate_resources']! as List).add({
      'kind': 'task',
      'id': '11111111-1111-4111-8111-111111111111',
    });
    final b = cache.transact(7, DomainCache.patch());
    await Future.wait([a, b]);
    expect(p.maxActive, 1);
    expect(p.attempts, 3);
    expect(
      p.seen.every((patch) => (patch['invalidate_resources']! as List).isEmpty),
      true,
    );
    expect(p.saved!.revision, 11);
    expect(p.saved!.value['pending_refresh'], isNull);
    expect(p.revision, 3);
  });
  test(
    'epoch change rejects queued writer instead of restoring stale state',
    () async {
      final p = RacingDomain(),
          m = SessionMemory()..adopt(UnlockResult(7, fixtureSession()));
      final cache = DomainCache(p, p, m);
      m.lock(const NativeLockEvent(8));
      await expectLater(
        cache.transact(7, DomainCache.patch()),
        throwsStateError,
      );
      expect(p.attempts, 0);
    },
  );
}
