import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/platform/domain_platform.dart';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/cache/domain_cache.dart';
import '../../core/platform/platform_gateway.dart';
import '../../core/recovery/action_recovery.dart';
import '../../core/recovery/pending_action.dart';
import '../../core/session/session_memory.dart';
import 'domain_models.dart';
import 'today_repository.dart';

enum TodayPhase {
  loading,
  fresh,
  empty,
  offline,
  stale,
  conflict,
  unknown,
  paused,
  unavailable,
  error,
  locked,
}

class TodayController extends ChangeNotifier {
  final TodayRepository repository;
  final DomainCache cache;
  final SessionMemory memory;
  final ActionRecovery? recovery;
  TodayPhase phase = TodayPhase.loading, detailPhase = TodayPhase.loading;
  Dashboard? dashboard;
  List<TaskDto> tasks = [];
  TaskDto? selectedTask;
  ReminderDto? selectedReminder;
  List<PendingAction> pending = [];
  String? message, detailMessage, lastSync, detailLastSync;
  bool loadingMore = false;
  int _busySerial = 0;
  int? _busyOwner;
  bool get busy => _busyOwner != null;
  int _claimBusy() {
    final owner = ++_busySerial;
    _busyOwner = owner;
    return owner;
  }

  void _invalidateBusy() {
    _busyOwner = null;
  }

  void _releaseBusy(int owner) {
    if (_busyOwner == owner) {
      _busyOwner = null;
      _emit();
    }
  }

  int _view = 0, _detail = 0, _scope = 0;
  bool _disposed = false;
  String? detailResourceId;
  bool detailIsReminder = false;
  final Set<String> _checkedAbsent = {};
  final Map<String, TaskDto> _taskEntities = {};
  StreamSubscription<int>? _denials;
  bool _membershipUncertain = false;
  void _hideDenied() {
    _view++;
    _detail++;
    _scope++;
    _invalidateBusy();
    dashboard = null;
    tasks = [];
    _taskEntities.clear();
    selectedTask = null;
    selectedReminder = null;
    pending = [];
    detailResourceId = null;
    lastSync = null;
    detailLastSync = null;
    _checkedAbsent.clear();
    loadingMore = false;
    if (repository is ApiTodayRepository) {
      (repository as ApiTodayRepository).clearPrivateMetadata();
    }
    phase = TodayPhase.paused;
    detailPhase = TodayPhase.paused;
    message = 'Ассистент приостановлен владельцем.';
    detailMessage = message;
    _emit();
  }

  bool _superseded(Object e) =>
      e is DomainReadSuperseded ||
      (e is PlatformException && e.code == 'DOMAIN_READ_SUPERSEDED');
  TaskDto _canonicalTask(TaskDto next) {
    final prior = _taskEntities[next.id];
    if (prior != null && prior.entityVersion > next.entityVersion) return prior;
    _taskEntities[next.id] = next;
    return next;
  }

  void _mergeTaskDetail(TaskDto next) {
    final current = _canonicalTask(next);
    final wasListed =
        tasks.any((t) => t.id == current.id) ||
        (dashboard?.tasks.any((t) => t.id == current.id) ?? false);
    tasks = [
      for (final t in tasks)
        if ((t.id == current.id ? current : t).status == 'open')
          t.id == current.id ? current : t,
    ];
    if (selectedTask?.id == current.id) selectedTask = current;
    if (dashboard case final d?) {
      dashboard = null;
      try {
        dashboard = Dashboard.fromCacheJson({
          ...d.json,
          'tasks': [
            for (final t in d.tasks)
              if ((t.id == current.id ? current : t).status == 'open')
                (t.id == current.id ? current : t).toJson(),
          ],
        });
      } on FormatException {
        _membershipUncertain = true;
        phase = TodayPhase.stale;
        message = 'Задача обновлена. Обновите список и счётчик.';
      }
      if (current.status != 'open' && wasListed) {
        _membershipUncertain = true;
        phase = TodayPhase.stale;
        message = 'Состояние задачи изменилось. Обновите список и счётчик.';
      }
    }
  }

  void _mergeReminderDetail(ReminderDto next) {
    final d = dashboard, r = d?.nearestReminder;
    if (d != null &&
        r?.id == next.id &&
        (r!.entityVersion != next.entityVersion ||
            r.dueAt != next.dueAt ||
            r.sourceWarning != next.sourceWarning ||
            next.status != 'scheduled' ||
            next.json['active'] != true)) {
      dashboard = Dashboard.fromCacheJson({
        ...d.json,
        'nearest_reminder': null,
      });
      phase = TodayPhase.stale;
      _membershipUncertain = true;
      message = 'Ближайшее напоминание изменилось. Обновите список.';
    }
  }

