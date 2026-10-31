import 'dart:convert';

import 'package:assistant/features/today/today_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/today_harness.dart';
import '../support/domain_fixtures.dart';

void main() {
  test('reminder tap only reads; explicit snooze sends exact original body and conflict remains honest', () async {
    final h = TodayHarness();
    await h.enter();
    await h.c.openReminder(reminderId);
    expect(h.t.requests.where((r) => r.method == 'POST'), isEmpty);
    h.t.handler = (r) async => r.method == 'POST'
        ? wire({'code': 'STATE_CONFLICT'}, status: 409)
        : h.defaultResponse(r);
    await h.c.snoozeReminder(h.c.selectedReminder!);
    expect(h.c.detailPhase, TodayPhase.conflict);
    expect(
      h.t.requests
          .where(
            (r) => r.method == 'GET' && r.uri.path.endsWith('/$reminderId'),
          )
          .length,
      2,
    );
    expect(h.c.selectedReminder!.dueAt, '2026-10-31T13:00:00Z');
    final request = h.t.requests.singleWhere((r) => r.method == 'POST');
    expect(jsonDecode(utf8.decode(request.body!)), {
      'expected_version': 4,
      'delay_minutes': 10,
    });
    h.t.handler = (r) async => r.uri.path.contains('/reminders/')
        ? wire({
            ...reminderJson(),
            'version': 5,
            'status': 'cancelled',
            'active': false,
            'permitted_actions': [],
          })
        : h.defaultResponse(r);
    await h.c.openReminder(reminderId);
    expect(h.c.selectedReminder!.canSnooze, false);
    await h.c.snoozeReminder(h.c.selectedReminder!);
    expect(h.t.requests.where((r) => r.method == 'POST').length, 1);
    h.dispose();
  });
  test(
    '404 detail hides the object instead of an empty successful detail',
    () async {
      final h = TodayHarness();
      await h.enter();
      h.t.handler = (r) async => wire({'code': 'NOT_FOUND'}, status: 404);
      await h.c.openTask(taskId);
      expect(h.c.selectedTask, isNull);
      expect(h.c.detailPhase, TodayPhase.unavailable);
      h.dispose();
    },
  );
}
