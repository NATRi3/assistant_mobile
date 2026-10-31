import 'dart:async';

import 'package:assistant/core/api/api_client.dart';
import 'package:assistant/core/platform/platform_gateway.dart';

class FakePlatform implements PlatformGateway {
  final events = StreamController<NativeLockEvent>.broadcast(sync: true);
  final List<String> trace = [];
  PrivateCacheRead? saved;
  int epoch = 7;
  Future<UnlockResult> Function()? unlockHandler;
  bool unlocked = true;
  bool keyExists = true;
  bool closing = false;
  @override
  Stream<NativeLockEvent> get lockEvents => events.stream;
  @override
  Future<UnlockResult> unlockAndReadSession() async => unlockHandler != null
      ? await unlockHandler!()
      : UnlockResult(
          epoch,
          saved?.value['session'] == null
              ? null
              : SessionDto.fromJson(
                  Map<String, Object?>.from(saved!.value['session']! as Map),
                ),
        );
  @override
  Future<PublicDeviceKey> createDeviceKey() async => const PublicDeviceKey({
    'kty': 'EC',
    'crv': 'P-256',
    'x': 'x',
    'y': 'y',
  }, 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
  @override
  Future<String> signDpop(DpopMetadata v) async {
    trace.add('sign:${v.operation.name}');
    if (!keyExists ||
        !unlocked ||
        (closing && v.operation != ApiOperation.revokeSelfDevice)) {
      throw StateError('Locked');
    }
    return 'proof';
  }

  @override
  Future<PrivateCacheRead?> readPrivateCache(CacheSlot slot) async {
    if (!unlocked || closing) throw StateError('Locked');
    return saved;
  }

  @override
  Future<void> writePrivateCache(PrivateCacheWrite v) async {
    if (v.nativeEpoch != epoch ||
        !unlocked ||
        closing ||
        v.expectedRevision != (saved?.revision ?? 0)) {
      throw StateError('Fence');
    }
    saved = PrivateCacheRead(
      v.value,
      DateTime.utc(2026, 10, 31, 12),
      v.expectedRevision + 1,
    );
    trace.add('persist');
  }

  @override
  Future<void> clearLocalState(LocalClearPhase phase) async {
    trace.add(phase.name);
    if (phase == LocalClearPhase.cover) {
      closing = true;
    } else {
      keyExists = false;
      saved = null;
      unlocked = false;
    }
  }
}

class FakeTransport implements ApiTransport {
  final List<ApiRequest> requests = [];
  bool aborted = false;
  Future<ApiResponse> Function(ApiRequest)? handler;
  @override
  Future<ApiResponse> send(ApiRequest request) {
    requests.add(request);
    return handler!(request);
  }

  @override
  void abortAll() {
    aborted = true;
  }
}

class FakeApi implements MobileApi {
  final List<({ApiOperation op, String? key, Map<String, Object?> body})>
  calls = [];
  Future<Map<String, Object?>> Function(
    ApiOperation,
    String?,
    Map<String, Object?>,
  )?
  handler;
  @override
  Future<Map<String, Object?>> call(
    ApiOperation op, {
    String? resourceId,
    Map<String, Object?> body = const {},
    Map<String, String> query = const {},
    String? actionKey,
  }) {
    calls.add((op: op, key: actionKey, body: body));
    return handler!(op, actionKey, body);
  }

  @override
  void cancelPrivateRequests() {}
}
