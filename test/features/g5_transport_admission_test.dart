import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:assistant/core/api/api_client.dart';
import 'package:assistant/core/api/api_error.dart';
import 'package:assistant/core/cache/domain_cache.dart';
import 'package:assistant/core/config/app_config.dart';
import 'package:assistant/core/platform/platform_gateway.dart';
import 'package:assistant/core/recovery/action_recovery.dart';
import 'package:assistant/core/session/session_memory.dart';
import 'package:assistant/features/today/today_controller.dart';
import 'package:assistant/features/today/today_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/domain_fakes.dart';
import '../support/domain_fixtures.dart';
import '../support/fixtures.dart';
import '../support/today_harness.dart';
import 'review_fix2_regressions_test.dart' show scopePage;

// Exercise production HttpTransport, including its actual openUrl await. Only
// dart:io's connection is synthetic; no network or native authentication occurs.
class _Connections {
  final opening = Completer<void>(), resume = Completer<void>();
  final List<ApiRequest> sent = [];
  final List<_Request> opened = [];
  final List<_Client> clients = [];
  bool holdPost = false;
  String? changedScope;
  Future<ApiResponse> Function(ApiRequest)? handler;
  HttpClient create(SecurityContext? _) {
    final client = _Client(this);
    clients.add(client);
    return client;
  }

  ApiResponse response(ApiRequest r) {
    if (r.uri.path.endsWith('/self')) return wire(fixtureDevice());
    if (r.uri.path.endsWith('/dashboard')) {
      return wire(
        changedScope == null ? dashboardJson() : scopePage(changedScope!),
      );
    }
    if (r.uri.path.contains('/mutations/')) return wire(receiptJson());
    if (r.method == 'POST') {
      return wire(
        r.uri.path.contains('/reminders/')
            ? receiptJson(id: reminderId, kind: 'reminder')
            : receiptJson(),
      );
    }
    return wire(
      r.uri.path.contains('/reminders/') ? reminderJson() : taskJson(),
    );
  }
}

class _Client implements HttpClient {
  final _Connections connections;
  bool closed = false;
  @override
  Duration? connectionTimeout;
  _Client(this.connections);
  @override
  Future<HttpClientRequest> openUrl(String method, Uri uri) async {
    final request = _Request(connections, method, uri);
    connections.opened.add(request);
    if (method == 'POST' && connections.holdPost) {
      connections.holdPost = false;
      connections.opening.complete();
      await connections.resume.future;
    }
    return request;
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  final Map<String, String> values = {};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value.toString();
  }

