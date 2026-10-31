import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/config/app_config.dart';
import '../../core/platform/platform_gateway.dart';
import '../../core/session/session_memory.dart';
import '../../core/session/session_controller.dart';
import '../../core/session/refresh_coordinator.dart';

enum PairingPhase {
  unconfigured,
  locked,
  idle,
  creating,
  pending,
  approved,
  completing,
  paired,
  denied,
  expired,
  error,
  revoked,
}

class PairingController extends ChangeNotifier {
  final AppConfig config;
  final MobileApi api;
  final PlatformGateway platform;
  final SessionMemory memory;
  final SessionStore store;
  final DateTime Function() now;
  final Future<Device> Function()? verifyDevice;
  PairingPhase phase;
  PairingCreated? challenge;
  String? message;
  String? _completeKey;
  DateTime? _completeStarted, _lastPoll;
  int _run = 0;
  bool _busy = false;
  int? _unlockRun;
  bool get _unlocking => _unlockRun == _run;
  late final StreamSubscription<NativeLockEvent> _locks;
  PairingController(
    this.config,
    this.api,
    this.platform,
    this.memory,
    this.store, {
    DateTime Function()? now,
    this.verifyDevice,
  }) : now = now ?? DateTime.now,
       phase = config.configured
           ? PairingPhase.locked
           : PairingPhase.unconfigured {
    _locks = platform.lockEvents.listen((e) {
      if (!_unlocking) {
        _run++;
        _busy = false;
      }
      memory.lock(e);
      api.cancelPrivateRequests();
      phase = config.configured
          ? PairingPhase.locked
          : PairingPhase.unconfigured;
      message = null;
      notifyListeners();
    });
  }
  void _state(PairingPhase p, [String? copy]) {
    phase = p;
    message = copy;
    notifyListeners();
  }

  void _check(int run, int epoch) {
    if (run != _run || !memory.unlocked || memory.nativeEpoch != epoch) {
      throw StateError('Locked');
    }
  }

  bool _expired() {
    final c = challenge;
    if (c != null && !now().isBefore(c.expiresAt)) {
      _state(
        PairingPhase.expired,
        'Код истёк. Получите новый код и снова сравните отпечаток в Telegram.',
      );
      return true;
    }
    return false;
  }

