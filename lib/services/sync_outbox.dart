import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

/// An event is immutable once enqueued: retries always send the same UUID.
class SyncEvent {
  const SyncEvent({
    required this.id,
    required this.siteId,
    required this.deviceId,
    required this.eventType,
    required this.schemaVersion,
    required this.occurredAt,
    required this.payload,
    this.idempotencyKey,
  });

  final String id;
  final String siteId;
  final String deviceId;
  final String eventType;
  final int schemaVersion;
  final DateTime occurredAt;
  final Map<String, Object?> payload;
  final String? idempotencyKey;

  Map<String, Object?> toJson() => {
        'id': id,
        'site_id': siteId,
        'device_id': deviceId,
        'event_type': eventType,
        'schema_version': schemaVersion,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'payload': payload,
        if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      };

  factory SyncEvent.fromJson(Map<String, Object?> json) => SyncEvent(
        id: json['id']! as String,
        siteId: json['site_id']! as String,
        deviceId: json['device_id']! as String,
        eventType: json['event_type']! as String,
        schemaVersion: json['schema_version']! as int,
        occurredAt: DateTime.parse(json['occurred_at']! as String).toUtc(),
        payload: Map<String, Object?>.from(json['payload']! as Map),
        idempotencyKey: json['idempotency_key'] as String?,
      );
}

class SyncFlushResult {
  const SyncFlushResult({
    required this.sent,
    required this.acknowledged,
    required this.pending,
  });

  final int sent;
  final int acknowledged;
  final int pending;
}

/// Durable local outbox. Events remain on disk until the Cloud acknowledges
/// their stable IDs. A failed network attempt never deletes an event.
class SyncOutbox {
  SyncOutbox({Database? database}) : _injectedDatabase = database;

  static const _storeName = 'sync_outbox_v1';
  static const int maxBatchSize = 50;
  final Database? _injectedDatabase;
  final _store = stringMapStoreFactory.store(_storeName);
  Future<Database>? _databaseFuture;
  Future<void> _serial = Future<void>.value();

  Future<Database> get _database {
    if (_injectedDatabase != null) return Future.value(_injectedDatabase);
    return _databaseFuture ??= _openDatabase();
  }

  Future<Database> _openDatabase() async {
    final directory = await getApplicationSupportDirectory();
    return databaseFactoryIo.openDatabase(
      '${directory.path}/mtandao_sync.db',
    );
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _serial = _serial.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  static String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  Future<String> enqueue({
    required String siteId,
    required String deviceId,
    required String eventType,
    required Map<String, Object?> payload,
    int schemaVersion = 1,
    String? idempotencyKey,
    DateTime? occurredAt,
  }) async {
    if (siteId.isEmpty || deviceId.isEmpty || eventType.isEmpty ||
        eventType.length > 120 || schemaVersion < 1 ||
        (idempotencyKey?.length ?? 0) > 200) {
      throw ArgumentError('Invalid synchronization event metadata');
    }
    final event = SyncEvent(
      id: _uuidV4(),
      siteId: siteId,
      deviceId: deviceId,
      eventType: eventType,
      schemaVersion: schemaVersion,
      occurredAt: (occurredAt ?? DateTime.now()).toUtc(),
      payload: Map<String, Object?>.from(payload),
      idempotencyKey: idempotencyKey,
    );
    await _locked(() async {
      await _store.record(event.id).put(await _database, {
        'event': event.toJson(),
        'attempts': 0,
        'next_attempt_at': 0,
        'last_error': null,
        'queued_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      });
    });
    return event.id;
  }

  Future<int> pendingCount() async => (await _store.count(await _database));

  Future<List<SyncEvent>> pendingEvents({int limit = maxBatchSize}) async {
    final db = await _database;
    final records = await _store.find(
      db,
      finder: Finder(
        sortOrders: [SortOrder('queued_at')],
        limit: limit,
        filter: Filter.lessThanOrEquals(
          'next_attempt_at',
          DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
    return records
        .map((record) => SyncEvent.fromJson(
              Map<String, Object?>.from(record.value['event']! as Map),
            ))
        .toList();
  }

  Future<void> _acknowledge(Set<String> ids) => _locked(() async {
        final db = await _database;
        await db.transaction((txn) async {
          for (final id in ids) {
            await _store.record(id).delete(txn);
          }
        });
      });

  Future<void> _recordFailure(List<SyncEvent> events, Object error) =>
      _locked(() async {
        final db = await _database;
        await db.transaction((txn) async {
          for (final event in events) {
            final record = _store.record(event.id);
            final current = await record.get(txn);
            if (current == null) continue;
            final attempts = (current['attempts'] as int? ?? 0) + 1;
            final delaySeconds = min(3600, 1 << min(attempts, 12));
            await record.update(txn, {
              'attempts': attempts,
              'next_attempt_at': DateTime.now()
                  .add(Duration(seconds: delaySeconds))
                  .millisecondsSinceEpoch,
              'last_error': error.toString().substring(
                    0,
                    min(error.toString().length, 300),
                  ),
            });
          }
        });
      });

  /// Sends one batch. The API's acknowledgement is validated before deletion.
  Future<SyncFlushResult> flush({
    required Uri apiBaseUri,
    required String siteId,
    required String accessToken,
    http.Client? client,
  }) async {
    if (accessToken.isEmpty) throw ArgumentError('Access token is required');
    final ownsClient = client == null;
    final httpClient = client ?? http.Client();
    final events = await pendingEvents();
    if (events.isEmpty) {
      return SyncFlushResult(sent: 0, acknowledged: 0, pending: await pendingCount());
    }
    if (events.any((event) => event.siteId != siteId)) {
      throw StateError('Outbox contains events for a different site');
    }

    try {
      final response = await httpClient
          .post(
            apiBaseUri.resolve('/v1/sites/$siteId/sync/events'),
            headers: {
              'authorization': 'Bearer $accessToken',
              'content-type': 'application/json',
            },
            body: jsonEncode({'events': events.map((e) => e.toJson()).toList()}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw StateError('Sync API returned HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['site_id'] != siteId ||
          decoded['received_count'] != events.length ||
          decoded['acknowledged_event_ids'] is! List) {
        throw const FormatException('Invalid synchronization acknowledgement');
      }
      final acknowledged = (decoded['acknowledged_event_ids'] as List)
          .whereType<String>()
          .toSet();
      final expected = events.map((event) => event.id).toSet();
      if (!expected.containsAll(acknowledged) ||
          !acknowledged.containsAll(expected)) {
        throw const FormatException('Incomplete synchronization acknowledgement');
      }

      await _acknowledge(acknowledged);
      return SyncFlushResult(
        sent: events.length,
        acknowledged: acknowledged.length,
        pending: await pendingCount(),
      );
    } catch (error) {
      await _recordFailure(events, error);
      rethrow;
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  Future<void> close() async {
    if (_injectedDatabase != null) return;
    final future = _databaseFuture;
    if (future != null) await (await future).close();
    _databaseFuture = null;
  }
}
