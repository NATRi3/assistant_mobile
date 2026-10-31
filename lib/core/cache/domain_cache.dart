import 'dart:async';

import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../platform/platform_gateway.dart';
import '../platform/domain_platform.dart';
import '../session/session_memory.dart';
import '../api/json_value.dart';

// The only Dart domain writer: both read receipts and metadata share this queue.
class DomainCache {
  final PlatformGateway platform;
  final DomainPlatform domain;
  final SessionMemory memory;
  Future<void> _tail = Future.value();
  DomainCache(this.platform, this.domain, this.memory);
  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _check(int epoch) {
    if (!memory.unlocked ||
        memory.nativeEpoch != epoch ||
        memory.current == null) {
      throw StateError('Locked');
    }
  }

  Future<DomainFrame> read() async {
    final epoch = memory.nativeEpoch;
    _check(epoch);
    final frame = await domain.readDomainFrame();
    _check(epoch);
    return frame;
  }

  Future<DomainCommitAck> commit(DomainReadTicket ticket, ApiResult result) =>
      _serial(() async {
        _check(ticket.nativeEpoch);
        for (var attempt = 0; attempt < 3; attempt++) {
          final frame = await read();
          _check(ticket.nativeEpoch);
          try {
            final ack = await domain.commitDomainRead(
              ticket,
              result,
              expectedRevision: frame.revision,
            );
            _check(ticket.nativeEpoch);
            return ack;
          } on PlatformException catch (e) {
            if (e.code != 'DOMAIN_REVISION_CONFLICT' || attempt == 2) rethrow;
          }
        }
        throw StateError('Domain commit unavailable');
      });
  Future<DomainFrame> transact(int nativeEpoch, Map<String, Object?> patch) {
    final immutable = freezeJson(patch)! as Map<String, Object?>;
    return _serial(() async {
      _check(nativeEpoch);
      for (var attempt = 0; attempt < 3; attempt++) {
        final old = await read();
        _check(nativeEpoch);
        try {
          await platform.writePrivateCache(
            PrivateCacheWrite(
              CacheSlot.domain,
              immutable,
              nativeEpoch: nativeEpoch,
              expectedRevision: old.revision,
            ),
          );
          _check(nativeEpoch);
          return await read();
        } on PlatformException catch (e) {
          if (e.code != 'DOMAIN_REVISION_CONFLICT' || attempt == 2) rethrow;
        }
      }
      throw StateError('Domain patch unavailable');
    });
  }

  static Map<String, Object?> patch({
    List<Map<String, Object?>> upsert = const [],
    List<Map<String, Object?>> resolve = const [],
    List<Map<String, Object?>> invalidate = const [],
  }) => {
    'schema_version': 1,
    'upsert_pending': upsert,
    'resolve_pending': resolve,
    'invalidate_resources': invalidate,
  };
}