  Future<void> begin() async {
    if (!config.configured || _busy) return;
    _busy = true;
    final run = ++_run;
    try {
      _unlockRun = run;
      final unlocked = await platform.unlockAndReadSession();
      if (_unlockRun == run) {
        _unlockRun = null;
      }
      if (run != _run) return;
      memory.adopt(unlocked);
      final epoch = memory.nativeEpoch;
      _check(run, epoch);
      if (memory.current != null) {
        final saved = await store.read(epoch);
        _check(run, epoch);
        if (saved?.value['pending_refresh'] != null ||
            !now().isBefore(memory.current!.accessExpiresAt)) {
          await RefreshCoordinator(
            api,
            memory,
            store,
            now: now,
          ).resumeOrRefresh();
        }
        _check(run, epoch);
        final device = await _verifyOwnDevice();
        _check(run, epoch);
        if (device.deviceId != memory.current!.deviceId ||
            device.deviceVersion != memory.current!.deviceVersion) {
          throw const FormatException('Foreign device');
        }
        _state(PairingPhase.paired);
        return;
      }
      // A still-valid in-memory challenge keeps its semantic completion key across
      // a native lock. Explicit unlock is necessary before any retry.
      if (challenge != null && !_expired()) {
        _state(
          _completeKey != null ? PairingPhase.approved : PairingPhase.pending,
        );
        return;
      }
      challenge = null;
      _completeKey = null;
      _completeStarted = null;
      _state(PairingPhase.creating);
      final key = await platform.createDeviceKey();
      _check(run, epoch);
      final created = PairingCreated.fromJson(
        await api.call(
          ApiOperation.createPairing,
          body: {
            'public_jwk': key.jwk,
            'device_label': 'Android',
            'platform': 'android',
            'app_version': '0.1.0',
          },
        ),
      );
      _check(run, epoch);
      if (created.fingerprint != key.fingerprint) {
        throw const FormatException('Key mismatch');
      }
      challenge = created;
      _lastPoll = now();
      _state(PairingPhase.pending);
    } on ApiError catch (e) {
      if (run == _run) _error(e);
    } catch (_) {
      if (run == _run) {
        _state(
          PairingPhase.locked,
          'Защищённая сессия недоступна. Проверьте блокировку экрана и повторите подключение.',
        );
      }
    } finally {
      if (_unlockRun == run) {
        _unlockRun = null;
      }
      if (run == _run) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> poll() async {
    if (_busy ||
        phase != PairingPhase.pending ||
        _expired() ||
        !memory.unlocked) {
      return;
    }
    if (_lastPoll != null &&
        now().difference(_lastPoll!) < const Duration(seconds: 3)) {
      return;
    }
    _busy = true;
    final run = _run, epoch = memory.nativeEpoch;
    _lastPoll = now();
    try {
      final status = PairingStatus.fromJson(
        await api.call(
          ApiOperation.getPairing,
          resourceId: challenge!.pairingId,
        ),
      );
      _check(run, epoch);
      if (status.pairingId != challenge!.pairingId ||
          status.expiresAt != challenge!.expiresAt) {
        throw const FormatException('Foreign challenge');
      }
      switch (status.status) {
        case 'approved':
          _state(PairingPhase.approved);
        case 'denied':
          _state(PairingPhase.denied, 'Подключение отклонено владельцем.');
        case 'expired':
          _state(PairingPhase.expired, 'Код истёк. Получите новый код.');
        case 'consumed':
          _state(
            PairingPhase.error,
            'Подключение уже завершалось. В личном Telegram отправьте /mobile_pair ${challenge!.code}, выполните явный отзыв старого телефона и подключитесь заново.',
          );
        default:
          _state(PairingPhase.pending);
      }
    } on ApiError catch (e) {
      if (run == _run) _error(e);
    } catch (_) {
      if (run == _run) {
        _state(PairingPhase.error, 'Не удалось проверить подключение.');
      }
    } finally {
      if (_unlockRun == run) {
        _unlockRun = null;
      }
      if (run == _run) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> complete() async {
    if (_busy ||
        phase != PairingPhase.approved ||
        _expired() ||
        !memory.unlocked) {
      return;
    }
    if (_completeStarted != null &&
        (now().difference(_completeStarted!).isNegative ||
            now().difference(_completeStarted!) >=
                const Duration(seconds: 60))) {
      challenge = null;
      _completeKey = null;
      _completeStarted = null;
      _state(
        PairingPhase.error,
        'Подтверждение выдачи сессии недоступно. Получите новый код, отправьте /mobile_pair CODE в личном Telegram, явно отзовите старый телефон и повторите подключение.',
      );
      return;
    }
    _busy = true;
    final run = _run, epoch = memory.nativeEpoch;
    _completeKey ??= newActionKey();
    _completeStarted ??= now();
    _state(PairingPhase.completing);
    try {
      final dto = SessionDto.fromJson(
        await api.call(
          ApiOperation.completePairing,
          resourceId: challenge!.pairingId,
          actionKey: _completeKey,
        ),
      );
      _check(run, epoch);
      await store.install(dto, epoch);
      _check(run, epoch);
      await _verifyOwnDevice();
      _check(run, epoch);
      _state(PairingPhase.paired);
    } on ApiError catch (e) {
      if (run == _run) {
        if (e.code == 'DEVICE_LIMIT') {
          // A definite rejection created no credential receipt. Keep the same
          // semantic key; the next explicit attempt starts its uncertainty timer.
          _completeStarted = null;
          _state(
            PairingPhase.approved,
            'Уже подключён другой телефон. Отправьте /mobile_pair ${challenge!.code} в личном Telegram. В ответе будет UUID вашего активного телефона и команда явного отзыва. После отзыва вернитесь сюда и повторите завершение до истечения кода; повторное подтверждение отпечатка не требуется.',
          );
        } else if (e.retryable) {
          _state(
            PairingPhase.approved,
            'Ответ не получен. Повторите завершение в течение 60 секунд; используется тот же запрос.',
          );
        } else {
          _error(e);
        }
      }
    } catch (_) {
      if (run == _run) {
        _state(
          PairingPhase.error,
          'Сессию не удалось сохранить. Выполните явный отзыв телефона через личный Telegram и подключитесь заново.',
        );
      }
    } finally {
      if (_unlockRun == run) {
        _unlockRun = null;
      }
      if (run == _run) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<Device> _verifyOwnDevice() async {
    final device = verifyDevice != null
        ? await verifyDevice!()
        : Device.fromJson(await api.call(ApiOperation.getSelfDevice));
    if (device.deviceId != memory.current?.deviceId ||
        device.deviceVersion != memory.current?.deviceVersion) {
      throw const FormatException('Foreign device');
    }
    return device;
  }

  void _error(ApiError e) {
    if (e.status == 401) {
      memory.lock(NativeLockEvent(memory.nativeEpoch));
      api.cancelPrivateRequests();
      _state(
        PairingPhase.revoked,
        'Сессия недействительна. Подключите телефон заново.',
      );
    } else if (e.code == 'OWNER_PAUSED') {
      _state(PairingPhase.error, 'Ассистент приостановлен владельцем.');
    } else if (e.status == 410) {
      _state(PairingPhase.expired, 'Код истёк. Получите новый код.');
    } else {
      _state(
        PairingPhase.error,
        'Для открытия сохранённых данных нужно проверить подключение телефона к серверу. Сейчас проверка недоступна.',
      );
    }
  }

  void cancel() {
    _run++;
    _busy = false;
    api.cancelPrivateRequests();
    challenge = null;
    _completeKey = null;
    _completeStarted = null;
    _state(config.configured ? PairingPhase.locked : PairingPhase.unconfigured);
  }

  void coverForLogout() {
    _run++;
    _busy = false;
    challenge = null;
    _completeKey = null;
    _state(
      PairingPhase.revoked,
      'Телефон отключён здесь; серверный отзыв не подтверждён',
    );
  }

  @override
  void dispose() {
    _locks.cancel();
    super.dispose();
  }
}
