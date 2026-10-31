import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/platform/platform_gateway.dart';

import 'dart:io';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/cache/domain_cache.dart';
import '../../core/platform/domain_platform.dart';
import 'domain_models.dart';

abstract interface class TodayRepository {
  Future<Dashboard> dashboard({String? cursor});
  Future<TaskDto> task(String id);
  Future<ReminderDto> reminder(String id);
  Future<MutationReceipt> complete(
    String id,
    int version,
    String key, {
    required void Function() checkAdmission,
  });
  Future<MutationReceipt> snooze10(
    String id,
    int version,
    String key, {
    required void Function() checkAdmission,
  });
  Future<MutationReceipt?> mutation(String key);
}

class ApiTodayRepository implements TodayRepository {
  final ApiClient api;
  final DomainCache cache;
  final DomainPlatform domain;
  int viewGeneration = 0;
  bool lastDashboardCached = true;
  final Map<ApiOperation, ({String id, String at})> _detailSync = {};
  String? detailSyncedAt(String id, bool reminder) {
    final read =
        _detailSync[reminder ? ApiOperation.getReminder : ApiOperation.getTask];
    return read?.id == id ? read?.at : null;
  }

  void clearPrivateMetadata() {
    _detailSync.clear();
  }

  int _readBarrier = 0;
  final Map<ApiOperation, int> _families = {};
  StreamSubscription<int>? _denials;
  ApiTodayRepository(this.api, this.cache, this.domain) {
    if (api.platform case final DomainAccessAuthority authority) {
      _denials = authority.domainDenials.listen((_) {
        _readBarrier++;
        _families.clear();
        clearPrivateMetadata();
      });
    }
  }
  void dispose() {
    _denials?.cancel();
    clearPrivateMetadata();
  }

  Future<T> _read<T>(
    ApiOperation op,
    T Function(Map<String, Object?>) decode, {
    String? id,
    String? cursor,
    int generation = 0,
  }) async {
    final barrier = _readBarrier;
    final family = (_families[op] ?? 0) + 1;
    _families[op] = family;
    bool current() => barrier == _readBarrier && _families[op] == family;
    final ticket = await domain.beginDomainRead(
      op,
      resourceId: id,
      cursor: cursor,
      viewGeneration: generation,
    );
    try {
      if (!current()) throw const DomainReadSuperseded();
      final result = await api.callResult(
        op,
        resourceId: id,
        query: op == ApiOperation.getDashboard
            ? {'limit': '20', 'cursor': ?cursor}
            : const {},
      );
      if (!current()) throw const DomainReadSuperseded();
      final dto = decode(result.body);
      final ack = await cache.commit(ticket, result);
      if (!current()) throw const DomainReadSuperseded();
      if (op == ApiOperation.getDashboard) lastDashboardCached = ack.cached;
      if (op == ApiOperation.getReminder) {
        // A newly accepted detail is a barrier for outstanding list snapshots,
        // including equal-version derived warning and terminal-state changes.
        _families[ApiOperation.getDashboard] =
            (_families[ApiOperation.getDashboard] ?? 0) + 1;
      }
      if (op == ApiOperation.getTask || op == ApiOperation.getReminder) {
        _detailSync[op] = (
          id: id!,
          at: HttpDate.parse(result.headers['date']!).toUtc().toIso8601String(),
        );
      }
      return dto;
    } catch (e) {
      await domain.cancelDomainRead(ticket);
      if (e is PlatformException && e.code == 'DOMAIN_READ_SUPERSEDED') {
        throw const DomainReadSuperseded();
      }
      rethrow;
    }
  }

  Future<Device> verifyDevice() {
    _readBarrier++;
    return _read(ApiOperation.getSelfDevice, Device.fromJson);
  }

  @override
  Future<Dashboard> dashboard({String? cursor}) async {
    // Allocate the logical view before any await: an older eligibility read
    // cannot later overtake a newer refresh and mint the newest generation.
    if (cursor == null) {
      viewGeneration++;
      _readBarrier++;
    }
    final generation = viewGeneration;
    var barrier = _readBarrier;
    final frame = await cache.read();
    if (barrier != _readBarrier || generation != viewGeneration) {
      throw const DomainReadSuperseded();
    }
    if (frame.policyDenied) {
      final verification = verifyDevice();
      barrier = _readBarrier;
      await verification;
      if (barrier != _readBarrier || generation != viewGeneration) {
        throw const DomainReadSuperseded();
      }
    }
    return _read(
      ApiOperation.getDashboard,
      Dashboard.fromJson,
      cursor: cursor,
      generation: generation,
    );
  }

  @override
  Future<TaskDto> task(String id) => _read(ApiOperation.getTask, (j) {
    final dto = TaskDto.fromJson(j);
    if (dto.id != id) throw const FormatException('Foreign task');
    return dto;
  }, id: id);
  @override
  Future<ReminderDto> reminder(String id) =>
      _read(ApiOperation.getReminder, (j) {
        final dto = ReminderDto.fromJson(j);
        if (dto.id != id) throw const FormatException('Foreign reminder');
        return dto;
      }, id: id);
  @override
  Future<MutationReceipt> complete(
    String id,
    int version,
    String key, {
    required void Function() checkAdmission,
  }) async => MutationReceipt.fromJson(
    (await api.callResult(
      ApiOperation.completeTask,
      resourceId: id,
      actionKey: key,
      body: {'expected_version': version},
      checkAdmission: checkAdmission,
    )).body,
  );
  @override
  Future<MutationReceipt> snooze10(
    String id,
    int version,
    String key, {
    required void Function() checkAdmission,
  }) async => MutationReceipt.fromJson(
    (await api.callResult(
      ApiOperation.snoozeReminder,
      resourceId: id,
      actionKey: key,
      body: {'expected_version': version, 'delay_minutes': 10},
      checkAdmission: checkAdmission,
    )).body,
  );
  @override
  Future<MutationReceipt?> mutation(String key) async {
    try {
      return MutationReceipt.fromJson(
        await api.call(ApiOperation.getMutation, resourceId: key),
      );
    } on ApiError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }
}
