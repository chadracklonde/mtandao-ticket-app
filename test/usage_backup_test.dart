import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/routeros/api_client.dart';
import 'package:mtandao_ticket/screens/usage_screen.dart';
import 'package:mtandao_ticket/services/live_usage.dart';
import 'package:mtandao_ticket/services/mikhmon_service.dart';

import 'support/fake_router.dart';

ActiveUser au(String id, String user, int inB, int outB, {String ip = '10.5.50.20'}) => ActiveUser(
      id: id,
      user: user,
      address: ip,
      mac: 'AA:BB:CC:00:00:0${id.length}',
      uptime: '5m',
      bytesIn: inB,
      bytesOut: outB,
    );

void main() {
  group('débits en direct', () {
    test('calcul et classement', () {
      final before = [au('*1', 'a', 0, 0), au('*2', 'b', 0, 0)];
      final now = [au('*1', 'a', 1000, 10000), au('*2', 'b', 0, 500000)];
      final r = computeRates(before, now, const Duration(seconds: 2));
      expect(r.first.session.user, 'b');
      expect(r.first.downBps, 250000);
      expect(r.last.downBps, 5000);
      expect(r.last.upBps, 500);
    });

    test('compteur remis à zéro, session nouvelle, durée nulle', () {
      final r = computeRates([au('*1', 'a', 900, 900)], [au('*1', 'a', 10, 10), au('*3', 'c', 5, 5)],
          const Duration(seconds: 3));
      expect(r.every((x) => x.totalBps == 0), isTrue);
      expect(computeRates([au('*1', 'a', 0, 0)], [au('*1', 'a', 100, 100)], Duration.zero).first.totalBps, 0);
    });

    test('affichage des vitesses', () {
      expect(formatSpeed(0), '0 o/s');
      expect(formatSpeed(512), '512 o/s');
      expect(formatSpeed(1536), '1,5 Ko/s');
      expect(formatSpeed(5 * 1024 * 1024), '5,0 Mo/s');
    });
  });

  group('routeur simulé', () {
    late FakeRouter router;
    late RouterOsClient client;
    late MikhmonService service;

    setUp(() async {
      router = await FakeRouter.start();
      client = RouterOsClient(
        host: '127.0.0.1',
        port: router.port,
        useSsl: false,
        username: 'admin',
        password: 'secret',
        connectTimeout: const Duration(seconds: 2),
        commandTimeout: const Duration(seconds: 5),
      );
      await client.connect();
      service = MikhmonService(client, Session(id: 's', name: 'Wifi', host: '127.0.0.1', username: 'admin'));
    });

    tearDown(() async {
      client.close();
      await router.stop();
    });

    test('ralentir puis rétablir un appareil', () async {
      router.queues.add({'.id': '*Q0', 'name': 'autre', 'target': '10.5.50.0/24'});
      await service.slowDevice('10.5.50.20');
      await service.slowDevice('10.5.50.20'); // déjà ralenti : rien de plus
      expect(await service.slowedAddresses(), {'10.5.50.20'});
      expect(router.queues.where((q) => q['comment'] == MikhmonService.slowComment).length, 1);
      expect(router.queues.firstWhere((q) => q['comment'] == MikhmonService.slowComment)['max-limit'], '256k/256k');
      await service.unslowDevice('10.5.50.20');
      expect(await service.slowedAddresses(), isEmpty);
      expect(router.queues.length, 1);
      await expectLater(service.slowDevice('pas-une-ip'), throwsA(isA<RouterOsException>()));
    });

    test('sauvegarde automatique : programmer, lire, arrêter', () async {
      var a = await service.autoBackup();
      expect(a.enabled, isFalse);
      await service.enableAutoBackup(const Duration(days: 7));
      await service.enableAutoBackup(const Duration(days: 1)); // remplace
      expect(router.tables['/system/scheduler']!.length, 1);
      router.tables['/file']!.add({'name': 'mtandao-auto.backup', 'creation-time': 'nov/03/2026 03:00:12'});
      a = await service.autoBackup();
      expect(a.enabled, isTrue);
      expect(a.interval, const Duration(days: 1));
      expect(a.last, DateTime(2026, 11, 3, 3, 0, 12));
      expect(a.lateAt(DateTime(2026, 11, 4, 12)), isFalse);
      expect(a.lateAt(DateTime(2026, 11, 8, 12)), isTrue);
      await service.disableAutoBackup();
      expect((await service.autoBackup()).enabled, isFalse);
      await expectLater(service.enableAutoBackup(const Duration(hours: 1)), throwsA(isA<RouterOsException>()));
    });

    testWidgets('écran : classement et ralentir', (tester) async {
      router.active.addAll([
        {'.id': '*A1', 'user': 'calme', 'address': '10.5.50.21', 'mac-address': 'AA:00:00:00:00:01',
          'uptime': '5m', 'bytes-in': '100', 'bytes-out': '100'},
        {'.id': '*A2', 'user': 'gourmand', 'address': '10.5.50.22', 'mac-address': 'AA:00:00:00:00:02',
          'uptime': '9m', 'bytes-in': '100', 'bytes-out': '100'},
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: UsageScreen(service: service, interval: const Duration(milliseconds: 300))),
      ));
      Future<void> wait([int n = 20]) async {
        for (var i = 0; i < n; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
          await tester.pump(const Duration(milliseconds: 40));
        }
      }

      await wait();
      expect(find.text('calme'), findsOneWidget);
      // Le 2e client télécharge beaucoup entre deux relevés.
      // Le débit doit durer : on fait grossir le compteur à chaque instant.
      for (var i = 0; i < 30; i++) {
        router.active[1]['bytes-out'] = '${90000000 + i * 5000000}';
        await wait(1);
      }
      final first = tester.getTopLeft(find.text('gourmand')).dy;
      final second = tester.getTopLeft(find.text('calme')).dy;
      expect(first, lessThan(second));
      await tester.tap(find.text('Ralentir').first);
      await wait();
      expect(router.queues.any((q) => q['comment'] == MikhmonService.slowComment && q['target'] == '10.5.50.22/32'),
          isTrue);
      expect(find.text('Ralenti'), findsOneWidget);
      // Arrête le minuteur avant la fin du test.
      await tester.pumpWidget(const SizedBox());
    });
  });
}
