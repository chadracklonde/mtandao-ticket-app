import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/routeros/api_client.dart';
import 'package:mtandao_ticket/services/mikhmon_service.dart';
import 'package:mtandao_ticket/util.dart';

import 'support/fake_router.dart';

void main() {
  test('durées RouterOS', () {
    expect(parseRouterDuration('1d2h30m'), const Duration(days: 1, hours: 2, minutes: 30));
    expect(parseRouterDuration('1w'), const Duration(days: 7));
    expect(parseRouterDuration('01:30:00'), const Duration(hours: 1, minutes: 30));
    expect(parseRouterDuration('2d03:00:00'), const Duration(days: 2, hours: 3));
    expect(parseRouterDuration('abc'), isNull);
    expect(parseRouterDuration(''), isNull);
    expect(toRouterDuration(const Duration(days: 1, hours: 2, minutes: 30)), '1d2h30m');
    expect(toRouterDuration(Duration.zero), '0s');
    expect(formatDuration(const Duration(days: 1, hours: 2)), '1 j 2 h');
    expect(formatDuration(const Duration(minutes: 45)), '45 min');
    expect(formatDuration(const Duration(hours: 3, minutes: 5)), '3 h 5 min');
  });

  test('état d\'un utilisateur', () {
    final fresh = HotspotUser.fromRow({'.id': '*1', 'name': 'a', 'comment': 'vc-021126-1400', 'limit-uptime': '1d'});
    expect(fresh.isNew, isTrue);
    expect(fresh.isUsed, isFalse);
    expect(fresh.timeLeft, const Duration(days: 1));
    final used = HotspotUser.fromRow({
      '.id': '*2', 'name': 'b', 'comment': 'used-vc-021126-1400',
      'uptime': '1h', 'limit-uptime': '1h', 'bytes-in': '100', 'bytes-out': '900', 'limit-bytes-total': '5000'
    });
    expect(used.isUsed, isTrue);
    expect(used.isExhausted, isTrue);
    expect(used.timeLeft, Duration.zero);
    expect(used.bytesLeft, 4000);
    final unlimited = HotspotUser.fromRow({'.id': '*3', 'name': 'c', 'uptime': '5h'});
    expect(unlimited.limitUptime, isNull);
    expect(unlimited.timeLeft, isNull);
    expect(unlimited.isExhausted, isFalse);
  });

  group('utilisateurs sur le routeur', () {
    late FakeRouter router;
    late RouterOsClient client;
    late MikhmonService service;

    setUp(() async {
      router = await FakeRouter.start();
      client = RouterOsClient(
        host: '127.0.0.1', port: router.port, useSsl: false,
        username: 'admin', password: 'secret',
        connectTimeout: const Duration(seconds: 2), commandTimeout: const Duration(seconds: 5),
      );
      final s = Session(id: 's', name: 'T', host: '127.0.0.1', username: 'admin');
      service = MikhmonService(client, s, random: Random(1));
      router.hotspotUsers.addAll([
        {'.id': '*1', 'name': 'neuf1', 'profile': '1H', 'comment': 'vc-021126-1000', 'limit-uptime': '1h', 'limit-bytes-total': '1073741824'},
        {'.id': '*2', 'name': 'vieux', 'profile': '1H', 'comment': 'used-vc-011126-0900', 'uptime': '1h', 'limit-uptime': '1h', 'bytes-in': '10', 'bytes-out': '20'},
      ]);
    });
    tearDown(() async {
      client.close();
      await router.stop();
    });

    test('liste complète triée', () async {
      final list = await service.hotspotUsers();
      expect(list.map((u) => u.name).toList(), ['neuf1', 'vieux']);
      expect(list.first.isNew, isTrue);
      expect(list.last.isExhausted, isTrue);
    });

    test('désactiver, réactiver, remise à zéro, suppression', () async {
      await service.setUserDisabled('*1', true);
      expect((await service.hotspotUsers()).first.disabled, isTrue);
      await service.setUserDisabled('*1', false);
      expect((await service.hotspotUsers()).first.disabled, isFalse);
      await service.resetUserCounters('*2');
      final v = (await service.hotspotUsers()).last;
      expect(v.uptime, Duration.zero);
      expect(v.bytesTotal, 0);
      await service.removeUser('*2');
      expect((await service.hotspotUsers()).length, 1);
    });

    test('prolonger le temps et les données', () async {
      final u = (await service.hotspotUsers()).first;
      await service.extendUser(u, addTime: const Duration(hours: 2), addBytes: 536870912);
      expect(router.hotspotUsers.first['limit-uptime'], '3h');
      expect(router.hotspotUsers.first['limit-bytes-total'], '1610612736');
    });

    test('prolonger un ticket illimité est refusé', () async {
      router.hotspotUsers.add({'.id': '*3', 'name': 'illim', 'comment': 'vc-1'});
      final u = (await service.hotspotUsers()).firstWhere((x) => x.name == 'illim');
      await expectLater(service.extendUser(u, addTime: const Duration(hours: 1)),
          throwsA(isA<RouterOsException>()));
    });
  });
}
