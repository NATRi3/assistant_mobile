// Permanent G5-F1 regressions adapted from the independent G5 four-case probe.
import 'dart:async';

import 'package:assistant/core/platform/domain_platform.dart';
import 'package:assistant/features/today/today_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/today_harness.dart';
import '../support/domain_fixtures.dart';
import '../support/domain_fakes.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';

import 'package:assistant/core/api/api_client.dart';
import 'package:assistant/core/cache/domain_cache.dart';
import 'package:assistant/core/config/app_config.dart';
import 'package:assistant/core/platform/platform_gateway.dart';
import 'package:assistant/core/recovery/action_recovery.dart';
import 'package:assistant/core/session/session_memory.dart';
import 'package:assistant/features/today/today_repository.dart';

class SigningPlatform extends FakeDomainPlatform {
  final signing = Completer<void>(), deliverProof = Completer<void>();
  @override
  Future<String> signDpop(DpopMetadata metadata) async {
    // Model the relevant existing native guards, without adding a fictional
    // pending/context check. Keyguard/300s eligibility is held valid in this probe.
    if (policyDenied || metadata.accessToken != fixtureSession().accessToken) {
      throw StateError('Native admission rejected');
    }
    final proof = await super.signDpop(metadata);
    if (metadata.operation == ApiOperation.completeTask) {
      signing.complete();
      await deliverProof.future;
    }
    return proof;
  }
}

Map<String, Object?> changedPage(String change) => {
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
  for (final change in ['context', 'policy']) {
    test(
      'G5 explicit retry retains unknown original when $change changes during proof',
      () async {
        final p = SigningPlatform(),
            m = SessionMemory()..adopt(UnlockResult(7, fixtureSession())),
            t = FakeTransport();
        final api = ApiClient(
              AppConfig.parse('https://synthetic.invalid'),
              p,
              t,
              m,
            ),
            cache = DomainCache(p, p, m);
        final repository = ApiTodayRepository(api, cache, p);
        final recovery = ActionRecovery(cache, m, 'https://synthetic.invalid');
        final c = TodayController(repository, cache, m, recovery: recovery);
        t.handler = (request) async => request.uri.path.contains('/mutations/')
            ? wire({'code': 'NOT_FOUND'}, status: 404)
            : wire(
                request.uri.path.endsWith('/self')
                    ? fixtureDevice()
                    : request.uri.path.endsWith('/dashboard')
                    ? dashboardJson()
                    : request.method == 'POST'
                    ? receiptJson()
                    : taskJson(),
              );
        await repository.verifyDevice();
        await c.refresh();
        await recovery.prepare(ApiOperation.completeTask, taskId, 3, 1);
        await c.refresh();
        await c.reconcile(c.pending.single);
        final original = c.pending.single;
        expect(c.canRetry(original), true);
        final retry = c.retryOriginal(original);
        await p.signing.future;
        t.handler = (request) async => wire(
          request.uri.path.endsWith('/dashboard')
              ? changedPage(change)
              : receiptJson(),
        );
        await c.refresh();
        p.deliverProof.complete();
        await retry;
        expect(t.requests.where((r) => r.method == 'POST'), isEmpty);
        expect(p.pending[original.actionKey], original.json);
        expect(c.busy, false);
        c.dispose();
        repository.dispose();
        m.dispose();
        await p.events.close();
      },
    );
    test(
      'G5 no POST when $change changes while native proof reply is awaited',
      () async {
        final p = SigningPlatform(),
            m = SessionMemory()..adopt(UnlockResult(7, fixtureSession())),
            t = FakeTransport();
        final api = ApiClient(
              AppConfig.parse('https://synthetic.invalid'),
              p,
              t,
              m,
            ),
            cache = DomainCache(p, p, m);
        final repository = ApiTodayRepository(api, cache, p);
        final c = TodayController(
          repository,
          cache,
          m,
          recovery: ActionRecovery(cache, m, 'https://synthetic.invalid'),
        );
        t.handler = (request) async => wire(
          request.uri.path.endsWith('/self')
              ? fixtureDevice()
              : request.uri.path.endsWith('/dashboard')
              ? dashboardJson()
              : request.method == 'POST'
              ? receiptJson()
              : taskJson(),
        );
        await repository.verifyDevice();
        await c.refresh();
        await c.openTask(taskId);
        final operation = c.completeTask(c.selectedTask!);
        await p.signing.future;
        final original = Map.of(p.pending.values.single as Map);
        expect(t.requests.where((r) => r.method == 'POST'), isEmpty);
        t.handler = (request) async => wire(
          request.uri.path.endsWith('/dashboard')
              ? changedPage(change)
              : receiptJson(),
        );
        await c.refresh();
        expect(
          change == 'context'
              ? c.dashboard!.contextEpoch
              : c.dashboard!.preferences.ownerPolicyVersion,
          2,
        );
        expect(m.nativeEpoch, 7);
        expect(
          m.unlocked &&
              p.unlocked &&
              !p.policyDenied &&
              !p.closing &&
              p.keyExists,
          true,
        );
        p.deliverProof.complete();
        await operation;
        final posts = t.requests.where((r) => r.method == 'POST').length;
        expect(p.pending.values.single, original);
        expect(c.busy, false);
        c.dispose();
        repository.dispose();
        m.dispose();
        await p.events.close();
        expect(
          posts,
          0,
          reason: 'scope fence must survive awaited native signing before transport starts',
        );
      },
    );
    test('G5 no POST when $change changes during final pending read', () async {
      final h = TodayHarness();
      await h.enter();
      final started = Completer<void>(), resume = Completer<void>();
      var reads = 0;
      h.p.frameHandler = (DomainFrame frame) async {
        // #1 prepare's CAS read; #2 durable readback; #3 _start's _pending.
        if (++reads == 3) {
          started.complete();
          await resume.future;
        }
        return frame;
      };
      final operation = h.c.completeTask(h.c.selectedTask!);
      await started.future;
      expect(h.t.requests.where((r) => r.method == 'POST'), isEmpty);
      expect(h.p.pending.length, 1);
      final original = Map.of(h.p.pending.values.single as Map);
      h.t.handler = (r) async => r.uri.path.endsWith('/dashboard')
          ? wire({
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
            })
          : h.defaultResponse(r);
      await h.c.refresh();
      expect(h.c.phase, TodayPhase.fresh);
      expect(h.c.busy, false);
      expect(h.m.unlocked, true);
      expect(h.m.nativeEpoch, 7);
      expect(h.p.policyDenied, false);
      expect(
        change == 'context'
            ? h.c.dashboard!.contextEpoch
            : h.c.dashboard!.preferences.ownerPolicyVersion,
        2,
      );
      resume.complete();
      await operation;
      final posts = h.t.requests.where((r) => r.method == 'POST').length;
      expect(h.p.pending.values.single, original);
      expect(h.c.busy, false);
      h.dispose();
      expect(
        posts,
        0,
        reason: 'obsolete prepared command must not start POST after known scope change',
      );
    });
  }
}