  TodayController(this.repository, this.cache, this.memory, {this.recovery}) {
    memory.addListener(_sessionChanged);
    if (cache.platform case final DomainAccessAuthority authority) {
      _denials = authority.domainDenials.listen((epoch) {
        if (_active(epoch)) _hideDenied();
      });
    }
  }
  bool get online => phase == TodayPhase.fresh || phase == TodayPhase.empty;
  bool get detailOnline => detailPhase == TodayPhase.fresh;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _sessionChanged() {
    if (!memory.unlocked) {
      _view++;
      _detail++;
      _scope++;
      _invalidateBusy();
      dashboard = null;
      tasks = [];
      _taskEntities.clear();
      selectedTask = null;
      selectedReminder = null;
      detailResourceId = null;
      detailLastSync = null;
      if (repository is ApiTodayRepository) {
        (repository as ApiTodayRepository).clearPrivateMetadata();
      }
      pending = [];
      lastSync = null;
      message = null;
      detailMessage = null;
      _checkedAbsent.clear();
      loadingMore = false;
      phase = TodayPhase.locked;
      detailPhase = TodayPhase.locked;
      _emit();
    }
  }

  bool _active(int epoch) =>
      !_disposed && memory.unlocked && memory.nativeEpoch == epoch;
  bool _sameScope(int scope) => scope == _scope;
  void _adopt(Dashboard next) {
    final old = dashboard;
    if (old != null &&
        (next.contextEpoch < old.contextEpoch ||
            next.preferences.ownerPolicyVersion <
                old.preferences.ownerPolicyVersion)) {
      throw const FormatException('Scope regression');
    }
    if (old == null ||
        next.contextEpoch != old.contextEpoch ||
        next.preferences.ownerPolicyVersion !=
            old.preferences.ownerPolicyVersion) {
      _scope++;
      _invalidateBusy();
      _detail++;
      selectedTask = null;
      selectedReminder = null;
      detailPhase = TodayPhase.stale;
      _checkedAbsent.clear();
      _taskEntities.clear();
    }
    final resolved = next.tasks.map(_canonicalTask).toList();
    _membershipUncertain =
        resolved.any((t) => t.status != 'open') ||
        Iterable<int>.generate(
          next.tasks.length,
        ).any((i) => resolved[i].entityVersion > next.tasks[i].entityVersion);
    tasks = resolved.where((t) => t.status == 'open').toList();
    dashboard = Dashboard.fromCacheJson({
      ...next.json,
      'tasks': tasks.map((t) => t.toJson()).toList(),
    });
    if (selectedTask case final selected?) {
      selectedTask = _taskEntities[selected.id] ?? selected;
    }
    lastSync = next.serverTime;
  }

  Future<void> _pending() async {
    final epoch = memory.nativeEpoch, scope = _scope;
    final frame = await cache.read();
    if (!_active(epoch) || !_sameScope(scope)) return;
    pending = frame.pending.values
        .map((v) => PendingAction.fromJson(objectJson(v)))
        .toList(growable: false);
  }

  Future<void> refresh() async {
    if (!memory.unlocked) return;
    final view = ++_view, epoch = memory.nativeEpoch;
    phase = dashboard == null ? TodayPhase.loading : TodayPhase.stale;
    message = null;
    _emit();
    try {
      final next = await repository.dashboard();
      if (!_active(epoch) || view != _view) return;
      _adopt(next);
      await _pending();
      if (!_active(epoch) || view != _view) return;
      phase = _membershipUncertain
          ? TodayPhase.stale
          : tasks.isEmpty && next.totalOpenCount == 0
          ? TodayPhase.empty
          : TodayPhase.fresh;
      if (repository is ApiTodayRepository &&
          !(repository as ApiTodayRepository).lastDashboardCached) {
        message = 'Офлайн-данные не сохранены';
      }
    } catch (e) {
      if (!_active(epoch) || view != _view) return;
      if (!_superseded(e)) await _readFailure(e, view, epoch);
    }
    if (_active(epoch) && view == _view) _emit();
  }

  Future<void> _readFailure(Object e, int view, int epoch) async {
    if (await _denial(e)) return;
    // Only native eligible per-entry data can be a read-only fallback.
    try {
      final frame = await cache.read();
      if (!_active(epoch) || view != _view) return;
      if (frame.policyDenied) {
        _hideDenied();
        return;
      }
      if (frame.dashboard != null) {
        _adopt(Dashboard.fromCacheJson(frame.dashboard!));
        lastSync = frame.lastSync;
        phase = frame.needsSync ? TodayPhase.stale : TodayPhase.offline;
        message =
            'Сохранённые данные · Только чтение. Не удалось обновить данные.';
        return;
      }
    } catch (_) {
      /* No private fallback if native eligibility fails. */
    }
    dashboard = null;
    tasks = [];
    phase = TodayPhase.error;
    message = _errorCopy(e);
  }

