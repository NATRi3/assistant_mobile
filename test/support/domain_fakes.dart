import 'dart:async';

import 'package:flutter/services.dart';
import 'package:assistant/core/platform/domain_platform.dart';
import 'package:assistant/core/platform/platform_gateway.dart';
import 'package:assistant/core/api/api_client.dart';
import 'package:assistant/features/today/domain_models.dart';

import 'fakes.dart';

// Synthetic native boundary; real native merge/AEAD is verified separately.
class FakeDomainPlatform extends FakePlatform
    implements DomainPlatform, DomainAccessAuthority {
  final _denials = StreamController<int>.broadcast(sync: true);
  bool policyDenied = false;
  @override
  Stream<int> get domainDenials => _denials.stream;
  @override
  Future<void> denyDomainAccess(int epoch) async {
    if (!policyDenied) {
      policyDenied = true;
      verified = false;
      tickets.clear();
      _denials.add(epoch);
    }
  }

  int _ticketSequence = 0;
  int revision = 0;
  bool failAdmission = false, verified = false;
  Map<String, Object?>? dashboard, scope;
  final Map<String, Object?> tasks = {}, reminders = {}, pending = {};
  final List<String> commits = [];
  final Map<String, ApiOperation> tickets = {};
  @override
  Future<DomainReadTicket> beginDomainRead(
    ApiOperation op, {
    String? resourceId,
    String? cursor,
    int viewGeneration = 0,
  }) async {
    if (policyDenied &&
        op != ApiOperation.getSelfDevice &&
        op != ApiOperation.getDashboard) {
      throw PlatformException(code: 'DOMAIN_ACCESS_DENIED');
    }
    if (op != ApiOperation.getSelfDevice && !verified) {
      throw StateError('Unverified');
    }
    final id = 'ticket-${++_ticketSequence}';
    tickets[id] = op;
    return DomainReadTicket(id, epoch, viewGeneration);
  }

  @override
  Future<void> cancelDomainRead(DomainReadTicket ticket) async {
    tickets.remove(ticket.id);
  }

  @override
  Future<DomainCommitAck> commitDomainRead(
    DomainReadTicket ticket,
    ApiResult result, {
    required int expectedRevision,
  }) async {
    if (result.statusCode != 200 ||
        result.headers['date'] == null ||
        ticket.nativeEpoch != epoch) {
      throw StateError('Invalid provenance');
    }
    final op = tickets.remove(ticket.id)!;
    commits.add(op.name);
    if (op == ApiOperation.getSelfDevice) {
      verified = true;
    } else if (op == ApiOperation.getDashboard) {
      policyDenied = false;
      dashboard = result.body;
      scope = {'context_epoch': result.body['context_epoch']};
      for (final t in result.body['tasks']! as List) {
        tasks[(t as Map)['id']! as String] = t;
      }
    } else if (op == ApiOperation.getTask) {
      tasks[result.body['id']! as String] = result.body;
    } else {
      reminders[result.body['id']! as String] = result.body;
    }
    return DomainCommitAck(++revision, epoch, true);
  }

  Future<DomainFrame> Function(DomainFrame)? frameHandler;
  @override
  Future<DomainFrame> readDomainFrame() async {
    final frame = DomainFrame.fromJson({
      'revision': revision,
      'needs_sync': dashboard == null,
      'policy_denied': policyDenied,
      'dashboard': policyDenied ? null : dashboard,
      'tasks_by_id': policyDenied ? {} : tasks,
      'reminders_by_id': policyDenied ? {} : reminders,
      'pending_actions_by_key': policyDenied ? {} : pending,
      'scope': policyDenied ? null : scope,
      'last_sync': policyDenied ? null : dashboard?['server_time'],
    });
    return frameHandler == null ? frame : await frameHandler!(frame);
  }

  @override
  Future<void> writePrivateCache(PrivateCacheWrite v) async {
    if (v.slot == CacheSlot.session) return super.writePrivateCache(v);
    if (failAdmission) throw StateError('Capacity');
    trace.add('domain-persist');
    for (final raw in v.value['upsert_pending']! as List) {
      final p = objectJson(raw);
      pending[p['action_key']! as String] = {
        ...p,
        'canonical_request_hash': 'a' * 64,
      };
    }
    for (final raw in v.value['resolve_pending']! as List) {
      final r = objectJson(raw), key = r['action_key']! as String;
      pending[key] = {
        ...objectJson(pending[key]),
        'state': r['resolution'] == 'confirmed_receipt'
            ? 'confirmed'
            : 'rejected',
      };
    }
    revision++;
  }
}