  @override
  void forEach(void Function(String, List<String>) action) {
    values.forEach((key, value) => action(key, [value]));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  final _Connections connections;
  @override
  final String method;
  @override
  final Uri uri;
  @override
  final _Headers headers = _Headers();
  final List<int> body = [];
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  bool submitted = false;
  _Request(this.connections, this.method, this.uri);
  @override
  void add(List<int> data) {
    body.addAll(data);
  }

  @override
  Future<HttpClientResponse> close() async {
    submitted = true;
    final r = ApiRequest(method, uri, Map.of(headers.values), List.of(body));
    connections.sent.add(r);
    final response =
        await (connections.handler?.call(r) ??
            Future.value(connections.response(r)));
    return _Response(response);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  final ApiResponse response;
  _Response(this.response);
  @override
  int get statusCode => response.statusCode;
  @override
  HttpHeaders get headers => _Headers()..values.addAll(response.headers);
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(response.body).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  final p = FakeDomainPlatform();
  final m = SessionMemory()..adopt(UnlockResult(7, fixtureSession()));
  late final api = ApiClient(
    AppConfig.parse('https://synthetic.invalid'),
    p,
    HttpTransport(),
    m,
  );
  late final cache = DomainCache(p, p, m);
  late final repository = ApiTodayRepository(api, cache, p);
  late final controller = TodayController(
    repository,
    cache,
    m,
    recovery: ActionRecovery(cache, m, 'https://synthetic.invalid'),
  );
  Future<void> enter() async {
    await repository.verifyDevice();
    await controller.refresh();
    await controller.openTask(taskId);
  }

  void dispose() {
    controller.dispose();
    repository.dispose();
    m.dispose();
    p.events.close();
  }
}

void main() {
  // F2 regressions adapted from the independent G5 post-transmit denial probe.
  for (final change in ['none', 'context', 'policy']) {
    test(
      'G5 current-session post-transmit 403 after $change persists denial before suppressing stale command',
      () async {
        final connections = _Connections();
        await HttpOverrides.runZoned(() async {
          final h = _Harness();
          await h.enter();
          final submitted = Completer<void>(),
              response = Completer<ApiResponse>();
          connections.handler = (r) {
            if (r.method == 'POST') {
              submitted.complete();
              return response.future;
            }
            return Future.value(connections.response(r));
          };
          final old = h.controller.completeTask(h.controller.selectedTask!);
          await submitted.future;
          final original = Map.of(h.p.pending.values.single as Map);
          expect(connections.opened.last.submitted, true);
          if (change != 'none') {
            connections.changedScope = change;
            await h.controller.refresh();
          }
          response.complete(wire({'code': 'OWNER_PAUSED'}, status: 403));
          await old;
          expect(connections.sent.where((r) => r.method == 'POST').length, 1);
          expect(h.p.pending.values.single, original);
          expect(h.m.nativeEpoch, 7);
          expect(
            h.p.policyDenied,
            true,
            reason: 'Current authenticated denial must persist before stale ownership can suppress publication',
          );
          expect(h.controller.phase, TodayPhase.paused);
          expect(h.controller.dashboard, isNull);
          expect(h.controller.tasks, isEmpty);
          expect((await h.p.readDomainFrame()).dashboard, isNull);
          connections.handler = (_) async =>
              wire({'code': 'UNAVAILABLE'}, status: 503);
          await h.controller.refresh();
          expect(h.controller.phase, TodayPhase.paused);
          expect(h.controller.dashboard, isNull);
          expect(h.p.policyDenied, true);
          h.dispose();
        }, createHttpClient: connections.create);
      },
    );
  }
  for (final authority in ['epoch', 'session', 'request generation']) {
    test(
      'G5 old $authority post-transmit 403 cannot deny current authority',
      () async {
        final connections = _Connections();
        await HttpOverrides.runZoned(() async {
          final h = _Harness();
          await h.enter();
          final submitted = Completer<void>(),
              response = Completer<ApiResponse>();
          connections.handler = (r) {
            if (r.method == 'POST') {
              submitted.complete();
              return response.future;
            }
            return Future.value(connections.response(r));
          };
          final old = h.controller.completeTask(h.controller.selectedTask!);
          await submitted.future;
          final original = Map.of(h.p.pending.values.single as Map);
          if (authority == 'epoch') {
            h.m.lock(const NativeLockEvent(8));
            h.p.epoch = 9;
            h.m.adopt(UnlockResult(9, fixtureSession()));
          } else if (authority == 'session') {
            h.m.install(
              SessionDto.fromJson({
                ...fixtureSession().toJson(),
                'access_token': 'B' * 43,
              }),
              7,
            );
          } else {
            h.api.cancelPrivateRequests();
          }
          response.complete(wire({'code': 'OWNER_PAUSED'}, status: 403));
          await old;
          expect(h.p.policyDenied, false);
          expect(h.m.unlocked, true);
          expect(
            (h.p.pending.values.single as Map)['state'],
            isNot('rejected'),
          );
          final retained = Map.of(h.p.pending.values.single as Map)
            ..remove('state');
          original.remove('state');
          expect(retained, original);
          expect(connections.sent.where((r) => r.method == 'POST').length, 1);
          h.dispose();
        }, createHttpClient: connections.create);
      },
    );
  }
  for (final change in ['context', 'policy']) {
    test(
      'G5 late200 after $change stays unresolved without publication or resend',
      () async {
        final connections = _Connections();
        await HttpOverrides.runZoned(() async {
          final h = _Harness();
          await h.enter();
          final submitted = Completer<void>(),
              response = Completer<ApiResponse>();
          connections.handler = (r) {
            if (r.method == 'POST') {
              submitted.complete();
              return response.future;
            }
            return Future.value(connections.response(r));
          };
          final old = h.controller.completeTask(h.controller.selectedTask!);
          await submitted.future;
          final original = Map.of(h.p.pending.values.single as Map);
          connections.changedScope = change;
          await h.controller.refresh();
          response.complete(wire(receiptJson()));
          await old;
          expect(h.p.pending.values.single, original);
          expect(h.controller.pending.single.unresolved, true);
          expect(h.p.policyDenied, false);
          expect(h.controller.phase, TodayPhase.fresh);
          expect(
            h.controller.detailMessage,
            isNot(contains('Команда выполнена')),
          );
          expect(connections.sent.where((r) => r.method == 'POST').length, 1);
          h.dispose();
        }, createHttpClient: connections.create);
      },
    );
  }
  for (final change in [
    'context',
    'policy',
    'lock',
    'new epoch',
    'denial',
    'dispose',
  ]) {
    test(
      'G5 production transport stops $change at delayed connection before headers/body/close',
      () async {
        final connections = _Connections();
        await HttpOverrides.runZoned(() async {
          final h = _Harness();
          var disposed = false;
          await h.enter();
          connections.holdPost = true;
          final command = h.controller.completeTask(h.controller.selectedTask!);
          await connections.opening.future;
          final original = Map.of(h.p.pending.values.single as Map);
          final request = connections.opened.last;
          expect(request.method, 'POST');
          switch (change) {
            case 'context' || 'policy':
              connections.changedScope = change;
              await h.controller.refresh();
            case 'lock':
              h.m.lock(const NativeLockEvent(8));
            case 'new epoch':
              h.m.lock(const NativeLockEvent(8));
              h.p.epoch = 9;
              h.m.adopt(UnlockResult(9, fixtureSession()));
            case 'denial':
              await h.p.denyDomainAccess(7);
            case 'dispose':
              h.controller.dispose();
              disposed = true;
          }
          connections.resume.complete();
          await command;
          expect(
            request.headers.values,
            isEmpty,
            reason: 'No proof/token sent after failed admission',
          );
          expect(request.body, isEmpty);
          expect(request.submitted, false);
          expect(connections.sent.where((r) => r.method == 'POST'), isEmpty);
          expect(
            h.p.pending.values.single,
            original,
            reason: 'Invalidation cannot erase/rewrite the durable original',
          );
          expect(connections.clients.every((c) => c.closed), true);
          if (!disposed) h.controller.dispose();
          h.repository.dispose();
          h.m.dispose();
          await h.p.events.close();
        }, createHttpClient: connections.create);
      },
    );
  }
  for (final kind in ['complete', 'snooze', 'retry']) {
    test(
      'G5 production transport admits normal $kind with the immutable original request',
      () async {
        final connections = _Connections();
        await HttpOverrides.runZoned(() async {
          final h = _Harness();
          await h.enter();
          if (kind == 'snooze') await h.controller.openReminder(reminderId);
          if (kind == 'retry') {
            connections.handler = (r) async {
              if (r.method == 'POST') {
                throw const ApiError(0, 'TRANSPORT_UNAVAILABLE');
              }
              if (r.uri.path.contains('/mutations/')) {
                return wire({'code': 'NOT_FOUND'}, status: 404);
              }
              return connections.response(r);
            };
            await h.controller.completeTask(h.controller.selectedTask!);
            await h.controller.reconcile(h.controller.pending.single);
            expect(h.controller.canRetry(h.controller.pending.single), true);
            connections.handler = null;
          }
          connections.holdPost = true;
          final action = kind == 'retry'
              ? h.controller.retryOriginal(h.controller.pending.single)
              : kind == 'snooze'
              ? h.controller.snoozeReminder(h.controller.selectedReminder!)
              : h.controller.completeTask(h.controller.selectedTask!);
          await connections.opening.future;
          final original = Map.of(h.p.pending.values.single as Map);
          connections.resume.complete();
          await action;
          final posts = connections.sent
              .where((r) => r.method == 'POST')
              .toList();
          expect(posts.length, kind == 'retry' ? 2 : 1);
          final post = posts.last;
          expect(post.headers['Idempotency-Key'], original['action_key']);
          expect(post.headers['DPoP'], 'proof');
          expect(jsonDecode(utf8.decode(post.body!)), {
            'expected_version': kind == 'snooze' ? 4 : 3,
            if (kind == 'snooze') 'delay_minutes': 10,
          });
          if (kind == 'retry') {
            expect(posts.first.uri, post.uri);
            expect(posts.first.body, post.body);
            expect(
              posts.first.headers['Idempotency-Key'],
              post.headers['Idempotency-Key'],
            );
          }
          expect(h.controller.pending.single.state, 'confirmed');
          expect(h.controller.busy, false);
          h.dispose();
        }, createHttpClient: connections.create);
      },
    );
  }
  test('G5 same-scope read supersession preserves command waiting on production connection', () async {
    final connections = _Connections();
    await HttpOverrides.runZoned(() async {
      final h = _Harness();
      await h.enter();
      connections.holdPost = true;
      final command = h.controller.completeTask(h.controller.selectedTask!);
      await connections.opening.future;
      final oldDashboard = Completer<ApiResponse>(),
          reading = Completer<void>();
      var dashboards = 0;
      connections.handler = (r) {
        if (r.uri.path.endsWith('/dashboard') && ++dashboards == 1) {
          reading.complete();
          return oldDashboard.future;
        }
        return Future.value(connections.response(r));
      };
      final oldRefresh = h.controller.refresh();
      await reading.future;
      await h.controller.refresh();
      oldDashboard.complete(wire(dashboardJson()));
      await oldRefresh;
      expect(h.controller.busy, true);
      connections.resume.complete();
      await command;
      expect(connections.sent.where((r) => r.method == 'POST').length, 1);
      expect(h.controller.pending.single.state, 'confirmed');
      expect(h.m.unlocked, true);
      h.dispose();
    }, createHttpClient: connections.create);
  });
  test('G5 obsolete connection cannot send or clear newer reconciliation ownership', () async {
    final connections = _Connections();
    await HttpOverrides.runZoned(() async {
      final h = _Harness();
      await h.enter();
      connections.holdPost = true;
      final old = h.controller.completeTask(h.controller.selectedTask!);
      await connections.opening.future;
      connections.changedScope = 'context';
      await h.controller.refresh();
      final lookup = Completer<ApiResponse>(), started = Completer<void>();
      connections.handler = (r) {
        if (r.uri.path.contains('/mutations/')) {
          started.complete();
          return lookup.future;
        }
        return Future.value(connections.response(r));
      };
      final newer = h.controller.reconcile(h.controller.pending.single);
      await started.future;
      connections.resume.complete();
      await old;
      expect(h.controller.busy, true);
      expect(connections.sent.where((r) => r.method == 'POST'), isEmpty);
      lookup.complete(wire({'code': 'NOT_FOUND'}, status: 404));
      await newer;
      expect(h.controller.busy, false);
      expect(h.controller.pending.single.state, 'unknown');
      h.dispose();
    }, createHttpClient: connections.create);
  });
}
