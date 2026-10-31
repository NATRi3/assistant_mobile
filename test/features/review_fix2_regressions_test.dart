// R3b/R5: permanent regressions adapted from independent fix1 review probes.
import 'dart:async';

import 'package:assistant/core/api/api_client.dart';
import 'package:assistant/core/api/api_error.dart';
import 'package:assistant/features/today/today_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/today_harness.dart';
import '../support/domain_fixtures.dart';

Map<String, Object?> scopePage(String change) => {
  ...dashboardJson(),
  if (change == 'context') 'context_epoch': 2,
  if (change == 'policy')
    'preferences': {
      ...dashboardJson()['preferences']! as Map<String, Object?>,
      'quiet_hours': {
        ...((dashboardJson()['preferences']! as Map)['quiet_hours']!
            as Map<String, Object?>),
        'owner_policy_version': 2,
      },
    },
};
void main() {
  for (final variant in ['version', 'warning', 'terminal']) {
    test(
      'R3b accepted $variant Reminder fences older Dashboard and permits later read',
      () async {
        final h = TodayHarness();
        await h.enter();
        final old = Completer<ApiResponse>();
        final detail = {
          ...reminderJson(),
          if (variant != 'warning') 'version': 5,
          if (variant == 'version') 'due_at': '2026-10-31T14:00:00Z',
          if (variant == 'warning') 'source_warning': true,
          if (variant == 'terminal') ...{
            'status': 'cancelled',
            'active': false,
            'permitted_actions': [],
          },
        };
        h.t.handler = (r) => r.uri.path.endsWith('/dashboard')
            ? old.future
            : Future.value(wire(detail));
        final reading = h.c.refresh();
        await Future<void>.delayed(Duration.zero);
        await h.c.openReminder(reminderId);
        expect(h.c.dashboard!.nearestReminder, isNull);
        final commits = h.p.commits.length;
        old.complete(wire(dashboardJson()));
        await reading;
        expect(h.c.dashboard?.nearestReminder, isNull);
        expect(h.p.commits.length, commits);
        expect(h.m.unlocked, true);
        expect(h.t.aborted, false);
        final latest = variant == 'terminal'
            ? null
            : {
                'id': reminderId,
                'due_at': detail['due_at'],
                'version': detail['version'],
                'source_warning': detail['source_warning'],
              };
        h.t.handler = (_) async =>
            wire({...dashboardJson(), 'nearest_reminder': latest});
        await h.c.refresh();
        expect(h.c.phase, TodayPhase.fresh);
        expect(h.c.dashboard!.nearestReminder?.toJson(), latest);
        h.dispose();
      },
    );
  }
  for (final change in ['context', 'policy']) {
    for (final work in ['command', 'reconcile', 'retry']) {
      test(
        'R5 $change during $work releases obsolete busy without resending',
        () async {
          final h = TodayHarness();
          await h.enter();
          if (work != 'command') {
            h.t.handler = (r) async {
              if (r.method == 'POST') throw const ApiError(0, 'TIMEOUT');
              return h.defaultResponse(r);
            };
            await h.c.completeTask(h.c.selectedTask!);
            if (work == 'retry') {
              h.t.handler = (r) async => r.uri.path.contains('/mutations/')
                  ? wire({'code': 'NOT_FOUND'}, status: 404)
                  : h.defaultResponse(r);
              await h.c.reconcile(h.c.pending.single);
            }
          }
          final delayed = Completer<ApiResponse>();
          h.t.handler = (r) {
            if ((work == 'reconcile' && r.uri.path.contains('/mutations/')) ||
                (work != 'reconcile' && r.method == 'POST')) {
              return delayed.future;
            }
            if (r.uri.path.endsWith('/dashboard')) {
              return Future.value(wire(scopePage(change)));
            }
            return Future.value(h.defaultResponse(r));
          };
          final original = work == 'command' ? null : h.c.pending.single;
          final future = work == 'command'
              ? h.c.completeTask(h.c.selectedTask!)
              : work == 'reconcile'
              ? h.c.reconcile(original!)
              : h.c.retryOriginal(original!);
          await Future<void>.delayed(Duration.zero);
          expect(h.c.busy, true);
          final posts = h.t.requests.where((r) => r.method == 'POST').length;
          await h.c.refresh();
          expect(
            h.c.busy,
            false,
            reason: 'Scope invalidation releases obsolete ownership while retaining its immutable metadata',
          );
          delayed.complete(wire(receiptJson()));
          await future;
          expect(h.c.busy, false);
          expect(h.c.pending.single.unresolved, true);
          expect(h.t.requests.where((r) => r.method == 'POST').length, posts);
          h.dispose();
        },
      );
    }
  }
  test(
    'R5 old completion cannot clear newer reconciliation ownership',
    () async {
      final h = TodayHarness();
      await h.enter();
      final post = Completer<ApiResponse>(), lookup = Completer<ApiResponse>();
      var confirmed = false;
      h.t.handler = (r) {
        if (r.method == 'POST') return post.future;
        if (r.uri.path.contains('/mutations/')) return lookup.future;
        if (r.uri.path.endsWith('/dashboard')) {
          return Future.value(
            wire({
              ...scopePage('context'),
              if (confirmed) 'tasks': [],
              if (confirmed) 'total_open_count': 0,
            }),
          );
        }
        return Future.value(
          wire(
            confirmed
                ? {
                    ...taskJson(),
                    'version': 5,
                    'status': 'done',
                    'permitted_actions': [],
                  }
                : taskJson(),
          ),
        );
      };
      final old = h.c.completeTask(h.c.selectedTask!);
      await Future<void>.delayed(Duration.zero);
      await h.c.refresh();
      final newer = h.c.reconcile(h.c.pending.single);
      await Future<void>.delayed(Duration.zero);
      expect(h.c.busy, true);
      post.complete(wire(receiptJson()));
      await old;
      expect(
        h.c.busy,
        true,
        reason: 'An obsolete operation does not own this busy state',
      );
      confirmed = true;
      lookup.complete(wire(receiptJson()));
      await newer;
      expect(h.c.busy, false);
      expect(h.t.requests.where((r) => r.method == 'POST').length, 1);
      h.dispose();
    },
  );
}
