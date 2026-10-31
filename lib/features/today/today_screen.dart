import 'package:flutter/material.dart';

import '../tasks/task_screen.dart';
import '../reminders/reminder_screen.dart';
import '../device/device_screen.dart';
import '../../core/recovery/pending_action.dart';
import 'today_controller.dart';

String utcLabel(String value) =>
    '${value.replaceFirst('T', ' ').replaceFirst('Z', '')} UTC';

class TodayShell extends StatefulWidget {
  final TodayController controller;
  final String deviceId;
  final VoidCallback onLogout;
  const TodayShell({
    super.key,
    required this.controller,
    required this.deviceId,
    required this.onLogout,
  });
  @override
  State<TodayShell> createState() => _TodayShellState();
}

class _TodayShellState extends State<TodayShell> {
  String route = 'today';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.refresh();
    });
  }

  void back() => setState(() => route = 'today');
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      if (route == 'device') {
        return DeviceScreen(
          deviceId: widget.deviceId,
          onLogout: widget.onLogout,
          onBack: back,
        );
      }
      if (route == 'task') return TaskScreen(controller: c, onBack: back);
      if (route == 'reminder') {
        return ReminderScreen(controller: c, onBack: back);
      }
      return TodayScreen(
        controller: c,
        onDevice: () => setState(() => route = 'device'),
        onTask: (id) {
          setState(() => route = 'task');
          c.openTask(id);
        },
        onReminder: (id) {
          setState(() => route = 'reminder');
          c.openReminder(id);
        },
      );
    },
  );
}

class StatusText extends StatelessWidget {
  final String text;
  const StatusText(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(text),
    ),
  );
}

class TodayScreen extends StatelessWidget {
  final TodayController controller;
  final VoidCallback onDevice;
  final ValueChanged<String> onTask, onReminder;
  const TodayScreen({
    super.key,
    required this.controller,
    required this.onDevice,
    required this.onTask,
    required this.onReminder,
  });
  @override
  Widget build(BuildContext context) {
    final c = controller, d = c.dashboard;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сегодня'),
        actions: [
          IconButton(
            onPressed: onDevice,
            tooltip: 'Этот телефон',
            icon: const Icon(Icons.phone_android),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Semantics(
              header: true,
              child: Text(
                'Ваши дела',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            if (d != null) Text('Открытых задач: ${d.totalOpenCount}'),
            if (c.phase == TodayPhase.loading)
              Semantics(
                label: 'Загрузка дел',
                child: LinearProgressIndicator(),
              ),
            if (c.lastSync != null)
              Text('Последняя синхронизация: ${utcLabel(c.lastSync!)}'),
            if (c.phase == TodayPhase.offline || c.phase == TodayPhase.stale)
              const StatusText('Сохранённые данные · Только чтение'),
            if (c.message != null) StatusText(c.message!),
            if (c.phase == TodayPhase.empty)
              const StatusText('На сегодня открытых задач нет.'),
            if (d != null)
              Text('Часовой пояс владельца: ${d.preferences.timezone}'),
            if (d?.nearestReminder case final reminder?)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: const Text('Ближайшее напоминание'),
                  subtitle: Text(utcLabel(reminder.dueAt)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onReminder(reminder.id),
                ),
              ),
            for (final task in c.tasks)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(task.title),
                  subtitle: Text(
                    [
                      if (task.dueDate != null) 'Дата: ${task.dueDate}',
                      if (task.dueAt != null) utcLabel(task.dueAt!),
                      if (task.sourceWarning) 'Источник изменён; доступные действия уточняются на сервере',
                    ].join('\n'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onTask(task.id),
                ),
              ),
            if (d?.nextCursor != null)
              OutlinedButton(
                onPressed: c.online && !c.loadingMore ? c.loadNextPage : null,
                child: Text(
                  c.loadingMore ? 'Загрузка страницы…' : 'Показать ещё',
                ),
              ),
            OutlinedButton(
              onPressed: c.phase == TodayPhase.loading ? null : c.refresh,
              child: const Text('Обновить'),
            ),
            RecoveryList(controller: c),
          ],
        ),
      ),
    );
  }
}

class RecoveryList extends StatelessWidget {
  final TodayController controller;
  const RecoveryList({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final entries = c.pending.where((p) => p.unresolved).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (entries.isNotEmpty)
          Semantics(
            header: true,
            child: Text(
              'Команды с неизвестным исходом',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        for (final p in entries)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    p.kind == 'task'
                        ? 'Завершение задачи: результат требует проверки'
                        : 'Перенос напоминания: результат требует проверки',
                  ),
                  FilledButton(
                    onPressed: c.busy ? null : () => c.reconcile(p),
                    child: const Text('Проверить результат'),
                  ),
                  if (c.canRetry(p))
                    OutlinedButton(
                      onPressed: () => confirmOriginal(context, c, p),
                      child: const Text('Повторить исходную команду'),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

Future<bool> confirmCommand(BuildContext context, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подтвердите команду'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    ) ??
    false;
Future<void> confirmOriginal(
  BuildContext context,
  TodayController c,
  PendingAction p,
) async {
  if (await confirmCommand(
    context,
    'Будет повторена исходная команда с тем же ключом и версией. Отсутствие квитанции не доказывает отсутствие прежнего эффекта.',
  )) {
    await c.retryOriginal(p);
  }
}
