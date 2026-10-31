import 'package:flutter/material.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/api/http_transport.dart';
import 'core/platform/method_channel_gateway.dart';
import 'theme/token_loader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.parse(
    const String.fromEnvironment('ASSISTANT_API_ORIGIN'),
  );
  final tokens = await DesignTokens.load();
  final platform = MethodChannelGateway();
  final state = await platform.bootstrap(config);
  final id = state['device_id'];
  final warning = state['logout_unconfirmed'] == true
      ? 'Телефон отключён здесь; серверный отзыв не подтверждён${id is String ? '. В личном Telegram: /mobile_revoke $id' : ''}'
      : null;
  runApp(
    AssistantApp(
      config: config,
      tokens: tokens,
      platform: platform,
      transport: HttpTransport(),
      initialWarning: warning,
      initialDeviceId: id is String ? id : null,
      initialNativeEpoch: state['native_epoch']! as int,
    ),
  );
}
