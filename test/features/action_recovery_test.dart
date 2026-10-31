import 'dart:async';
import 'dart:convert';

import 'package:assistant/core/api/api_client.dart';
import 'package:assistant/core/api/api_error.dart';
import 'package:assistant/core/platform/platform_gateway.dart';
import 'package:assistant/features/today/today_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/today_harness.dart';
import '../support/domain_fixtures.dart';

void main() {
  test('durable preparation precedes one POST; response lost then GET receipt confirms', () async {
    final h = TodayHarness();
    await h.enter();
    var posts = 0;
    h.t.handler = (r) async {
      if (r.method == 'POST') {
        expect(h.p.pending.length, 1);
        expect(
          h.p.trace.indexOf('domain-persist'),
          lessThan(h.p.trace.indexOf('sign:completeTask')),
        );
        posts++;
        throw const ApiError(0, 'TRANSPORT_UNAVAILABLE');
      }
      return h.defaultResponse(r);
    };
    await h.c.completeTask(h.c.selectedTask!);
    expect(h.c.detailPhase, TodayPhase.unknown);
    expect(h.c.pending.single.state, 'unknown');
    expect(posts, 1);
    final original = h.c.pending.single;
    await h.c.reconcile(original);
    expect(posts, 1);
    expect(h.c.pending.single.state, 'confirmed');
    expect(
      h.t.requests
          .where((r) => r.uri.path.endsWith('/${original.actionKey}'))
          .length,
      1,
    );
    h.dispose();
  });
  test('404 never resends; explicit original retry preserves key route version body and ambiguity on409', () async {
    final h = TodayHarness();
    await h.enter();
    var attempts = 0;
    h.t.handler = (r) async {
      if (r.method == 'POST') {
        attempts++;
        if (attempts == 1) throw const ApiError(0, 'TIMEOUT');
        return wire({'code': 'VERSION_CONFLICT'}, status: 409);
      }
      if (r.uri.path.contains('/mutations/')) {
        return wire({'code': 'NOT_FOUND'}, status: 404);
      }
      return h.defaultResponse(r);
    };
    await h.c.completeTask(h.c.selectedTask!);
    final original = h.c.pending.single;
    await h.c.reconcile(original);
    expect(attempts, 1);
    expect(h.c.canRetry(original), true);
    await h.c.retryOriginal(original);
    expect(attempts, 2);
    expect(h.c.pending.single.state, 'unknown');
    final posts = h.t.requests.where((r) => r.method == 'POST').toList();
    expect(posts[0].uri, posts[1].uri);
    expect(
      posts[0].headers['Idempotency-Key'],
      posts[1].headers['Idempotency-Key'],
    );
    expect(utf8.decode(posts[0].body!), utf8.decode(posts[1].body!));
    expect(jsonDecode(utf8.decode(posts[1].body!)), {'expected_version': 3});
    h.dispose();
  });
  test(
    'admission failure sends zero commands and duplicate submit is blocked',
    () async {
      final h = TodayHarness();
      await h.enter();
      h.p.failAdmission = true;
      await h.c.completeTask(h.c.selectedTask!);
      expect(h.t.requests.where((r) => r.method == 'POST'), isEmpty);
      h.p.failAdmission = false;
      await h.c.openTask(taskId);
      final delayed = Completer<ApiResponse>();
      h.t.handler = (r) => r.method == 'POST'
          ? delayed.future
          : Future.value(h.defaultResponse(r));
      final first = h.c.completeTask(h.c.selectedTask!);
      await Future<void>.delayed(Duration.zero);
      await h.c.completeTask(h.c.selectedTask!);
      expect(h.t.requests.where((r) => r.method == 'POST').length, 1);
      delayed.completeError(const ApiError(0, 'TIMEOUT'));
      await first;
      h.dispose();
    },
  );
  test('wrong success status or malformed receipt remains unknown; confirmed refetch failure is honest', () async {
    for (final mode in ['status', 'malformed', 'refetch']) {
      final h = TodayHarness();
      await h.enter();
      var posted = false;
      h.t.handler = (r) async {
        if (r.method == 'POST') {
          posted = true;
          return mode == 'status'
              ? wire({}, status: 204)
              : mode == 'malformed'
              ? wire({'resource_id': taskId})
              : wire(receiptJson());
        }
        if (posted && mode == 'refetch') {
          return wire({'code': 'UNAVAILABLE'}, status: 503);
        }
        return h.defaultResponse(r);
      };
      await h.c.completeTask(h.c.selectedTask!);
      expect(
        h.c.detailPhase,
        mode == 'refetch' ? TodayPhase.stale : TodayPhase.unknown,
      );
      if (mode == 'refetch') {
        expect(
          h.c.detailMessage,
          contains('Команда выполнена; обновить данные пока не удалось'),
        );
        expect(h.c.selectedTask, isNull);
      } else {
        expect(h.c.pending.single.state, 'unknown');
      }
      h.dispose();
    }
  });
  test(
    'lock during POST clears private references before late receipt',
    () async {
      final h = TodayHarness();
      await h.enter();
      final delayed = Completer<ApiResponse>();
      h.t.handler = (r) => r.method == 'POST'
          ? delayed.future
          : Future.value(h.defaultResponse(r));
      final send = h.c.completeTask(h.c.selectedTask!);
      await Future<void>.delayed(Duration.zero);
      h.m.lock(const NativeLockEvent(8));
      expect(h.c.tasks, isEmpty);
      expect(h.c.selectedTask, isNull);
      expect(h.c.pending, isEmpty);
      delayed.complete(wire(receiptJson()));
      await send;
      expect(h.c.phase, TodayPhase.locked);
      expect(h.c.selectedTask, isNull);
      h.dispose();
    },
  );
}
