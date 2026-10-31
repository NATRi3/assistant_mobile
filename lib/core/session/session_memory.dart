import 'package:flutter/foundation.dart';

import '../platform/platform_gateway.dart';

class SessionMemory extends ChangeNotifier {
  SessionDto? _current;
  int _nativeEpoch = 0;
  bool _unlocked = false;
  SessionDto? get current => _current;
  int get nativeEpoch => _nativeEpoch;
  bool get unlocked => _unlocked;
  void adopt(UnlockResult value) {
    if (value.nativeEpoch <= _nativeEpoch) return;
    _current = value.session;
    _nativeEpoch = value.nativeEpoch;
    _unlocked = true;
    notifyListeners();
  }

  void install(SessionDto value, int epoch) {
    if (!_unlocked || epoch != _nativeEpoch) throw StateError('Locked');
    _current = value;
    notifyListeners();
  }

  void lock(NativeLockEvent value) {
    if (value.nativeEpoch < _nativeEpoch) return;
    _current = null;
    _nativeEpoch = value.nativeEpoch;
    _unlocked = false;
    notifyListeners();
  }
}
