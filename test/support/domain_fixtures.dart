Map<String, Object?> taskJson() => {
  'id': '11111111-1111-4111-8111-111111111111',
  'title': 'Синтетическая задача',
  'status': 'open',
  'version': 3,
  'due_date': '2026-10-31',
  'due_at': null,
  'source_warning': false,
  'updated_at': '2026-10-31T12:00:00Z',
  'permitted_actions': ['complete'],
};
const taskId = '11111111-1111-4111-8111-111111111111';
const reminderId = '22222222-2222-4222-8222-222222222222';
Map<String, Object?> dashboardJson() => {
  'server_time': '2026-10-31T12:00:00Z',
  'snapshot_id': taskId,
  'context_epoch': 1,
  'tasks': [taskJson()],
  'total_open_count': 47,
  'nearest_reminder': {
    'id': reminderId,
    'due_at': '2026-10-31T13:00:00Z',
    'version': 4,
    'source_warning': false,
  },
  'preferences': {
    'version': 1,
    'delivery_route': 'telegram',
    'widget_summary_enabled': false,
    'quiet_hours': {
      'enabled': false,
      'start': null,
      'end': null,
      'timezone': 'Europe/Moscow',
      'owner_policy_version': 1,
    },
  },
  'next_cursor': null,
};
Map<String, Object?> reminderJson() => {
  'id': reminderId,
  'text': 'Синтетическое напоминание',
  'status': 'scheduled',
  'active': true,
  'version': 4,
  'due_at': '2026-10-31T13:00:00Z',
  'timezone': 'Europe/Moscow',
  'linked_task_id': taskId,
  'source_warning': false,
  'updated_at': '2026-10-31T12:00:00Z',
  'permitted_actions': ['snooze_10m'],
};
Map<String, Object?> receiptJson({String id = taskId, String kind = 'task'}) =>
    {
      'effect_id': reminderId,
      'resource_id': id,
      'resource_kind': kind,
      'version': 5,
      'changed_at': '2026-10-31T12:01:00Z',
      'replayed': false,
    };
