import 'dart:async';

import '../api/api_client.dart';
import '../platform/platform_gateway.dart';
import 'session_memory.dart';

class LogoutCoordinator {
  final PlatformGateway platform;
  final SessionMemory memory;
  final MobileApi normalApi;
  final MobileApi Function(SessionDto? Function()) dedicatedApi;
  final Future<void> Function(bool) recordResult;
  LogoutCoordinator(
    this.platform,
    this.memory,
    this.normalApi,
    this.dedicatedApi, {
    required this.recordResult,
  });
  Future<bool>? _flight;
  Future<bool> logout() => _flight ??= _run();
  Future<bool> _run() async {
    SessionDto? retained = memory.unlocked ? memory.current : null;
    final deadline = Stopwatch()..start();
    memory.lock(NativeLockEvent(memory.nativeEpoch + 1));
    normalApi.cancelPrivateRequests();
    MobileApi? revoke;
    bool confirmed = false;
    StreamSubscription<NativeLockEvent>? subscription;
    try {
      await platform.clearLocalState(LocalClearPhase.cover);
      subscription = platform.lockEvents.listen((_) {
        retained = null;
        revoke?.cancelPrivateRequests();
      });
      if (retained != null && deadline.elapsedMilliseconds < 5000) {
        revoke = dedicatedApi(() => retained);
        await revoke
            .call(ApiOperation.revokeSelfDevice, actionKey: newActionKey())
            .timeout(
              Duration(milliseconds: 5000 - deadline.elapsedMilliseconds),
            );
        confirmed = true;
      }
    } catch (_) {
      confirmed = false;
    } finally {
      revoke?.cancelPrivateRequests();
      retained = null;
      await subscription?.cancel();
      try {
        await platform.clearLocalState(LocalClearPhase.destroy);
      } finally {
        await recordResult(confirmed);
      }
    }
    return confirmed;
  }
}
