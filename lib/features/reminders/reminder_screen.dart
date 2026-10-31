import 'package:flutter/material.dart';

import '../today/today_controller.dart';
import '../today/today_screen.dart';

class ReminderScreen extends StatelessWidget {
  final TodayController controller;
  final VoidCallback onBack;
  const ReminderScreen({
    super.key,
    required this.controller,
    required this.onBack,
  });
  @override
  Widget build(BuildContext context) {
    final c = controller, r = c.selectedReminder;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: onBack,
          tooltip: 'Назад к делам',
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Напоминание'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (c.detailPhase == TodayPhase.loading)
              Semantics(
                label: 'Загрузка напоминания',
                child: LinearProgressIndicator(),
              ),
            if (r != null) ...[
              Semantics(
                header: true,
                child: Text(
                  r.text,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              Text(utcLabel(r.dueAt)),
              Text('Часовой пояс владельца: ${r.timezone}'),
              Text(
                'Состояние: ${switch (r.status) {
                  'scheduled' => 'Запланировано',
                  'expired' => 'Истекло',
                  _ => 'Отменено',
                }}',
              ),
              if (r.sourceWarning)
                const StatusText(
                  'Источник изменён. Доступные действия проверяются сервером.',
                ),
              FilledButton(
                onPressed:
                    c.online &&
                        c.detailOnline &&
                        !c.busy &&
                        !c.blocked(r.id) &&
                        r.canSnooze
                    ? () async {
                        if (await confirmCommand(
                          context,
                          'Отложить это напоминание на 10 минут?',
                        )) {
                          await c.snoozeReminder(r);
                        }
                      }
                    : null,
                child: Text(
                  c.busy ? 'Ожидание результата…' : 'Отложить на 10 минут',
                ),
              ),
              OutlinedButton(
                onPressed: c.busy ? null : () => c.openReminder(r.id),
                child: const Text('Обновить напоминание'),
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
