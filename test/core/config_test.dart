import 'package:flutter_test/flutter_test.dart';
import 'package:assistant/core/config/app_config.dart';

void main() {
  test(
    'unconfigured is inert; credentials cannot select a different origin',
    () {
      expect(AppConfig.parse('').configured, isFalse);
      for (final raw in [
        'http://mobile.example.invalid',
        'https://user:pass@mobile.example.invalid',
        'https://mobile.example.invalid/private?token=x',
      ]) {
        expect(() => AppConfig.parse(raw), throwsFormatException);
      }
      expect(
        AppConfig.parse('https://mobile.example.invalid').configured,
        isTrue,
      );
    },
  );
}
