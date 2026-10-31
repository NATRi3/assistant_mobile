import 'dart:convert';

import 'package:assistant/core/api/api_client.dart';
import 'package:assistant/core/cache/domain_cache.dart';
import 'package:assistant/core/config/app_config.dart';
import 'package:assistant/core/platform/platform_gateway.dart';
import 'package:assistant/core/session/session_memory.dart';
import 'package:assistant/core/recovery/action_recovery.dart';
import 'package:assistant/features/today/today_repository.dart';
import 'package:assistant/features/today/today_controller.dart';

import 'domain_fakes.dart';
import 'domain_fixtures.dart';
import 'fakes.dart';
import 'fixtures.dart';

ApiResponse wire(Object body, {int status = 200}) => ApiResponse(status, {
  'date': 'Sat, 31 Oct 2026 12:00:00 GMT',
}, utf8.encode(jsonEncode(body)));

class TodayHarness {
  final p = FakeDomainPlatform(),
      m = SessionMemory()..adopt(UnlockResult(7, fixtureSession())),
      t = FakeTransport();
  late final ApiClient api;
  late final DomainCache cache;
  late final ApiTodayRepository repo;
  late final TodayController c;
  TodayHarness() {
    api = ApiClient(AppConfig.parse('https://synthetic.invalid'), p, t, m);
    cache = DomainCache(p, p, m);
    repo = ApiTodayRepository(api, cache, p);
    c = TodayController(
      repo,
      cache,
      m,
      recovery: ActionRecovery(cache, m, 'https://synthetic.invalid'),
    );
    t.handler = (r) async => defaultResponse(r);
  }
  ApiResponse defaultResponse(ApiRequest r) {
    if (r.uri.path.endsWith('self')) return wire(fixtureDevice());
    if (r.uri.path.endsWith('dashboard')) return wire(dashboardJson());
    if (r.method == 'POST') return wire(receiptJson());
    if (r.uri.path.contains('/mutations/')) return wire(receiptJson());
    if (r.uri.path.contains('/reminders/')) return wire(reminderJson());
    return wire(taskJson());
  }

  Future<void> enter() async {
    await repo.verifyDevice();
    await c.refresh();
    await c.openTask(taskId);
  }

  void dispose() {
    c.dispose();
    repo.dispose();
    m.dispose();
    p.events.close();
  }
}