  Future<bool> _denial(Object e) async {
    final paused =
        (e is ApiError && e.status == 403) ||
        (e is PlatformException && e.code == 'DOMAIN_ACCESS_DENIED');
    if (paused) {
      if (cache.platform case final DomainAccessAuthority authority) {
        await authority.denyDomainAccess(memory.nativeEpoch);
      }
      _hideDenied();
      return true;
    }
    if (e is ApiError && e.status == 401) {
      dashboard = null;
      tasks = [];
      _taskEntities.clear();
      selectedTask = null;
      selectedReminder = null;
      detailResourceId = null;
      detailLastSync = null;
      if (repository is ApiTodayRepository) {
        (repository as ApiTodayRepository).clearPrivateMetadata();
      }
      pending = [];
      lastSync = null;
      _scope++;
      _invalidateBusy();
      _detail++;
      _view++;
      _checkedAbsent.clear();
      phase = TodayPhase.locked;
      detailPhase = TodayPhase.locked;
      memory.lock(NativeLockEvent(memory.nativeEpoch));
      if (repository is ApiTodayRepository) {
        (repository as ApiTodayRepository).api.cancelPrivateRequests();
      }
      _emit();
      await cache.platform.clearLocalState(LocalClearPhase.cover);
      await cache.platform.clearLocalState(LocalClearPhase.destroy);
      return true;
    }
    return false;
  }

  String _errorCopy(Object e) => e is ApiError && e.status == 429
      ? 'Слишком много запросов. Подождите и повторите явно.'
      : e is ApiError && e.status == 404
      ? 'Объект недоступен. Обновите список.'
      : 'Не удалось получить данные. Повторите обновление.';
  Future<void> loadNextPage() async {
    final cursor = dashboard?.nextCursor;
    if (!online || cursor == null || loadingMore) return;
    final epoch = memory.nativeEpoch, view = _view, scope = _scope;
    loadingMore = true;
    _emit();
    try {
      final page = await repository.dashboard(cursor: cursor);
      if (!_active(epoch) || view != _view || !_sameScope(scope)) return;
      if (page.contextEpoch != dashboard!.contextEpoch ||
          page.preferences.ownerPolicyVersion !=
              dashboard!.preferences.ownerPolicyVersion) {
        await refresh();
        return;
      }
      final byId = {for (final t in tasks) t.id: t};
      for (final t in page.tasks) {
        final prior = byId[t.id];
        if (prior != null && t.entityVersion < prior.entityVersion) {
          throw const FormatException('Version regression');
        }
        byId[t.id] = t;
      }
      tasks = byId.values.toList();
      dashboard = Dashboard.fromCacheJson({
        ...dashboard!.json,
        'next_cursor': page.nextCursor,
      });
      message = 'Список обновляется постранично; данные могут меняться.';
    } catch (e) {
      if (_active(epoch) && view == _view) {
        if (!_superseded(e) && !await _denial(e)) {
          phase = TodayPhase.stale;
          message = _errorCopy(e);
        }
      }
    } finally {
      if (_active(epoch) && view == _view) {
        loadingMore = false;
        _emit();
      }
    }
  }

  Future<void> openTask(String id) => _open(id, false);
  Future<void> openReminder(String id) => _open(id, true);
  Future<void> retryDetail() async {
    final id = detailResourceId;
    if (id != null) await _open(id, detailIsReminder);
  }

