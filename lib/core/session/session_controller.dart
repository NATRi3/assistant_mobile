import 'dart:async';

import '../platform/platform_gateway.dart';
import '../api/api_client.dart';
import 'session_memory.dart';

class SessionController {
  final PlatformGateway platform;
  final SessionMemory memory;
  final MobileApi api;
  late final StreamSubscription<NativeLockEvent> _subscription;
  SessionController(this.platform, this.memory, this.api) {
    _subscription = platform.lockEvents.listen((e) {
      memory.lock(e);
      api.cancelPrivateRequests();
    });
  }
  Future<void> unlock() async {
    final result = await platform.unlockAndReadSession();
    memory.adopt(result);
  }

  Future<void> dispose() => _subscription.cancel();
}

class SessionStore {
  final PlatformGateway platform;
  final SessionMemory memory;
  SessionStore(this.platform, this.memory);
  void check(int epoch) {
    if (!memory.unlocked || memory.nativeEpoch != epoch) {
      throw StateError('Locked');
    }
  }

  Future<PrivateCacheRead?> read(int epoch) async {
    check(epoch);
    final value = await platform.readPrivateCache(CacheSlot.session);
    check(epoch);
    return value;
  }

  Future<void> write(
    Map<String, Object?> envelope,
    int epoch,
    int revision,
  ) async {
    check(epoch);
    await platform.writePrivateCache(
      PrivateCacheWrite(
        CacheSlot.session,
        envelope,
        nativeEpoch: epoch,
        expectedRevision: revision,
      ),
    );
    check(epoch);
  }

  Future<void> install(SessionDto dto, int epoch, {int? revision}) async {
    final old = revision == null ? await read(epoch) : null;
    await write(
      {'session': dto.toJson(), 'pending_refresh': null},
      epoch,
      revision ?? old?.revision ?? 0,
    );
    memory.install(dto, epoch);
  }
}
