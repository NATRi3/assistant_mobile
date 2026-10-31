import 'dart:convert' show utf8, jsonEncode;

import 'wire_models.dart';
import 'operation.dart';

import 'json_value.dart';
export 'json_value.dart';

bool boolean(Object? v) {
  if (v is! bool) throw const FormatException('Invalid boolean');
  return v;
}

String uuid(Object? v) {
  if (!validUuid(v)) throw const FormatException('Invalid UUID');
  return v! as String;
}

String bounded(Object? v, int max, {int min = 0}) {
  if (v is! String ||
      v.contains('\u0000') ||
      v.runes.length < min ||
      v.runes.length > max) {
    throw const FormatException('Invalid string');
  }
  return v;
}

String enumValue(Object? v, Set<String> options) {
  if (!options.contains(v)) throw const FormatException('Invalid enum');
  return v! as String;
}

String? calendarDate(Object? v) {
  if (v == null) return null;
  if (v is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) {
    throw const FormatException('Invalid date');
  }
  final t = DateTime.tryParse('${v}T00:00:00Z');
  if (t == null || t.toIso8601String().substring(0, 10) != v) {
    throw const FormatException('Invalid date');
  }
  return v;
}

List<String> actions(Object? v, String permitted) {
  if (v is! List || v.length > 1 || v.any((x) => x != permitted)) {
    throw const FormatException('Invalid actions');
  }
  return List<String>.unmodifiable(v.cast<String>());
}

abstract class Projection {
  final Map<String, Object?> json;
  Projection(Map<String, Object?> value)
    : json = freezeJson(value)! as Map<String, Object?>;
  Map<String, Object?> toJson() => json;
  String get id => json['id']! as String;
  int get entityVersion => json['version']! as int;
  bool get sourceWarning => json['source_warning']! as bool;
  @override
  String toString() => 'Projection([redacted])';
}

class TaskDto extends Projection {
  TaskDto.fromJson(Map<String, Object?> j) : super(j) {
    exact(j, {
      'id',
      'title',
      'status',
      'version',
      'due_date',
      'due_at',
      'source_warning',
      'updated_at',
      'permitted_actions',
    });
    uuid(j['id']);
    bounded(j['title'], 4096);
    enumValue(j['status'], {'open', 'done', 'cancelled'});
    version(j['version']);
    calendarDate(j['due_date']);
    if (j['due_at'] != null) timestamp(j['due_at']);
    if (j['due_date'] != null && j['due_at'] != null) {
      throw const FormatException('Exclusive dates');
    }
    boolean(j['source_warning']);
    timestamp(j['updated_at']);
    actions(j['permitted_actions'], 'complete');
  }
  String get title => json['title']! as String;
  String get status => json['status']! as String;
  String? get dueDate => json['due_date'] as String?;
  String? get dueAt => json['due_at'] as String?;
  bool get canComplete =>
      status == 'open' &&
      (json['permitted_actions']! as List).contains('complete');
}

class ReminderSummary extends Projection {
  ReminderSummary.fromJson(Map<String, Object?> j) : super(j) {
    exact(j, {'id', 'due_at', 'version', 'source_warning'});
    uuid(j['id']);
    timestamp(j['due_at']);
    version(j['version']);
    boolean(j['source_warning']);
  }
  String get dueAt => json['due_at']! as String;
}

class ReminderDto extends Projection {
  ReminderDto.fromJson(Map<String, Object?> j) : super(j) {
    exact(j, {
      'id',
      'text',
      'status',
      'active',
      'version',
      'due_at',
      'timezone',
      'linked_task_id',
      'source_warning',
      'updated_at',
      'permitted_actions',
    });
    uuid(j['id']);
    bounded(j['text'], 4096);
    enumValue(j['status'], {'scheduled', 'cancelled', 'expired'});
    boolean(j['active']);
    version(j['version']);
    timestamp(j['due_at']);
    bounded(j['timezone'], 100, min: 1);
    if (j['linked_task_id'] != null) uuid(j['linked_task_id']);
    boolean(j['source_warning']);
    timestamp(j['updated_at']);
    actions(j['permitted_actions'], 'snooze_10m');
  }
  String get text => json['text']! as String;
  String get status => json['status']! as String;
  String get dueAt => json['due_at']! as String;
  String get timezone => json['timezone']! as String;
  bool get canSnooze =>
      status == 'scheduled' &&
      json['active'] == true &&
      (json['permitted_actions']! as List).contains('snooze_10m');
}

