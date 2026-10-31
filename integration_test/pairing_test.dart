import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:assistant/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('default installed APK exposes only unconfigured pairing', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();
    expect(
      find.text('Сервер ассистента не настроен. Подключение недоступно.'),
      findsOneWidget,
    );
    expect(find.text('Телефон подключён'), findsNothing);
  });
}
