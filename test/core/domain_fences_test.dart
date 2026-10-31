import 'dart:async';

import 'package:assistant/core/api/api_client.dart';
import 'package:assistant/core/platform/platform_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/today_harness.dart';
import '../support/domain_fixtures.dart';

void main() {
  test(
    'short byte-bounded page follows actual opaque cursor and real total',
    () async {
      final h = TodayHarness();
      await h.repo.verifyDevice();
      h.t.handler = (r) async => wire({
        ...dashboardJson(),
        'next_cursor': r.uri.queryParameters['cursor'] == null
            ? 'opaque'
            : null,
        'tasks': r.uri.queryParameters['cursor'] == null
            ? [taskJson()]
            : [
                {...taskJson(), 'id': reminderId, 'title': 'Вторая задача'},
              ],
      });
      await h.c.refresh();
      expect(h.c.tasks.length, 1);
      expect(h.c.dashboard!.totalOpenCount, 47);
      await h.c.loadNextPage();
      expect(h.c.tasks.length, 2);
      expect(h.c.dashboard!.totalOpenCount, 47);
      expect(h.t.requests.last.uri.queryParameters['cursor'], 'opaque');
      h.dispose();
    },
  );
  test(
    'old dashboard callback after native epoch change cannot install a view',
    () async {
      final h = TodayHarness();
      await h.repo.verifyDevice();
      final delayed = Completer<ApiResponse>();
      h.t.handler = (_) => delayed.future;
      final refresh = h.c.refresh();
      await Future<void>.delayed(Duration.zero);
      h.m.lock(const NativeLockEvent(8));
      delayed.complete(wire(dashboardJson()));
      await refresh;
      expect(h.c.dashboard, isNull);
      expect(h.c.tasks, isEmpty);
      expect(h.p.commits.where((s) => s == 'getDashboard'), isEmpty);
      h.dispose();
    },
  );
}
