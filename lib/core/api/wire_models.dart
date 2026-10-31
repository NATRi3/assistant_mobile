import 'operation.dart';

void exact(Map<String, Object?> j, Set<String> fields) {
  if (j.keys.toSet().difference(fields).isNotEmpty ||
      fields.difference(j.keys.toSet()).isNotEmpty) {
    throw const FormatException('Invalid fields');
  }
}

String stringField(Map<String, Object?> j, String k, {int? length}) {
  final v = j[k];
  if (v is! String ||
      v.contains('\u0000') ||
      (length != null && v.length != length)) {
    throw const FormatException('Invalid string');
  }
  return v;
}

DateTime timestamp(Object? v) {
  if (v is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$')
          .hasMatch(v)) {
    throw const FormatException('Invalid timestamp');
  }
  final t = DateTime.tryParse(v);
  if (t == null || t.toIso8601String().substring(0, 19) != v.substring(0, 19)) {
    throw const FormatException('Invalid timestamp');
  }
  return t;
}

int version(Object? v) {
  if (v is! int || v < 1 || v > 9007199254740991) {
    throw const FormatException('Invalid version');
  }
  return v;
}

class SessionDto {
  final Map<String, Object?> _json;
  SessionDto.fromJson(Map<String, Object?> j) : _json = Map.unmodifiable(j) {
    exact(j, {
      'device_id',
      'device_version',
      'token_type',
      'access_token',
      'expires_in',
      'refresh_token',
      'refresh_expires_at',
      'server_time',
    });
    if (!validUuid(j['device_id']) ||
        j['token_type'] != 'DPoP' ||
        (j['expires_in'] is! int || j['expires_in'] != 600)) {
      throw const FormatException('Invalid session');
    }
    version(j['device_version']);
    for (final k in ['access_token', 'refresh_token']) {
      final t = stringField(j, k, length: 43);
      if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(t)) {
        throw const FormatException('Invalid token');
      }
    }
    timestamp(j['server_time']);
    timestamp(j['refresh_expires_at']);
  }
  String get deviceId => _json['device_id']! as String;
  int get deviceVersion => _json['device_version']! as int;
  String get accessToken => _json['access_token']! as String;
  String get refreshToken => _json['refresh_token']! as String;
  DateTime get serverTime => timestamp(_json['server_time']);
  DateTime get accessExpiresAt => serverTime.add(const Duration(seconds: 600));
  DateTime get refreshExpiresAt => timestamp(_json['refresh_expires_at']);
  Map<String, Object?> toJson() => Map.of(_json);
  @override
  String toString() => 'SessionDto([redacted])';
}

class PairingCreated {
  final String pairingId, code, fingerprint;
  final DateTime expiresAt;
  PairingCreated.fromJson(Map<String, Object?> j)
    : pairingId = stringField(j, 'pairing_id'),
      code = stringField(j, 'code', length: 8),
      fingerprint = stringField(j, 'fingerprint', length: 43),
      expiresAt = timestamp(j['expires_at']) {
    exact(j, {
      'pairing_id',
      'code',
      'fingerprint',
      'expires_at',
      'poll_after_seconds',
    });
    if (!validUuid(pairingId) ||
        !RegExp(r'^[A-Z2-7]{8}$').hasMatch(code) ||
        (j['poll_after_seconds'] is! int || j['poll_after_seconds'] != 3)) {
      throw const FormatException('Invalid pairing');
    }
  }
}

class PairingStatus {
  final String pairingId, status;
  final DateTime expiresAt;
  PairingStatus.fromJson(Map<String, Object?> j)
    : pairingId = stringField(j, 'pairing_id'),
      status = stringField(j, 'status'),
      expiresAt = timestamp(j['expires_at']) {
    exact(j, {'pairing_id', 'status', 'expires_at', 'poll_after_seconds'});
    if (!validUuid(pairingId) ||
        !{
          'pending',
          'approved',
          'denied',
          'expired',
          'consumed',
        }.contains(status) ||
        (j['poll_after_seconds'] is! int || j['poll_after_seconds'] != 3)) {
      throw const FormatException('Invalid pairing status');
    }
  }
}

class Device {
  final String deviceId, deviceLabel, fingerprint;
  final int deviceVersion, registrationVersion, contextEpoch;
  final DateTime createdAt;
  Device.fromJson(Map<String, Object?> j)
    : deviceId = stringField(j, 'device_id'),
      deviceLabel = stringField(j, 'device_label'),
      fingerprint = stringField(j, 'fingerprint'),
      deviceVersion = version(j['device_version']),
      registrationVersion = j['registration_version'] is int
          ? j['registration_version']! as int
          : -1,
      contextEpoch = version(j['context_epoch']),
      createdAt = timestamp(j['created_at']) {
    exact(j, {
      'device_id',
      'device_label',
      'device_version',
      'state',
      'fingerprint',
      'created_at',
      'registration_version',
      'context_epoch',
    });
    if (!validUuid(deviceId) ||
        deviceLabel.length > 60 ||
        fingerprint.length > 43 ||
        j['state'] != 'active' ||
        registrationVersion < 0 ||
        registrationVersion > 9007199254740991) {
      throw const FormatException('Invalid device');
    }
  }
}
