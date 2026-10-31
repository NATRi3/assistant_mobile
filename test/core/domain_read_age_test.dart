import 'package:assistant/core/api/api_client.dart';
import 'package:assistant/features/today/today_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/today_harness.dart';
import '../support/domain_fixtures.dart';

void main() {
  test('real API malformed statuses and absent Date never obtain a native admission', () async {
    for (final status in [201, 202, 204, 503]) {
      final h = TodayHarness();
      await h.repo.verifyDevice();
      h.t.handler = (r) async => wire({}, status: status);
      await h.c.refresh();
      expect(h.c.phase, TodayPhase.error);
      expect(h.p.commits.where((s) => s == 'getDashboard'), isEmpty);
      h.dispose();
    }
    final h = TodayHarness();
    await h.repo.verifyDevice();
    h.t.handler = (r) async {
      final result = wire(dashboardJson());
      return ApiResponse(200, {}, result.body);
    };
    await h.c.refresh();
    expect(h.c.phase, TodayPhase.error);
    expect(h.p.commits.where((s) => s == 'getDashboard'), isEmpty);
    h.dispose();
  });
  test('valid cached data is read-only on read failure; known401/403 never fallback', () async {
    for (final status in [503, 401, 403]) {
      final h = TodayHarness();
      await h.enter();
      h.t.handler = (r) async => wire({
        'code': status == 403 ? 'OWNER_PAUSED' : 'UNAVAILABLE',
      }, status: status);
      await h.c.refresh();
      expect(
        h.c.phase,
        status == 503
            ? TodayPhase.offline
            : status == 401
            ? TodayPhase.locked
            : TodayPhase.paused,
      );
      if (status != 503) {
        expect(h.c.tasks, isEmpty);
        expect(h.c.dashboard, isNull);
      } else {
        expect(h.c.online, false);
      }
      h.dispose();
    }
  });
}
