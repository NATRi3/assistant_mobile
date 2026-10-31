import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:assistant/app.dart';
import 'package:assistant/core/config/app_config.dart';
import 'package:assistant/theme/token_loader.dart';

import '../support/fakes.dart';

void main() {
  testWidgets('production shell stays inert without server at 2x text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final p = FakePlatform(), t = FakeTransport();
    final tokens = await DesignTokens.load();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: AssistantApp(
          config: AppConfig.parse(''),
          tokens: tokens,
          platform: p,
          transport: t,
        ),
      ),
    );
    expect(
      find.text('Сервер ассистента не настроен. Подключение недоступно.'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(t.requests, isEmpty);
    expect(p.trace, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
