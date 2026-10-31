import 'package:flutter/material.dart';

import 'core/api/api_client.dart';
import 'core/config/app_config.dart';
import 'core/platform/method_channel_gateway.dart';
import 'core/platform/platform_gateway.dart';
import 'core/session/session_memory.dart';
import 'core/session/session_controller.dart';
import 'core/session/logout_coordinator.dart';
import 'features/pairing/pairing_controller.dart';
import 'features/pairing/pairing_screen.dart';
import 'features/device/device_screen.dart';
import 'theme/assistant_theme.dart';
import 'theme/token_loader.dart';

class AssistantApp extends StatefulWidget {
  final AppConfig config;
  final DesignTokens tokens;
  final PlatformGateway platform;
  final ApiTransport transport;
  final String? initialWarning;
  final String? initialDeviceId;
  final int initialNativeEpoch;
  const AssistantApp({
    super.key,
    required this.config,
    required this.tokens,
    required this.platform,
    required this.transport,
    this.initialWarning,
    this.initialDeviceId,
    this.initialNativeEpoch = 0,
  });
  @override
  State<AssistantApp> createState() => _AssistantAppState();
}

class _AssistantAppState extends State<AssistantApp> {
  late final SessionMemory memory;
  late final ApiClient api;
  late final PairingController pairing;
  String? warning;
  // Public recovery metadata only; session credentials still clear on lock.
  String? ownedDeviceId;
  bool closing = false;
  @override
  void initState() {
    super.initState();
    warning = widget.initialWarning;
    ownedDeviceId = widget.initialDeviceId;
    memory = SessionMemory();
    if (widget.initialNativeEpoch > 0) {
      memory.lock(NativeLockEvent(widget.initialNativeEpoch));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _changed();
      }
    });
    api = ApiClient(widget.config, widget.platform, widget.transport, memory);
    pairing = PairingController(
      widget.config,
      api,
      widget.platform,
      memory,
      SessionStore(widget.platform, memory),
    );
    pairing.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    ownedDeviceId = memory.current?.deviceId ?? ownedDeviceId;
    setState(() {});
    if (widget.platform case final MethodChannelGateway native) {
      if (!memory.unlocked) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          native.acknowledgeCover(memory.nativeEpoch);
        });
      }
    }
  }

  Future<void> logout() async {
    if (closing) return;
    closing = true;
    final id = memory.current?.deviceId ?? ownedDeviceId;
    pairing.coverForLogout();
    final coordinator = LogoutCoordinator(
      widget.platform,
      memory,
      api,
      (session) => ApiClient(
        widget.config,
        widget.platform,
        HttpTransport(),
        memory,
        revokeSession: session,
      ),
      recordResult: (confirmed) async {
        if (widget.platform case final MethodChannelGateway native) {
          await native.recordRevokeResult(confirmed);
        }
      },
    );
    final confirmed = await coordinator.logout();
    if (!mounted) return;
    setState(() {
      warning = confirmed
          ? 'Телефон отключён. Серверный отзыв подтверждён.'
          : 'Телефон отключён здесь; серверный отзыв не подтверждён${id == null ? '' : '. В личном Telegram: /mobile_revoke $id'}';
      closing = false;
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Ассистент',
    theme: assistantTheme(widget.tokens, Brightness.light),
    darkTheme: assistantTheme(widget.tokens, Brightness.dark),
    home: pairing.phase == PairingPhase.paired && memory.current != null
        ? DeviceScreen(deviceId: memory.current!.deviceId, onLogout: logout)
        : PairingScreen(
            controller: pairing,
            logoutWarning: warning,
            onReset: logout,
          ),
  );
  @override
  void dispose() {
    pairing.removeListener(_changed);
    pairing.dispose();
    memory.dispose();
    api.cancelPrivateRequests();
    super.dispose();
  }
}
