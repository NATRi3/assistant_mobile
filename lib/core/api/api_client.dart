import 'dart:async';
import 'dart:convert';

import '../config/app_config.dart';
import '../platform/platform_gateway.dart';
import '../session/session_memory.dart';
import 'operation.dart';
import 'api_error.dart';
import 'http_transport.dart';
import 'strict_json.dart';
import 'json_value.dart';
export 'operation.dart';
export 'http_transport.dart';

class ApiResult {
  final int statusCode;
  final Map<String, String> headers;
  final Map<String, Object?> body;
  ApiResult(
    this.statusCode,
    Map<String, String> headers,
    Map<String, Object?> body,
  ) : headers = Map.unmodifiable(headers),
      body = freezeJson(body)! as Map<String, Object?>;
  @override
  String toString() => 'ApiResult([redacted])';
}

abstract interface class MobileApi {
  Future<Map<String, Object?>> call(
    ApiOperation operation, {
    String? resourceId,
    Map<String, Object?> body = const {},
    Map<String, String> query = const {},
    String? actionKey,
  });
  void cancelPrivateRequests();
}

class ApiClient implements MobileApi {
  final AppConfig config;
  final PlatformGateway platform;
  final ApiTransport transport;
  final SessionMemory memory;
  final SessionDto? Function()? revokeSession;
  int _generation = 0;
  ApiClient(
    this.config,
    this.platform,
    this.transport,
    this.memory, {
    this.revokeSession,
  });
  @override
  Future<Map<String, Object?>> call(
    ApiOperation operation, {
    String? resourceId,
    Map<String, Object?> body = const {},
    Map<String, String> query = const {},
    String? actionKey,
  }) async => (await callResult(
    operation,
    resourceId: resourceId,
    body: body,
    query: query,
    actionKey: actionKey,
  )).body;
  Future<ApiResult> callResult(
    ApiOperation operation, {
    String? resourceId,
    Map<String, Object?> body = const {},
    Map<String, String> query = const {},
    String? actionKey,
    void Function()? checkAdmission,
  }) async {
    final origin = config.apiOrigin;
    if (origin == null) throw const ApiError(0, 'UNCONFIGURED');
    final route = operationRoutes[operation]!;
    final path = route.resolve(resourceId);
    final dedicated =
        operation == ApiOperation.revokeSelfDevice && revokeSession != null;
    final session = dedicated ? revokeSession!() : memory.current;
    if (!dedicated && !memory.unlocked) throw const ApiError(0, 'LOCKED');
    if (route.authenticated && session == null) {
      throw const ApiError(401, 'UNAUTHORIZED');
    }
    if (actionKey != null && !validUuid(actionKey)) {
      throw const FormatException('Invalid action key');
    }
    if (route.method != 'GET' &&
        operation != ApiOperation.createPairing &&
        actionKey == null) {
      throw const FormatException('Action key required');
    }
    final bytes = route.method == 'GET' ? null : utf8.encode(jsonEncode(body));
    if (bytes != null && bytes.length > 16384) {
      throw const ApiError(413, 'BODY_TOO_LARGE');
    }
    if (query.keys.any((k) => !{'limit', 'cursor', 'state'}.contains(k))) {
      throw const FormatException('Unknown query');
    }
    final epoch = memory.nativeEpoch, generation = _generation;
    void checkSession() {
      if (generation != _generation ||
          (!dedicated &&
              (!memory.unlocked ||
                  epoch != memory.nativeEpoch ||
                  (route.authenticated &&
                      !identical(session, memory.current))))) {
        throw const ApiError(0, 'LOCKED');
      }
    }

    void check() {
      checkSession();
      checkAdmission?.call();
    }

    try {
      return await (() async {
        check();
        final proof = await platform.signDpop(
          DpopMetadata(
            operation,
            resourceId: resourceId,
            accessToken: route.authenticated ? session!.accessToken : null,
          ),
        );
        check();
        final response = await transport.send(
          ApiRequest(
            route.method,
            origin.replace(
              path: path,
              queryParameters: query.isEmpty ? null : query,
            ),
            {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'DPoP': proof,
              if (route.authenticated)
                'Authorization': 'DPoP ${session!.accessToken}',
              'Idempotency-Key': ?actionKey,
            },
            bytes,
            checkAdmission: check,
          ),
        );
        // Current authenticated denial is a security barrier even when this
        // command's result is obsolete. Old session/epoch responses have no
        // authority to deny the current session.
        checkSession();
        if (!dedicated &&
            route.authenticated &&
            response.statusCode == 403 &&
            platform is DomainAccessAuthority) {
          await (platform as DomainAccessAuthority).denyDomainAccess(epoch);
        }
        check();
        if (response.body.length > 262144) {
          throw const ApiError(0, 'RESPONSE_TOO_LARGE');
        }
        // A successful HTTP class alone is not a contractual receipt.
        final expected = switch (operation) {
          ApiOperation.createPairing => 201,
          ApiOperation.revokeSelfDevice => 204,
          ApiOperation.submitChat ||
          ApiOperation.recordNotificationReceipt => 202,
          _ => 200,
        };
        if (response.statusCode >= 200 && response.statusCode < 300) {
          if (response.statusCode != expected) {
            throw const ApiError(0, 'INVALID_RESPONSE');
          }
          if (expected == 204) {
            return ApiResult(204, response.headers, const {});
          }
        }
        Object? decoded;
        try {
          decoded = decodeStrictJson(
            utf8.decode(response.body, allowMalformed: false),
          );
        } catch (_) {
          throw const ApiError(0, 'INVALID_RESPONSE');
        }
        if (decoded is! Map<String, dynamic>) {
          throw const ApiError(0, 'INVALID_RESPONSE');
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final code = decoded['code'];
          throw ApiError(
            response.statusCode,
            code is String && RegExp(r'^[A-Z_]{1,64}$').hasMatch(code)
                ? code
                : 'REQUEST_FAILED',
          );
        }
        return ApiResult(
          response.statusCode,
          response.headers,
          Map<String, Object?>.from(decoded),
        );
      })().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      cancelPrivateRequests();
      throw const ApiError(0, 'TIMEOUT');
    }
  }

  @override
  void cancelPrivateRequests() {
    _generation++;
    transport.abortAll();
  }
}
