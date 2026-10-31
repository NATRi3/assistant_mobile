import 'dart:async';

import 'package:flutter/services.dart';

import '../config/app_config.dart';
import 'platform_gateway.dart';

class MethodChannelGateway implements PlatformGateway {
  static const _channel = MethodChannel('assistant.platform/v1');
  final _locks = StreamController<NativeLockEvent>.broadcast(sync: true);
  MethodChannelGateway() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'locked') {
        final j = Map<String, Object?>.from(call.arguments as Map);
        _locks.add(NativeLockEvent(j['native_epoch']! as int));
      }
    });
  }
  Future<Map<String, Object?>> bootstrap(AppConfig config) async {
    final j = await _map('bootstrap', null);
    if (j['api_origin'] != (config.apiOrigin?.toString() ?? '')) {
      throw StateError('Native origin mismatch');
    }
    return j;
  }

  Future<Map<String, Object?>> _map(String method, Object? args) async =>
      Map<String, Object?>.from(
        (await _channel.invokeMethod<Map>(method, args))!,
      );
  @override
  Stream<NativeLockEvent> get lockEvents => _locks.stream;
  @override
  Future<UnlockResult> unlockAndReadSession() async {
    final j = await _map('unlockAndReadSession', null);
    return UnlockResult(
      j['native_epoch']! as int,
      j['session'] == null
          ? null
          : SessionDto.fromJson(
              Map<String, Object?>.from(j['session']! as Map),
            ),
    );
  }

  @override
  Future<PublicDeviceKey> createDeviceKey() async {
    final j = await _map('createDeviceKey', null);
    return PublicDeviceKey(
      Map<String, Object?>.from(j['jwk']! as Map),
      j['fingerprint']! as String,
    );
  }

  @override
  Future<String> signDpop(DpopMetadata value) async =>
      (await _channel.invokeMethod<String>('signDpop', {
        'operation_id': value.operation.name,
        'resource_id': value.resourceId,
        'access_token': value.accessToken,
      }))!;
  @override
  Future<void> writePrivateCache(PrivateCacheWrite v) =>
      _channel.invokeMethod<void>('writePrivateCache', {
        'slot': v.slot.name,
        'value': v.value,
        'native_epoch': v.nativeEpoch,
        'expected_revision': v.expectedRevision,
      });
  @override
  Future<PrivateCacheRead?> readPrivateCache(CacheSlot slot) async {
    final raw = await _channel.invokeMethod<Map>('readPrivateCache', {
      'slot': slot.name,
    });
    if (raw == null) return null;
    final j = Map<String, Object?>.from(raw);
    return PrivateCacheRead(
      Map<String, Object?>.from(j['value']! as Map),
      timestamp(j['synced_at']),
      j['revision']! as int,
    );
  }

  @override
  Future<void> clearLocalState(LocalClearPhase phase) =>
      _channel.invokeMethod<void>('clearLocalState', {'phase': phase.name});
  Future<void> acknowledgeCover(int epoch) async {
    try {
      await _channel.invokeMethod<void>('acknowledgeCover', {
        'native_epoch': epoch,
      });
    } on PlatformException {
      /* A newer native epoch keeps the cover in place. */
    }
  }

  Future<void> recordRevokeResult(bool confirmed) => _channel
      .invokeMethod<void>('recordRevokeResult', {'confirmed': confirmed});
}
