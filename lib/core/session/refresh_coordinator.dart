import '../api/api_client.dart';
import '../api/api_error.dart';
import '../platform/platform_gateway.dart';
import 'session_memory.dart';
import 'session_controller.dart';

class RefreshCoordinator {
  final MobileApi api;
  final SessionMemory memory;
  final SessionStore store;
  final DateTime Function() now;
  RefreshCoordinator(
    this.api,
    this.memory,
    this.store, {
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  Future<SessionDto>? _flight;
  Future<SessionDto> resumeOrRefresh() {
    if (_flight != null) return _flight!;
    final f = _run();
    _flight = f;
    f.then(
      (_) {
        _flight = null;
      },
      onError: (Object _, StackTrace _) {
        _flight = null;
      },
    );
    return f;
  }

  Future<SessionDto> _run() async {
    final epoch = memory.nativeEpoch;
    store.check(epoch);
    final dto = memory.current;
    if (dto == null) throw StateError('No session');
    final stored = await store.read(epoch);
    var revision = stored?.revision ?? 0;
    final existing = stored?.value['pending_refresh'];
    final pending = existing == null
        ? <String, Object?>{
            'action_key': newActionKey(),
            'refresh_token': dto.refreshToken,
            'started_at': now().toUtc().toIso8601String(),
          }
        : Map<String, Object?>.from(existing as Map);
    final started = timestamp(pending['started_at']);
    final age = now().difference(started);
    if (age.isNegative ||
        age >= const Duration(seconds: 60) ||
        now().isAfter(dto.refreshExpiresAt)) {
      memory.lock(NativeLockEvent(epoch));
      api.cancelPrivateRequests();
      throw const ApiError(401, 'REPAIR_REQUIRED');
    }
    if (existing == null) {
      await store.write(
        {'session': dto.toJson(), 'pending_refresh': pending},
        epoch,
        revision,
      );
      revision++;
    }
    try {
      final result = SessionDto.fromJson(
        await api.call(
          ApiOperation.refreshSession,
          actionKey: pending['action_key']! as String,
          body: {'refresh_token': pending['refresh_token']},
        ),
      );
      if (result.deviceId != dto.deviceId ||
          result.deviceVersion != dto.deviceVersion) {
        throw const FormatException('Foreign session');
      }
      await store.install(result, epoch, revision: revision);
      return result;
    } on ApiError catch (e) {
      if (e.status == 401) {
        memory.lock(NativeLockEvent(epoch));
        api.cancelPrivateRequests();
      }
      rethrow;
    }
  }
}
