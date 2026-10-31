import 'package:assistant/features/today/today_screen.dart';
import 'package:assistant/features/tasks/task_screen.dart';
import 'package:assistant/features/today/today_controller.dart';
import 'package:assistant/theme/assistant_theme.dart';
import 'package:assistant/theme/token_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/today_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DesignTokens tokens;
  setUpAll(() async {
    tokens = await DesignTokens.load();
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      'synthetic Today/detail 360dp 2x $brightness reflows and summary stays generic',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = TodayHarness();
        await h.enter();
        await tester.pumpWidget(
          MaterialApp(
            theme: assistantTheme(tokens, brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: TodayScreen(
              controller: h.c,
              onDevice: () {},
              onTask: (_) {},
              onReminder: (_) {},
            ),
          ),
        );
        expect(find.text('Открытых задач: 47'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Ближайшее напоминание'),
          200,
        );
        expect(find.text('Ближайшее напоминание'), findsOneWidget);
        expect(find.textContaining('Синтетическое напоминание'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          MaterialApp(
            theme: assistantTheme(tokens, brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: TaskScreen(controller: h.c, onBack: () {}),
          ),
        );
        await tester.scrollUntilVisible(find.text('Завершить задачу'), 200);
        await tester.tap(find.text('Завершить задачу'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Отмена'));
        await tester.pumpAndSettle();
        expect(h.t.requests.where((r) => r.method == 'POST'), isEmpty);
        expect(tester.takeException(), isNull);
        h.c.detailPhase = TodayPhase.offline;
        await tester.pumpWidget(const SizedBox());
        h.dispose();
      },
    );
  }
  testWidgets('saved state has read-only label and disabled command', (
    tester,
  ) async {
    final h = TodayHarness();
    await h.enter();
    h.c.detailPhase = TodayPhase.offline;
    h.c.phase = TodayPhase.offline;
    await tester.pumpWidget(
      MaterialApp(
        home: TaskScreen(controller: h.c, onBack: () {}),
      ),
    );
    final button = tester.widget<FilledButton>(find.byType(FilledButton).first);
    expect(button.onPressed, isNull);
    expect(find.text('Сохранённые данные · Только чтение'), findsOneWidget);
    expect(find.textContaining('Дата: 2026-10-31'), findsOneWidget);
    expect(find.textContaining('00:00:00'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    h.dispose();
  });
}