  Future<void> _open(String id, bool reminder) async {
    detailResourceId = id;
    detailIsReminder = reminder;
    final epoch = memory.nativeEpoch, detail = ++_detail, scope = _scope;
    selectedTask = null;
    selectedReminder = null;
    detailPhase = TodayPhase.loading;
    detailMessage = null;
    detailLastSync = null;
    _emit();
    try {
      final projection = reminder
          ? await repository.reminder(id)
          : await repository.task(id);
      if (!_active(epoch) || detail != _detail || !_sameScope(scope)) return;
      if (projection is TaskDto) {
        selectedTask = _canonicalTask(projection);
        _mergeTaskDetail(selectedTask!);
      } else {
        selectedReminder = projection as ReminderDto;
        _mergeReminderDetail(selectedReminder!);
      }
      detailPhase = TodayPhase.fresh;
      if (repository is ApiTodayRepository) {
        detailLastSync = (repository as ApiTodayRepository).detailSyncedAt(
          id,
          reminder,
        );
      }
    } catch (e) {
      if (!_active(epoch) || detail != _detail || !_sameScope(scope)) return;
      if (_superseded(e)) {
        detailPhase = TodayPhase.stale;
        detailMessage = 'Загрузка заменена обновлением. Повторите загрузку.';
        _emit();
        return;
      }
      if (await _denial(e)) return;
      detailPhase = e is ApiError && e.status == 404
          ? TodayPhase.unavailable
          : TodayPhase.error;
      detailMessage = _errorCopy(e);
      if (detailPhase != TodayPhase.unavailable) {
        try {
          final frame = await cache.read();
          if (!_active(epoch) || detail != _detail || !_sameScope(scope)) {
            return;
          }
          final raw = (reminder ? frame.reminders : frame.tasks)[id];
          if (raw != null) {
            detailLastSync =
                (reminder ? frame.reminderSyncedAt : frame.taskSyncedAt)[id]
                    as String?;
            if (reminder) {
              selectedReminder = ReminderDto.fromJson(objectJson(raw));
            } else {
              selectedTask = TaskDto.fromJson(objectJson(raw));
            }
            detailPhase = TodayPhase.offline;
            detailMessage = 'Сохранённые данные · Только чтение';
          }
        } catch (_) {}
      }
    }
    if (_active(epoch) && detail == _detail) _emit();
  }

  bool blocked(String id) =>
      pending.any((p) => p.resourceId == id && p.unresolved);
  Future<void> completeTask(TaskDto task) async {
    if (!detailOnline ||
        selectedTask?.id != task.id ||
        selectedTask?.entityVersion != task.entityVersion ||
        !task.canComplete) {
      return;
    }
    await _start(ApiOperation.completeTask, task.id, task.entityVersion);
  }

  Future<void> snoozeReminder(ReminderDto reminder) async {
    if (!detailOnline ||
        selectedReminder?.id != reminder.id ||
        selectedReminder?.entityVersion != reminder.entityVersion ||
        !reminder.canSnooze) {
      return;
    }
    await _start(
      ApiOperation.snoozeReminder,
      reminder.id,
      reminder.entityVersion,
    );
  }

  Future<void> _start(ApiOperation op, String id, int version) async {
    if (busy ||
        !online ||
        blocked(id) ||
        recovery == null ||
        dashboard == null) {
      return;
    }
    final busyOwner = _claimBusy();
    detailMessage = null;
    _emit();
    final epoch = memory.nativeEpoch, scope = _scope;
    try {
      final action = await recovery!.prepare(
        op,
        id,
        version,
        dashboard!.contextEpoch,
      );
      if (!_active(epoch) || !_sameScope(scope)) return;
      await _pending();
      await _send(action, false, epoch, scope);
    } catch (e) {
      if (_active(epoch) && _sameScope(scope)) {
        if (!await _denial(e)) {
          detailPhase = TodayPhase.error;
          detailMessage = 'Не удалось надёжно сохранить команду. Отправка не подтверждена; проверьте сохранённые команды.';
        }
      }
    } finally {
      _releaseBusy(busyOwner);
    }
  }

  Future<void> _send(PendingAction p, bool retry, int epoch, int scope) async {
    MutationReceipt receipt;
    try {
      receipt = p.operation == ApiOperation.completeTask
          ? await repository.complete(
              p.resourceId,
              p.expectedVersion,
              p.actionKey,
            )
          : await repository.snooze10(
              p.resourceId,
              p.expectedVersion,
              p.actionKey,
            );
      p.match(receipt);
    } catch (e) {
      if (!_active(epoch) || !_sameScope(scope)) return;
      if (await _denial(e)) return;
      final definite =
          e is ApiError && {400, 404, 409, 422, 429}.contains(e.status);
      if (definite && !retry) {
        await recovery!.reject(p, e.status, e.code);
        await _pending();
        if (e.status == 409 || e.status == 404) {
          await refresh();
          if (!_active(epoch) ||
              !_sameScope(scope) ||
              phase == TodayPhase.paused) {
            return;
          }
          if (e.status == 409) await _open(p.resourceId, p.kind == 'reminder');
          if (!_active(epoch) ||
              !_sameScope(scope) ||
              phase == TodayPhase.paused) {
            return;
          }
          if (e.status == 404) {
            selectedTask = null;
            selectedReminder = null;
          }
        }
        detailPhase = e.status == 409
            ? TodayPhase.conflict
            : e.status == 404
            ? TodayPhase.unavailable
            : TodayPhase.error;
        detailMessage = e.status == 409
            ? 'Данные изменились. Обновите объект перед новой командой.'
            : _errorCopy(e);
      } else {
        try {
          await recovery!.unknown(p);
          await _pending();
        } catch (_) {}
        detailPhase = TodayPhase.unknown;
        detailMessage = 'Исход команды неизвестен. Проверьте результат; повторной отправки не было.';
      }
      _emit();
      return;
    }
    if (!_active(epoch) || !_sameScope(scope)) return;
    try {
      await recovery!.confirm(p, receipt, lookup: false);
      await _pending();
    } catch (_) {
      detailPhase = TodayPhase.unknown;
      detailMessage = 'Получен ответ команды; локальное подтверждение недоступно. Проверьте результат.';
      _emit();
      return;
    }
    if (!_active(epoch) || !_sameScope(scope)) return;
    await _afterConfirmed(p, epoch, scope);
  }

