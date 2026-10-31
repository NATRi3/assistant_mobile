import 'package:assistant/core/platform/domain_platform.dart';

// R1-R3 initial probes adapted with attribution from independent Task2 review.
import 'dart:async';

import 'package:assistant/core/api/api_client.dart';
import 'package:assistant/features/today/today_controller.dart';
import 'package:assistant/core/api/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/today_harness.dart';
import '../support/domain_fixtures.dart';

void main() {
  test(
    'R1 known pause survives later503, detail navigation and a new controller',
    () async {
      final h = TodayHarness();
      await h.enter();
      h.t.handler = (_) async => wire({'code': 'OWNER_PAUSED'}, status: 403);
      await h.c.refresh();
      expect(h.c.phase, TodayPhase.paused);
      h.t.handler = (_) async => wire({'code': 'UNAVAILABLE'}, status: 503);
      await h.c.refresh();
      expect(h.c.tasks, isEmpty);
      expect((await h.cache.read()).dashboard, isNull);
      final other = TodayController(h.repo, h.cache, h.m);
      await other.openTask(taskId);
      expect(other.selectedTask, isNull);
      await other.refresh();
      expect(other.dashboard, isNull);
      other.dispose();
      h.dispose();
    },
  );
  for (final size in [51, 200]) {
    test('R2 native aggregate $size is distinct from a wire page', () async {
      final h = TodayHarness();
      await h.enter();
      final items = List.generate(
        size,
        (i) => {
          ...taskJson(),
          'id':
              '${i.toRadixString(16).padLeft(8, '0')}-1111-4111-8111-111111111111',
          'title': size == 200 ? 'x' * 4096 : 'Synthetic',
        },
      );
      h.p.dashboard = {
        ...dashboardJson(),
        'tasks': items,
        'total_open_count': 237,
      };
      for (final item in items) {
        h.p.tasks[item['id']! as String] = item;
      }
      h.t.handler = (_) async => wire({'code': 'UNAVAILABLE'}, status: 503);
      await h.c.refresh();
      expect(h.c.phase, TodayPhase.offline);
      expect(h.c.tasks.length, size);
      expect(h.c.dashboard!.totalOpenCount, 237);
      h.dispose();
    });
  }
  test(
    'R3 detail source scrub replaces all Task references and derived fields',
    () async {
      final h = TodayHarness();
      await h.enter();
      h.t.handler = (_) async => wire({
        ...taskJson(),
        'version': 4,
        'title': '',
        'source_warning': true,
        'permitted_actions': [],
      });
      await h.c.openTask(taskId);
      expect(h.c.selectedTask!.title, '');
      expect(h.c.tasks.single.title, '');
      expect(h.c.dashboard!.tasks.single.title, '');
      expect(h.c.lastSync, '2026-10-31T12:00:00Z');
      h.dispose();
    },
  );
  test(
    'R3 terminal and same-version policy results never leave old parent copies',
    () async {
      final h = TodayHarness();
      await h.enter();
      h.t.handler = (_) async => wire({
        ...taskJson(),
        'source_warning': true,
        'permitted_actions': [],
      });
      await h.c.openTask(taskId);
      expect(h.c.tasks.single.sourceWarning, true);
      expect(h.c.dashboard!.tasks.single.canComplete, false);
      h.t.handler = (_) async => wire({
        ...taskJson(),
        'version': 4,
        'status': 'done',
        'permitted_actions': [],
      });
      await h.c.openTask(taskId);
      expect(h.c.tasks, isEmpty);
      expect(h.c.dashboard!.tasks, isEmpty);
      expect(h.c.dashboard!.totalOpenCount, 47);
      expect(h.c.phase, TodayPhase.stale);
      h.dispose();
    },
  );
  test('R3 Reminder detail invalidates an obsolete nearest summary', () async {
    final h = TodayHarness();
    await h.enter();
    h.t.handler = (_) async => wire({
      ...reminderJson(),
      'version': 5,
      'due_at': '2026-10-31T14:00:00Z',
    });
    await h.c.openReminder(reminderId);
    expect(h.c.dashboard!.nearestReminder, isNull);
    expect(h.c.phase, TodayPhase.stale);
    h.dispose();
  });
  test(
    'R4 superseded detail drops before commit without aborting healthy HTTP',
    () async {
      final h = TodayHarness();
      await h.enter();
      final detail = Completer<ApiResponse>();
      h.t.handler = (r) => r.uri.path.contains('/tasks/')
          ? detail.future
          : Future.value(h.defaultResponse(r));
      final old = h.c.openTask(taskId);
      await Future<void>.delayed(Duration.zero);
      final before = h.p.commits.length;
      await h.c.refresh();
      detail.complete(
        wire({...taskJson(), 'version': 4, 'title': 'old callback'}),
      );
      await old;
      expect(h.p.commits.skip(before).where((x) => x == 'getTask'), isEmpty);
      expect(h.c.tasks.single.title, isNot('old callback'));
      expect(h.m.unlocked, true);
      expect(h.t.aborted, false);
      h.dispose();
    },
  );
  test('R1 in-flight valid detail cannot cross denial and reopening needs online permission', () async {
    final h = TodayHarness();
    await h.enter();
    final delayed = Completer<ApiResponse>();
    h.t.handler = (r) => r.uri.path.contains('/tasks/')
        ? delayed.future
        : Future.value(wire({'code': 'OWNER_PAUSED'}, status: 403));
    final reading = h.c.openTask(taskId);
    await Future<void>.delayed(Duration.zero);
    await h.c.refresh();
    final commits = h.p.commits.length;
    delayed.complete(
      wire({...taskJson(), 'version': 4, 'title': 'must stay hidden'}),
    );
    await reading;
    expect(h.c.selectedTask, isNull);
    expect(h.p.commits.length, commits);
    expect(h.c.pending, isEmpty);
    // Own-device verification alone cannot restore saved bodies after a known pause.
    h.t.handler = (r) async => h.defaultResponse(r);
    await h.repo.verifyDevice();
    expect((await h.cache.read()).dashboard, isNull);
    h.t.handler = (_) async => wire({'code': 'UNAVAILABLE'}, status: 503);
    await h.c.refresh();
    expect(h.c.dashboard, isNull);
    h.t.handler = (r) async => h.defaultResponse(r);
    await h.c.refresh();
    expect(h.c.phase, TodayPhase.fresh);
    h.dispose();
  });
  test('R2 unchanged wire limit rejects51 while cache rejects201 and oversized whole view', () async {
    final h = TodayHarness();
    await h.enter();
    final items = List.generate(
      51,
      (i) => {
        ...taskJson(),
        'id':
            '${i.toRadixString(16).padLeft(8, '0')}-1111-4111-8111-111111111111',
      },
    );
    h.t.handler = (_) async => wire({...dashboardJson(), 'tasks': items});
    final count = h.p.commits.length;
    await h.c.refresh();
    expect(h.p.commits.length, count);
    expect(
      () => Dashboard.fromCacheJson({
        ...dashboardJson(),
        'tasks': List.generate(
          201,
          (i) => {
            ...taskJson(),
            'id':
                '${i.toRadixString(16).padLeft(8, '0')}-1111-4111-8111-111111111111',
          },
        ),
      }),
      throwsFormatException,
    );
    expect(
      () => Dashboard.fromCacheJson({
        ...dashboardJson(),
        'tasks': List.generate(
          200,
          (i) => {
            ...taskJson(),
            'title': '\u0001' * 4096,
            'id':
                '${i.toRadixString(16).padLeft(8, '0')}-1111-4111-8111-111111111111',
          },
        ),
      }),
      throwsFormatException,
    );
    h.dispose();
  });
  test('R3 Dashboard updates the selected copy; older callbacks cannot undo a detail scrub', () async {
    final h = TodayHarness();
    await h.enter();
    final page = Completer<ApiResponse>();
    h.t.handler = (r) => r.uri.path.endsWith('/dashboard')
        ? page.future
        : Future.value(wire({...taskJson(), 'version': 4, 'title': ''}));
    final refresh = h.c.refresh();
    await Future<void>.delayed(Duration.zero);
    await h.c.openTask(taskId);
    page.complete(wire(dashboardJson()));
    await refresh;
    expect(h.c.tasks.single.title, '');
    expect(h.c.dashboard!.tasks.single.title, '');
    h.t.handler = (_) async => wire({
      ...dashboardJson(),
      'tasks': [
        {...taskJson(), 'version': 5, 'title': 'current'},
      ],
    });
    await h.c.refresh();
    expect(h.c.selectedTask!.title, 'current');
    h.dispose();
  });
  test(
    'R4 overlapping refresh does not abort or resend an unrelated POST',
    () async {
      final h = TodayHarness();
      await h.enter();
      final post = Completer<ApiResponse>();
      final page = Completer<ApiResponse>();
      var pages = 0;
      h.t.handler = (r) {
        if (r.method == 'POST') return post.future;
        if (r.uri.path.endsWith('/dashboard') && pages++ == 0) {
          return page.future;
        }
        return Future.value(h.defaultResponse(r));
      };
      final action = h.c.completeTask(h.c.selectedTask!);
      await Future<void>.delayed(Duration.zero);
      final old = h.c.refresh();
      await Future<void>.delayed(Duration.zero);
      await h.c.refresh();
      page.complete(wire(dashboardJson()));
      await old;
      expect(h.t.aborted, false);
      expect(h.m.unlocked, true);
      expect(h.t.requests.where((r) => r.method == 'POST').length, 1);
      post.complete(wire(receiptJson()));
      await action;
      expect(h.t.aborted, false);
      expect(h.t.requests.where((r) => r.method == 'POST').length, 1);
      h.dispose();
    },
  );
  test(
    'R1 a delayed eligible fallback frame cannot publish after shared denial',
    () async {
      final h = TodayHarness();
      await h.enter();
      final delayed = Completer<DomainFrame>(), started = Completer<void>();
      var reads = 0;
      h.p.frameHandler = (frame) {
        if (++reads == 2) {
          started.complete();
          return delayed.future;
        }
        return Future.value(frame);
      };
      h.t.handler = (_) async => wire({'code': 'UNAVAILABLE'}, status: 503);
      final refreshing = h.c.refresh();
      await started.future;
      h.t.handler = (_) async => wire({'code': 'OWNER_PAUSED'}, status: 403);
      await expectLater(
        h.api.call(ApiOperation.getTask, resourceId: taskId),
        throwsA(isA<Exception>()),
      );
      delayed.complete(
        DomainFrame.fromJson({
          'revision': h.p.revision,
          'needs_sync': false,
          'dashboard': dashboardJson(),
          'tasks_by_id': {taskId: taskJson()},
          'reminders_by_id': {},
          'pending_actions_by_key': {},
          'scope': {'context_epoch': 1},
          'last_sync': '2026-10-31T12:00:00Z',
        }),
      );
      await refreshing;
      expect(h.c.phase, TodayPhase.paused);
      expect(h.c.dashboard, isNull);
      expect(h.c.tasks, isEmpty);
      h.dispose();
    },
  );
  test(
    'R4 older eligibility read cannot overtake a newer refresh generation',
    () async {
      final h = TodayHarness();
      await h.enter();
      final delayed = Completer<DomainFrame>(), started = Completer<void>();
      var first = true;
      h.p.frameHandler = (frame) {
        if (first) {
          first = false;
          started.complete();
          return delayed.future;
        }
        return Future.value(frame);
      };
      final old = h.c.refresh();
      await started.future;
      final snapshot = await h.p.readDomainFrame();
      await h.c.refresh();
      final before = h.t.requests.length;
      delayed.complete(snapshot);
      await old;
      expect(h.t.requests.length, before);
      expect(h.m.unlocked, true);
      expect(h.c.phase, TodayPhase.fresh);
      h.dispose();
    },
  );
  test('R3 confirmed terminal detail preserves an already authoritative empty Dashboard', () async {
    final h = TodayHarness();
    await h.enter();
    var posted = false;
    h.t.handler = (r) async {
      if (r.method == 'POST') {
        posted = true;
        return wire(receiptJson());
      }
      if (posted && r.uri.path.endsWith('/dashboard')) {
        return wire({...dashboardJson(), 'tasks': [], 'total_open_count': 0});
      }
      if (posted && r.uri.path.contains('/tasks/')) {
        return wire({
          ...taskJson(),
          'version': 5,
          'status': 'done',
          'permitted_actions': [],
        });
      }
      return h.defaultResponse(r);
    };
    await h.c.completeTask(h.c.selectedTask!);
    expect(h.c.phase, TodayPhase.empty);
    expect(h.c.detailPhase, TodayPhase.fresh);
    expect(h.c.selectedTask!.status, 'done');
    expect(h.c.detailMessage, 'Команда выполнена.');
    h.dispose();
  });
}
