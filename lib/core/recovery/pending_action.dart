import '../api/domain_models.dart';
import '../api/operation.dart';
import '../api/wire_models.dart' show version;

class PendingAction {
  final Map<String, Object?> json;
  PendingAction.fromJson(Map<String, Object?> j)
    : json = freezeJson(j)! as Map<String, Object?> {
    const fields = {
      'operation',
      'resource_id',
      'expected_version',
      'delay_minutes',
      'action_key',
      'device_id',
      'device_version',
      'api_origin',
      'context_epoch',
      'canonical_request_hash',
      'state',
    };
    if (j.keys.toSet().difference(fields).isNotEmpty ||
        fields.difference(j.keys.toSet()).isNotEmpty) {
      throw const FormatException('Invalid pending fields');
    }
    enumValue(j['operation'], {'completeTask', 'snoozeReminder'});
    uuid(j['resource_id']);
    uuid(j['action_key']);
    uuid(j['device_id']);
    version(j['expected_version']);
    version(j['device_version']);
    version(j['context_epoch']);
    enumValue(j['state'], {'prepared', 'unknown', 'confirmed', 'rejected'});
    if (j['operation'] == 'snoozeReminder'
        ? j['delay_minutes'] != 10
        : j['delay_minutes'] != null) {
      throw const FormatException('Invalid delay');
    }
    final hash = j['canonical_request_hash'];
    if (hash is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid hash');
    }
    final origin = Uri.tryParse(bounded(j['api_origin'], 2048, min: 1));
    if (origin == null || origin.scheme != 'https') {
      throw const FormatException('Invalid origin');
    }
  }
  ApiOperation get operation => json['operation'] == 'completeTask'
      ? ApiOperation.completeTask
      : ApiOperation.snoozeReminder;
  String get resourceId => json['resource_id']! as String;
  String get actionKey => json['action_key']! as String;
  int get expectedVersion => json['expected_version']! as int;
  String get state => json['state']! as String;
  String get kind =>
      operation == ApiOperation.completeTask ? 'task' : 'reminder';
  bool get unresolved => state == 'prepared' || state == 'unknown';
  Map<String, Object?> get body => Map.unmodifiable({
    'expected_version': expectedVersion,
    if (operation == ApiOperation.snoozeReminder) 'delay_minutes': 10,
  });
  void match(MutationReceipt receipt) {
    if (receipt.resourceId != resourceId ||
        receipt.resourceKind != kind ||
        receipt.entityVersion <= expectedVersion) {
      throw const FormatException('Foreign receipt');
    }
  }

  @override
  String toString() => 'PendingAction([redacted])';
}