  Future<void> _afterConfirmed(PendingAction p, int epoch, int scope) async {
    selectedTask = null;
    selectedReminder = null;
    detailPhase = TodayPhase.stale;
    detailMessage = 'Команда выполнена. Обновление данных…';
    _emit();
    await refresh();
    if (!_active(epoch) || !_sameScope(scope)) return;
    await _open(p.resourceId, p.kind == 'reminder');
    if (!_active(epoch) || !_sameScope(scope)) return;
    if (detailPhase != TodayPhase.fresh || !online) {
      selectedTask = null;
      selectedReminder = null;
      detailPhase = TodayPhase.stale;
      detailMessage = 'Команда выполнена; обновить данные пока не удалось';
    } else {
      detailMessage = 'Команда выполнена.';
    }
    _emit();
  }

  Future<void> reconcile(PendingAction p) async {
    if (busy || recovery == null || !memory.unlocked) return;
    final busyOwner = _claimBusy();
    final epoch = memory.nativeEpoch, scope = _scope;
    _emit();
    try {
      final receipt = await repository.mutation(p.actionKey);
      if (!_active(epoch) || !_sameScope(scope)) return;
      if (receipt != null) {
        p.match(receipt);
        await recovery!.confirm(p, receipt, lookup: true);
        await _pending();
        if (!_active(epoch) || !_sameScope(scope)) return;
        await _afterConfirmed(p, epoch, scope);
      } else {
        await recovery!.unknown(p);
        await _pending();
        _checkedAbsent.add(p.actionKey);
        detailPhase = TodayPhase.unknown;
        detailMessage = 'Квитанция не найдена. Это не доказывает отсутствие эффекта. Можно явно повторить исходную команду после проверки текущего объекта.';
      }
    } catch (e) {
      if (_active(epoch) && _sameScope(scope) && !await _denial(e)) {
        detailPhase = TodayPhase.unknown;
        detailMessage =
            'Проверка результата недоступна. Исходная команда сохранена.';
      }
    } finally {
      _releaseBusy(busyOwner);
    }
  }

  bool canRetry(PendingAction p) =>
      _checkedAbsent.contains(p.actionKey) && !busy && online;
  Future<void> retryOriginal(PendingAction p) async {
    if (!canRetry(p) ||
        recovery == null ||
        dashboard?.contextEpoch != p.json['context_epoch']) {
      return;
    }
    final busyOwner = _claimBusy();
    final epoch = memory.nativeEpoch, scope = _scope;
    _emit();
    try {
      final dto = p.kind == 'task'
          ? await repository.task(p.resourceId)
          : await repository.reminder(p.resourceId);
      if (!_active(epoch) || !_sameScope(scope)) return;
      final allowed = dto is TaskDto
          ? dto.canComplete
          : (dto as ReminderDto).canSnooze;
      if (!allowed) {
        detailPhase = TodayPhase.unknown;
        detailMessage = 'Исходная команда сохранена. Текущее состояние не разрешает повтор.';
        return;
      }
      _checkedAbsent.remove(p.actionKey);
      await _send(ActionRecovery.retrySame(p), true, epoch, scope);
    } catch (e) {
      if (_active(epoch) && _sameScope(scope) && !await _denial(e)) {
        detailPhase = TodayPhase.unknown;
        detailMessage = 'Исходная команда сохранена; повтор недоступен.';
      }
    } finally {
      _releaseBusy(busyOwner);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidateBusy();
    _view++;
    _detail++;
    memory.removeListener(_sessionChanged);
    _denials?.cancel();
    _taskEntities.clear();
    dashboard = null;
    tasks = [];
    selectedTask = null;
    selectedReminder = null;
    pending = [];
    super.dispose();
  }
}
