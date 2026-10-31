import 'package:flutter/material.dart';

class DeviceScreen extends StatelessWidget {
  final String deviceId;
  final VoidCallback onLogout;
  const DeviceScreen({
    super.key,
    required this.deviceId,
    required this.onLogout,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Подключённый телефон')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.verified_user_outlined, size: 48),
          const SizedBox(height: 24),
          Text(
            'Телефон подключён',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          const Text(
            'Защищённая сессия сохранена. Задачи, диалог и уведомления ещё не входят в эту сборку.',
          ),
          const SizedBox(height: 24),
          const Text('Идентификатор телефона'),
          Text(deviceId),
          const SizedBox(height: 24),
          const Text('Для отзыва через личный Telegram:'),
          Text('/mobile_revoke $deviceId'),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: onLogout,
            child: const Text('Отключить этот телефон'),
          ),
        ],
      ),
    ),
  );
}
