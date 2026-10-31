import '../api/api_client.dart';
import '../api/json_value.dart';

Map<String, Object?> immutableObject(Object? value) =>
    freezeJson(objectJson(value))! as Map<String, Object?>;

class DomainReadSuperseded implements Exception {
  const DomainReadSuperseded();
  @override
  String toString() => 'DomainReadSuperseded';
}

class DomainReadTicket {
  final String id;
  final int nativeEpoch, viewGeneration;
  const DomainReadTicket(this.id, this.nativeEpoch, this.viewGeneration);
}

class DomainCommitAck {
  final int revision, nativeEpoch;
  final bool cached;
  const DomainCommitAck(this.revision, this.nativeEpoch, this.cached);
}

class DomainFrame {
  final int revision;
  final bool needsSync, policyDenied;
  final Map<String, Object?>? dashboard;
  final Map<String, Object?> tasks, reminders, pending;
  final Map<String, Object?>? scope;
  final String? lastSync;
  final Map<String, Object?> taskSyncedAt, reminderSyncedAt;
  DomainFrame.fromJson(Map<String, Object?> j)
    : policyDenied = j['policy_denied'] == true,
      taskSyncedAt = immutableObject(j['task_synced_at_by_id'] ?? const {}),
      reminderSyncedAt = immutableObject(
        j['reminder_synced_at_by_id'] ?? const {},
      ),
      revision = j['revision']! as int,
      needsSync = j['needs_sync']! as bool,
      dashboard = j['dashboard'] == null
          ? null
          : immutableObject(j['dashboard']),
      tasks = immutableObject(j['tasks_by_id']),
      reminders = immutableObject(j['reminders_by_id']),
      pending = immutableObject(j['pending_actions_by_key']),
      scope = j['scope'] == null ? null : immutableObject(j['scope']),
      lastSync = j['last_sync'] as String?;
  @override
  String toString() => 'DomainFrame([redacted])';
}

abstract interface class DomainPlatform {
  Future<DomainReadTicket> beginDomainRead(
    ApiOperation operation, {
    String? resourceId,
    String? cursor,
    int viewGeneration = 0,
  });
  Future<DomainCommitAck> commitDomainRead(
    DomainReadTicket ticket,
    ApiResult result, {
    required int expectedRevision,
  });
  Future<void> cancelDomainRead(DomainReadTicket ticket);
  Future<DomainFrame> readDomainFrame();
}
