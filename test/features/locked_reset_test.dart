import 'dart:convert';

import 'package:assistant/app.dart';
import 'package:assistant/core/api/api_client.dart';
import 'package:assistant/core/config/app_config.dart';
import 'package:assistant/core/platform/platform_gateway.dart';
import 'package:assistant/features/device/device_screen.dart';
import 'package:assistant/features/pairing/pairing_screen.dart';
import 'package:assistant/theme/token_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/fixtures.dart';

void main() {
  testWidgets(
    'newly paired then locked reset retains only public revoke guidance',
    (tester) async {
      final p = FakePlatform(), t = FakeTransport();
      final expires = DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 5))
          .toIso8601String();
      t.handler = (request) async {
        if (request.uri.path.endsWith('/complete')) {
          return ApiResponse(
            200,
            {},
            utf8.encode(jsonEncode(fixtureSession().toJson())),
          );
        }
        if (request.method == 'GET') {
          return ApiResponse(
            200,
            {},
            utf8.encode(
              jsonEncode({
                'pairing_id': deviceId,
                'status': 'approved',
                'expires_at': expires,
                'poll_after_seconds': 3,
              }),
            ),
          );
        }
        return ApiResponse(
          201,
          {},
          utf8.encode(
            jsonEncode({
              'pairing_id': deviceId,
              'code': 'ABCDEFG2',
              'fingerprint': 'A' * 43,
              'expires_at': expires,
              'poll_after_seconds': 3,
            }),
          ),
        );
      };
      await tester.pumpWidget(
        AssistantApp(
          config: AppConfig.parse('https://mobile.example.invalid'),
          tokens: await DesignTokens.load(),
          platform: p,
          transport: t,
          // First launch: no public UUID has been received from native bootstrap.
        ),
      );
      await tester.tap(find.text('Разблокировать и подключить'));
      await tester.pumpAndSettle();
      expect(find.text('ABCDEFG2'), findsOneWidget);
      // The real controller uses wall-clock time for its minimum polling interval.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 3)),
      );
      await tester.tap(find.text('Проверить подтверждение'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Завершить подключение'));
      await tester.pumpAndSettle();
      expect(find.byType(DeviceScreen), findsOneWidget);

      p.unlocked = false;
      p.events.add(const NativeLockEvent(8));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<PairingScreen>(find.byType(PairingScreen))
          .controller;
      expect(controller.memory.current, isNull);
      expect(controller.memory.unlocked, isFalse);
      final requestsBeforeReset = t.requests.length;
      await tester.tap(find.text('Сбросить локальное подключение'));
      // Stream cancellation completes on the real event loop before destroy.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(p.keyExists, isFalse);
      expect(p.saved, isNull);
      expect(controller.memory.current, isNull);
      expect(t.requests.length, requestsBeforeReset);
      expect(
        find.textContaining('серверный отзыв не подтверждён'),
        findsWidgets,
      );
      expect(find.textContaining('/mobile_revoke $deviceId'), findsOneWidget);
      expect(find.textContaining(fixtureSession().accessToken), findsNothing);
      expect(find.textContaining(fixtureSession().refreshToken), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await p.events.close();
    },
  );
}
