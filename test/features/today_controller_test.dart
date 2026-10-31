import 'dart:convert';

import 'package:assistant/core/api/api_client.dart';
import 'package:assistant/core/cache/domain_cache.dart';
import 'package:assistant/core/config/app_config.dart';
import 'package:assistant/core/platform/platform_gateway.dart';
import 'package:assistant/core/session/session_memory.dart';
import 'package:assistant/features/today/today_repository.dart';
import 'package:assistant/features/today/today_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/domain_fakes.dart';
import '../support/domain_fixtures.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';

ApiResponse response(Object body, {int status = 200}) => ApiResponse(status, {
  'date': 'Sat, 31 Oct 2026 12:00:00 GMT',
}, utf8.encode(jsonEncode(body)));
void main() {
  test('actual dashboard body drives real count and distinct summary; malformed 200 is never empty', () async {
    final p = FakeDomainPlatform(),
        m = SessionMemory()..adopt(UnlockResult(7, fixtureSession())),
        t = FakeTransport();
    final api = ApiClient(
          AppConfig.parse('https://synthetic.invalid'),
          p,
          t,
          m,
        ),
        cache = DomainCache(p, p, m);
    final repo = ApiTodayRepository(api, cache, p);
    t.handler = (r) async => response(
      r.uri.path.endsWith('self') ? fixtureDevice() : dashboardJson(),
    );
    await repo.verifyDevice();
    final c = TodayController(repo, cache, m);
    await c.refresh();
    expect(c.phase, TodayPhase.fresh);
    expect(c.dashboard!.totalOpenCount, 47);
    expect(c.tasks.single.id, taskId);
    expect(c.dashboard!.nearestReminder!.id, reminderId);
    t.handler = (r) async => response({'tasks': []});
    await c.refresh();
    expect(c.phase, isNot(TodayPhase.empty));
    expect(p.commits.where((x) => x == 'getDashboard'), hasLength(1));
    c.dispose();
  });
}
