import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:sembast/sembast_memory.dart';

import 'package:mtandao_ticket/services/sync_outbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var databaseNumber = 0;

  late SyncOutbox outbox;

  setUp(() async {
    final db = await databaseFactoryMemory.openDatabase('sync-test-${databaseNumber++}');
    outbox = SyncOutbox(database: db);
  });

  tearDown(() async {
    // The injected in-memory database is owned by the test.
  });

  test('queued events survive as pending records until acknowledged', () async {
    final id = await outbox.enqueue(
      siteId: 'site-1',
      deviceId: 'device-1',
      eventType: 'ticket.created',
      payload: {'ticket_id': 'ticket-1'},
    );

    expect(id, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(await outbox.pendingCount(), 1);
    final events = await outbox.pendingEvents();
    expect(events.single.id, id);
    expect(events.single.payload['ticket_id'], 'ticket-1');
    expect(events.single.occurredAt.isUtc, isTrue);
  });

  test('successful flush removes only after a complete acknowledgement', () async {
    final id = await outbox.enqueue(
      siteId: 'site-1',
      deviceId: 'device-1',
      eventType: 'sale.created',
      payload: {'amount_minor': 2500, 'currency': 'CDF'},
    );

    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/sites/site-1/sync/events');
      expect(request.headers['authorization'], 'Bearer jwt-token');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect((body['events'] as List).single['id'], id);
      return http.Response(jsonEncode({
        'site_id': 'site-1',
        'received_count': 1,
        'inserted_count': 1,
        'acknowledged_event_ids': [id],
      }), 200);
    });

    final result = await outbox.flush(
      apiBaseUri: Uri.parse('https://cloud.example'),
      siteId: 'site-1',
      accessToken: 'jwt-token',
      client: client,
    );

    expect(result.sent, 1);
    expect(result.acknowledged, 1);
    expect(result.pending, 0);
    expect(await outbox.pendingCount(), 0);
  });

  test('network failure never deletes queued events', () async {
    await outbox.enqueue(
      siteId: 'site-1',
      deviceId: 'device-1',
      eventType: 'ticket.created',
      payload: {'ticket_id': 'ticket-2'},
    );

    final client = MockClient((_) async => http.Response('unavailable', 503));
    await expectLater(
      outbox.flush(
        apiBaseUri: Uri.parse('https://cloud.example'),
        siteId: 'site-1',
        accessToken: 'jwt-token',
        client: client,
      ),
      throwsStateError,
    );
    expect(await outbox.pendingCount(), 1);
  });

  test('incomplete acknowledgement does not delete the batch', () async {
    await outbox.enqueue(
      siteId: 'site-1',
      deviceId: 'device-1',
      eventType: 'ticket.created',
      payload: {'ticket_id': 'ticket-3'},
    );

    final client = MockClient((_) async => http.Response(jsonEncode({
      'site_id': 'site-1',
      'received_count': 1,
      'inserted_count': 0,
      'acknowledged_event_ids': [],
    }), 200));

    await expectLater(
      outbox.flush(
        apiBaseUri: Uri.parse('https://cloud.example'),
        siteId: 'site-1',
        accessToken: 'jwt-token',
        client: client,
      ),
      throwsFormatException,
    );
    expect(await outbox.pendingCount(), 1);
  });

  test('keeps other sites queued while synchronizing the active site', () async {
    await outbox.enqueue(
      siteId: 'site-other',
      deviceId: 'device-1',
      eventType: 'ticket.created',
      payload: {'ticket_id': 'ticket-4'},
    );
    var called = false;
    final client = MockClient((request) async {
      called = true;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['events'], isEmpty);
      return http.Response('{}', 200);
    });

    final result = await outbox.flush(
      apiBaseUri: Uri.parse('https://cloud.example'),
      siteId: 'site-1',
      accessToken: 'jwt-token',
      client: client,
    );
    expect(called, isFalse);
    expect(result.sent, 0);
    expect(await outbox.pendingCount(), 1);
    expect(await outbox.pendingCount(siteId: 'site-1'), 0);
  });
}
