import 'package:flutter/material.dart';

import 'pairing_controller.dart';

class PairingScreen extends StatelessWidget {
  final PairingController controller;
  final String? logoutWarning;
  final VoidCallback? onReset;
  const PairingScreen({
    super.key,
    required this.controller,
    this.logoutWarning,
    this.onReset,
  });
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final p = c.phase;
    final busy = p == PairingPhase.creating || p == PairingPhase.completing;
    final configured = p != PairingPhase.unconfigured;
    return Scaffold(
      appBar: AppBar(title: const Text('Ассистент')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              configured ? 'Подключение телефона' : 'Сервер не настроен',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Text(
              configured
                  ? 'Подключите телефон к своему ассистенту. Подтверждение выполняется владельцем в личном Telegram.'
                  : 'Сервер ассистента не настроен. Подключение недоступно.',
            ),
            if (logoutWarning != null) ...[
              const SizedBox(height: 16),
              Text(logoutWarning!),
            ],
            if (c.message != null) ...[
              const SizedBox(height: 16),
              Semantics(liveRegion: true, child: Text(c.message!)),
            ],
            if (c.challenge != null &&
                {
                  PairingPhase.pending,
                  PairingPhase.approved,
                  PairingPhase.completing,
                }.contains(p)) ...[
              const SizedBox(height: 24),
              Text(
                c.challenge!.code,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              Text('/mobile_pair ${c.challenge!.code}'),
              const SizedBox(height: 12),
              const Text('Сравните полный отпечаток перед подтверждением:'),
              Text(c.challenge!.fingerprint),
              const SizedBox(height: 12),
              Text('Действует до ${c.challenge!.expiresAt.toLocal()}'),
              const SizedBox(height: 16),
              if (p == PairingPhase.pending)
                const Text(
                  'Ожидаем явного подтверждения владельца. Проверка не подтверждает подключение.',
                ),
              if (p == PairingPhase.pending)
                OutlinedButton(
                  onPressed: c.poll,
                  child: const Text('Проверить подтверждение'),
                ),
              if (p == PairingPhase.approved)
                FilledButton(
                  onPressed: c.complete,
                  child: const Text('Завершить подключение'),
                ),
            ],
            if (busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Выполняется запрос…'),
            ],
            const SizedBox(height: 24),
            if (!{
              PairingPhase.pending,
              PairingPhase.approved,
              PairingPhase.completing,
            }.contains(p))
              FilledButton(
                onPressed: configured && !busy ? c.begin : null,
                child: Text(
                  p == PairingPhase.locked
                      ? 'Разблокировать и подключить'
                      : 'Подключить телефон',
                ),
              ),
            if (configured &&
                !busy &&
                {
                  PairingPhase.locked,
                  PairingPhase.error,
                  PairingPhase.revoked,
                }.contains(p))
              TextButton(
                onPressed: onReset,
                child: const Text('Сбросить локальное подключение'),
              ),
            if (c.challenge != null && !busy)
              TextButton(
                onPressed: c.cancel,
                child: const Text('Отменить подключение'),
              ),
          ],
        ),
      ),
    );
  }
}
