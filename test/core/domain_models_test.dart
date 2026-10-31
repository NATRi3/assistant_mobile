import 'package:assistant/features/today/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/domain_fixtures.dart';

void main() {
  test('malformed task cannot become a successful projection', () {
    for (final patch in [
      {'owner_id': 'foreign'},
      {'due_date': '2026-02-30'},
      {'due_at': '2026-10-31T12:00:00Z'},
      {'version': 9007199254740992},
      {'source_warning': 1},
      {
        'permitted_actions': ['delete'],
      },
    ]) {
      expect(
        () => TaskDto.fromJson({...taskJson(), ...patch}),
        throwsFormatException,
      );
    }
  });
  test('dashboard exact nullable policy, actual array byte budget and receipt schema', () {
    expect(Dashboard.fromJson(dashboardJson()).totalOpenCount, 47);
    final bad = <Map<String, Object?>>[
      {...dashboardJson(), 'owner_id': 'foreign'},
      {...dashboardJson(), 'tasks': null},
      {...dashboardJson(), 'total_open_count': 9007199254740992},
      {...dashboardJson(), 'next_cursor': ''},
      {...dashboardJson(), 'tasks': List.filled(51, taskJson())},
      {
        ...dashboardJson(),
        'tasks': List.generate(
          50,
          (i) => {
            ...taskJson(),
            'id':
                '${i.toRadixString(16).padLeft(8, '0')}-1111-4111-8111-111111111111',
            'title': '\u0001' * 4096,
          },
        ),
      },
      {
        ...dashboardJson(),
        'preferences': {
          'version': 1,
          'delivery_route': 'telegram',
          'widget_summary_enabled': false,
          'quiet_hours': {
            'enabled': false,
            'start': '00:00',
            'end': null,
            'timezone': 'UTC',
            'owner_policy_version': 1,
          },
        },
      },
    ];
    for (final value in bad) {
      expect(() => Dashboard.fromJson(value), throwsFormatException);
    }
    expect(
      () => MutationReceipt.fromJson({
        ...receiptJson(),
        'related_task_version': null,
      }),
      throwsFormatException,
    );
    expect(
      () => ReminderSummary.fromJson({
        ...((dashboardJson()['nearest_reminder'])! as Map<String, Object?>),
        'text': 'secret',
      }),
      throwsFormatException,
    );
    expect(
      () => ReminderDto.fromJson({...reminderJson(), 'status': 'delivered'}),
      throwsFormatException,
    );
    expect(
      () => TaskDto.fromJson({
        ...taskJson(),
        'updated_at': '2026-02-30T12:00:00Z',
      }),
      throwsFormatException,
    );
    final original = taskJson();
    final dto = TaskDto.fromJson(original);
    (original['permitted_actions']! as List).clear();
    expect(dto.canComplete, true);
    expect(() => dto.toJson()['title'] = 'changed', throwsUnsupportedError);
  });
}
