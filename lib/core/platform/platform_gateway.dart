import '../api/operation.dart';
import '../api/wire_models.dart';
export '../api/wire_models.dart';

abstract interface class PlatformGateway {
  Future<UnlockResult> unlockAndReadSession();
  Future<PublicDeviceKey> createDeviceKey();
  Future<String> signDpop(DpopMetadata metadata);
  Future<void> writePrivateCache(PrivateCacheWrite value);
  Future<PrivateCacheRead?> readPrivateCache(CacheSlot slot);
  Future<void> clearLocalState(LocalClearPhase phase);
  Stream<NativeLockEvent> get lockEvents;
}

// Native policy denial is shared across all current controllers and persisted.
abstract interface class DomainAccessAuthority {
  Stream<int> get domainDenials;
  Future<void> denyDomainAccess(int nativeEpoch);
}

enum LocalClearPhase { cover, destroy }

enum CacheSlot { session, domain }

class UnlockResult {
  final int nativeEpoch;
  final SessionDto? session;
  const UnlockResult(this.nativeEpoch, this.session);
}

class NativeLockEvent {
  final int nativeEpoch;
  const NativeLockEvent(this.nativeEpoch);
}

class PublicDeviceKey {
  final Map<String, Object?> jwk;
  final String fingerprint;
  const PublicDeviceKey(this.jwk, this.fingerprint);
}

class DpopMetadata {
  final ApiOperation operation;
  final String? resourceId, accessToken;
  const DpopMetadata(this.operation, {this.resourceId, this.accessToken});
  @override
  String toString() => 'DpopMetadata([redacted])';
}

class PrivateCacheWrite {
  final CacheSlot slot;
  final Map<String, Object?> value;
  final int nativeEpoch, expectedRevision;
  const PrivateCacheWrite(
    this.slot,
    this.value, {
    required this.nativeEpoch,
    required this.expectedRevision,
  });
  @override
  String toString() => 'PrivateCacheWrite([redacted])';
}

class PrivateCacheRead {
  final Map<String, Object?> value;
  final DateTime syncedAt;
  final int revision;
  const PrivateCacheRead(this.value, this.syncedAt, this.revision);
  @override
  String toString() => 'PrivateCacheRead([redacted])';
}
