import 'package:flutter/material.dart';

import '../today/today_controller.dart';
import '../today/today_screen.dart';

class TaskScreen extends StatelessWidget {
  final TodayController controller;
  final VoidCallback onBack;
  const TaskScreen({super.key, required this.controller, required this.onBack});
  @override
  Widget build(BuildContext context) {
    final c = controller, t = c.selectedTask;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: onBack,
          tooltip: 'Назад к делам',
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Задача'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (c.detailPhase == TodayPhase.loading)
              Semantics(
                label: 'Загрузка задачи',
                child: LinearProgressIndicator(),
              ),
            if (t != null) ...[
              Semantics(
                header: true,
                child: Text(
                  t.title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              Text(
                'Состояние: ${switch (t.status) {
                  'open' => 'Открыта',
                  'done' => 'Завершена',
                  _ => 'Отменена',
                }}',
              ),
              if (t.dueDate != null) Text('Дата: ${t.dueDate}'),
              if (t.dueAt != null) Text(utcLabel(t.dueAt!)),
              if (t.sourceWarning)
                const StatusText(
                  'Источник изменён. Доступные действия проверяются сервером.',
                ),
              FilledButton(
                onPressed:
                    c.online &&
                        c.detailOnline &&
                        !c.busy &&
                        !c.blocked(t.id) &&
                        t.canComplete
                    ? () async {
                        if (await confirmCommand(
                          context,
                          'Завершить эту задачу?',
                        )) {
                          await c.completeTask(t);
                        }
                      }
                    : null,
                child: Text(
                  c.busy ? 'Ожидание результата…' : 'Завершить задачу',
                ),
              ),
              OutlinedButton(
                onPressed: c.busy ? null : () => c.openTask(t.id),
                child: const Text('Обновить задачу'),
              ),
            ],
            if (c.detailPhase == TodayPhase.offline)
              const StatusText('Сохранённые данные · Только чтение'),
            if (c.detailLastSync != null)
              Text('Последняя синхронизация: ${utcLabel(c.detailLastSync!)}'),
            if (c.detailMessage != null) StatusText(c.detailMessage!),
            if (c.detailResourceId != null &&
                c.detailPhase != TodayPhase.loading &&
                !c.busy)
              OutlinedButton(
                onPressed: c.retryDetail,
                child: const Text('Повторить загрузку'),
              ),
            RecoveryList(controller: c),
          ],
        ),
      ),
    );
  }
}
