import 'package:assistant/core/api/wire_models.dart';

// Synthetic reserved identifiers and opaque-looking test credentials only.
const deviceId = '11111111-1111-4111-8111-111111111111';
SessionDto fixtureSession() => SessionDto.fromJson({
  'device_id': deviceId,
  'device_version': 1,
  'token_type': 'DPoP',
  'access_token': List.filled(43, 'A').join(),
  'refresh_token': List.filled(43, 'R').join(),
  'expires_in': 600,
  'refresh_expires_at': '2026-11-30T12:00:00Z',
  'server_time': '2026-10-31T12:00:00Z',
});
