import '../api/operation.dart';
import '../cache/domain_cache.dart';
import '../session/session_memory.dart';
import '../api/domain_models.dart';
import 'pending_action.dart';

class ActionRecovery {
  final DomainCache cache;
  final SessionMemory memory;
  final String origin;
  ActionRecovery(this.cache, this.memory, this.origin);
  static PendingAction retrySame(PendingAction original) => original;
  Future<PendingAction> prepare(
    ApiOperation op,
    String resourceId,
    int version,
    int context,
  ) async {
    final session = memory.current!;
    final intent = <String, Object?>{
      'operation': op.name,
      'resource_id': resourceId,
      'expected_version': version,
      'delay_minutes': op == ApiOperation.snoozeReminder ? 10 : null,
      'action_key': newActionKey(),
      'device_id': session.deviceId,
      'device_version': session.deviceVersion,
      'api_origin': origin,
      'context_epoch': context,
      'canonical_request_hash': '',
      'state': 'prepared',
    };
    final frame = await cache.transact(
      memory.nativeEpoch,
      DomainCache.patch(upsert: [intent]),
    );
    final admitted = PendingAction.fromJson(
      objectJson(frame.pending[intent['action_key']]),
    );
    // The native writer derives the digest from this exact typed intent. No ACK,
    // no matching readback, or changed identity/body => no outgoing command.
    if (admitted.state != 'prepared' ||
        intent.keys
            .where((k) => k != 'canonical_request_hash')
            .any((k) => admitted.json[k] != intent[k])) {
      throw StateError('Pending admission unconfirmed');
    }
    return admitted;
  }

  Future<void> unknown(PendingAction p) async {
    await cache.transact(
      memory.nativeEpoch,
      DomainCache.patch(
        upsert: [
          {...p.json, 'state': 'unknown'},
        ],
      ),
    );
  }

  Future<void> confirm(
    PendingAction p,
    MutationReceipt receipt, {
    required bool lookup,
  }) async {
    p.match(receipt);
    await cache.transact(
      memory.nativeEpoch,
      DomainCache.patch(
        resolve: [
          {
            'action_key': p.actionKey,
            'resolution': 'confirmed_receipt',
            'source_operation': lookup ? 'getMutation' : p.operation.name,
            'status_code': 200,
            'receipt': receipt.json,
            'rejection': null,
          },
        ],
        invalidate: [
          {'kind': p.kind, 'id': p.resourceId},
        ],
      ),
    );
  }

  Future<void> reject(PendingAction p, int status, String code) async {
    await cache.transact(
      memory.nativeEpoch,
      DomainCache.patch(
        resolve: [
          {
            'action_key': p.actionKey,
            'resolution': 'definite_first_rejection',
            'source_operation': p.operation.name,
            'status_code': status,
            'receipt': null,
            'rejection': {'code': code},
          },
        ],
      ),
    );
  }
}