class Preferences {
  final Map<String, Object?> json;
  Preferences.fromJson(Map<String, Object?> j)
    : json = freezeJson(j)! as Map<String, Object?> {
    exact(j, {
      'version',
      'delivery_route',
      'widget_summary_enabled',
      'quiet_hours',
    });
    version(j['version']);
    enumValue(j['delivery_route'], {'telegram', 'mobile', 'both'});
    boolean(j['widget_summary_enabled']);
    final q = objectJson(j['quiet_hours']);
    exact(q, {'enabled', 'start', 'end', 'timezone', 'owner_policy_version'});
    final enabled = boolean(q['enabled']);
    bounded(q['timezone'], 100, min: 1);
    version(q['owner_policy_version']);
    final pattern = RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$');
    if (enabled
        ? !(q['start'] is String &&
              q['end'] is String &&
              pattern.hasMatch(q['start']! as String) &&
              pattern.hasMatch(q['end']! as String) &&
              q['start'] != q['end'])
        : q['start'] != null || q['end'] != null) {
      throw const FormatException('Invalid quiet policy');
    }
  }
  int get ownerPolicyVersion =>
      (json['quiet_hours']! as Map)['owner_policy_version']! as int;
  String get timezone => (json['quiet_hours']! as Map)['timezone']! as String;
  @override
  String toString() => 'Preferences([redacted])';
}

class Dashboard {
  final Map<String, Object?> json;
  final List<TaskDto> tasks;
  final ReminderSummary? nearestReminder;
  final Preferences preferences;
  Dashboard.fromJson(Map<String, Object?> j) : this._decode(j, false);
  // Native aggregate: distinct from a single HTTP page. Native still owns the
  // whole encrypted envelope budget, per-entry age and membership resolution.
  Dashboard.fromCacheJson(Map<String, Object?> j) : this._decode(j, true);
  Dashboard._decode(Map<String, Object?> j, bool aggregate)
    : json = freezeJson(j)! as Map<String, Object?>,
      tasks = _tasks(j['tasks'], aggregate),
      nearestReminder = j['nearest_reminder'] == null
          ? null
          : ReminderSummary.fromJson(objectJson(j['nearest_reminder'])),
      preferences = Preferences.fromJson(objectJson(j['preferences'])) {
    exact(j, {
      'server_time',
      'snapshot_id',
      'context_epoch',
      'tasks',
      'total_open_count',
      'nearest_reminder',
      'preferences',
      'next_cursor',
    });
    timestamp(j['server_time']);
    uuid(j['snapshot_id']);
    version(j['context_epoch']);
    final count = j['total_open_count'];
    if (count is! int || count < 0 || count > 9007199254740991) {
      throw const FormatException('Invalid count');
    }
    if (j['next_cursor'] != null) bounded(j['next_cursor'], 1024, min: 1);
    if (aggregate && utf8.encode(jsonEncode(j)).length > 2097152) {
      throw const FormatException('Invalid cache view');
    }
  }
  static List<TaskDto> _tasks(Object? v, bool aggregate) {
    if (v is! List ||
        v.length > (aggregate ? 200 : 50) ||
        utf8.encode(jsonEncode(v)).length > (aggregate ? 2097152 : 196608)) {
      throw const FormatException('Invalid page');
    }
    final tasks = v.map((x) => TaskDto.fromJson(objectJson(x))).toList();
    if (tasks.map((x) => x.id).toSet().length != tasks.length) {
      throw const FormatException('Duplicate task');
    }
    return List.unmodifiable(tasks);
  }

  int get contextEpoch => json['context_epoch']! as int;
  int get totalOpenCount => json['total_open_count']! as int;
  String? get nextCursor => json['next_cursor'] as String?;
  String get serverTime => json['server_time']! as String;
  @override
  String toString() => 'Dashboard([redacted])';
}

class MutationReceipt {
  final Map<String, Object?> json;
  MutationReceipt.fromJson(Map<String, Object?> j)
    : json = freezeJson(j)! as Map<String, Object?> {
    final required = {
      'effect_id',
      'resource_id',
      'resource_kind',
      'version',
      'changed_at',
      'replayed',
    };
    if (!j.keys.toSet().containsAll(required) ||
        j.keys.any(
          (k) => !{
            ...required,
            'related_task_version',
            'related_reminder_version',
          }.contains(k),
        )) {
      throw const FormatException('Invalid receipt fields');
    }
    uuid(j['effect_id']);
    uuid(j['resource_id']);
    enumValue(j['resource_kind'], {
      'task',
      'reminder',
      'chat',
      'preferences',
      'push_registration',
    });
    version(j['version']);
    timestamp(j['changed_at']);
    boolean(j['replayed']);
    for (final k in ['related_task_version', 'related_reminder_version']) {
      if (j.containsKey(k)) version(j[k]);
    }
  }
  String get resourceId => json['resource_id']! as String;
  String get resourceKind => json['resource_kind']! as String;
  int get entityVersion => json['version']! as int;
  @override
  String toString() => 'MutationReceipt([redacted])';
}
