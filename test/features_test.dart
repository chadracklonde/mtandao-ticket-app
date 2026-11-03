import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/routeros/api_client.dart';
import 'package:mtandao_ticket/services/app_lock.dart';
import 'package:mtandao_ticket/services/mikhmon_service.dart';
import 'package:mtandao_ticket/services/profile_backup.dart';
import 'package:mtandao_ticket/services/stock_alert.dart';
import 'package:mtandao_ticket/services/ticket_layout.dart';
import 'package:mtandao_ticket/services/voucher_pdf.dart';
import 'package:mtandao_ticket/widgets/lock_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_router.dart';

void main() {
  final session = Session(id: 's', name: 'Wifi zone', host: 'h', username: 'u', dnsName: 'wifi.local');
  List<Voucher> make(int n, {bool separate = false}) => [
        for (var i = 0; i < n; i++)
          Voucher(
            name: 'K${i.toString().padLeft(5, '0')}',
            password: separate ? 'P$i' : 'K${i.toString().padLeft(5, '0')}',
            profile: '24H',
            price: 500,
            uptime: '1d',
            dataLimit: '1 Go',
          ),
      ];

  group('mise en page des tickets', () {
    test('toutes les mises en page produisent un PDF', () async {
      final logo = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
      for (final layout in [
        const TicketLayout(columns: 2),
        const TicketLayout(columns: 3, showLogo: true, header: 'Cyber Maniema', footer: 'Aide : 0990000000'),
        const TicketLayout(columns: 4, showQr: false),
        const TicketLayout(paper: TicketPaper.roll58),
        const TicketLayout(paper: TicketPaper.roll80, showLogo: true, footer: 'Merci'),
      ]) {
        final bytes = await buildVouchersPdf(make(12, separate: true), session, layout: layout, logo: logo);
        expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-', reason: layout.toJson().toString());
        expect(bytes.length, greaterThan(1500));
      }
    });

    test('le rouleau donne un autre document que la feuille A4', () async {
      final a4 = await buildVouchersPdf(make(9), session);
      final roll = await buildVouchersPdf(make(9), session, layout: const TicketLayout(paper: TicketPaper.roll80));
      expect(ascii.decode(roll.sublist(0, 5)), '%PDF-');
      expect(roll.length, isNot(a4.length));
    });

    test('mise en page enregistrée puis relue', () async {
      SharedPreferences.setMockInitialValues({});
      final store = TicketLayoutStore();
      expect((await store.load()).columns, 3);
      await store.save(const TicketLayout(
          paper: TicketPaper.roll58, columns: 4, showLogo: true, showQr: false, header: 'H', footer: 'F'));
      final back = await store.load();
      expect(back.paper, TicketPaper.roll58);
      expect(back.columns, 4);
      expect(back.showLogo, isTrue);
      expect(back.showQr, isFalse);
      expect(back.header, 'H');
      expect(back.footer, 'F');
      expect(TicketLayout.fromJson({'columns': 9}).columns, 3);
    });
  });

  group('sauvegarde', () {
    test('profils : export puis relecture', () {
      const list = [
        HotspotProfile(name: '24H', price: 500, uptime: '1d', rateLimit: '2M/2M', sharedUsers: 2, dataLimit: '1G'),
        HotspotProfile(name: '1H', price: 100, uptime: '1h'),
      ];
      final back = profilesFromJson(profilesToJson(list));
      expect(back.length, 2);
      expect(back.first.rateLimit, '2M/2M');
      expect(back.first.sharedUsers, 2);
      expect(back.first.dataLimit, '1G');
      expect(back.last.price, 100);
    });

    test('un fichier quelconque est refusé', () {
      expect(() => profilesFromJson('pas du json'), throwsA(isA<RouterOsException>()));
      expect(() => profilesFromJson('{"profiles": []}'), throwsA(isA<RouterOsException>()));
      expect(() => profilesFromJson('[1,2]'), throwsA(isA<RouterOsException>()));
    });
  });

  group('routeur', () {
    late FakeRouter router;
    late RouterOsClient client;
    late MikhmonService service;
    setUp(() async {
      router = await FakeRouter.start();
      client = RouterOsClient(
        host: '127.0.0.1', port: router.port, useSsl: false, username: 'admin', password: 'secret',
        connectTimeout: const Duration(seconds: 2), commandTimeout: const Duration(seconds: 5),
      );
      service = MikhmonService(client, session, random: Random(3));
    });
    tearDown(() async {
      client.close();
      await router.stop();
    });

    test('restaurer des profils : création puis mise à jour', () async {
      await service.saveProfile(const HotspotProfile(name: '24H', price: 500, uptime: '1d'));
      final json = await service.exportProfiles();
      // Autre routeur : un profil déjà présent avec un autre prix.
      final r2 = await FakeRouter.start();
      final c2 = RouterOsClient(
        host: '127.0.0.1', port: r2.port, useSsl: false, username: 'admin', password: 'secret',
        connectTimeout: const Duration(seconds: 2), commandTimeout: const Duration(seconds: 5),
      );
      addTearDown(() async {
        c2.close();
        await r2.stop();
      });
      final other = MikhmonService(c2, session);
      await other.saveProfile(const HotspotProfile(name: '24H', price: 999, uptime: '1h'));
      final wanted = [...profilesFromJson(json), const HotspotProfile(name: 'mauvais;nom')];
      final res = await other.restoreProfiles(wanted);
      expect(res.created, 0);
      expect(res.updated, 1);
      expect(res.failed.keys, ['mauvais;nom']);
      final p = (await other.profiles()).single;
      expect(p.price, 500);
      expect(p.uptime, '1d');
      expect(r2.profiles.length, 1);
    });

    test('sauvegarde du routeur', () async {
      final name = await service.createRouterBackup();
      expect(name, startsWith('mtandao-'));
      expect(router.savedFiles, ['$name.backup', '$name.rsc']);
    });

    test('surveillance : ressources, interfaces, trafic, journal, appareils', () async {
      final r = await service.resource();
      expect(r.cpuLoad, 7);
      expect(r.board, 'hAP ac2');
      expect(r.usedMemory, 68000000);
      expect(await service.interfaces(), ['ether1', 'wlan1']); // ether5 est coupée
      final t = await service.traffic('ether1');
      expect(t.rx, 1500000);
      expect(t.tx, 250000);
      router.logLines.addAll([
        {'time': '10:00:00', 'topics': 'system,info', 'message': 'ancien'},
        {'time': '10:05:00', 'topics': 'hotspot,info,debug', 'message': 'login ok'},
        {'time': '10:06:00', 'topics': 'system,error,critical', 'message': 'panne'},
      ]);
      final logs = await service.logs();
      expect(logs.first.message, 'panne'); // le plus récent d'abord
      expect(logs.first.isError, isTrue);
      expect(logs[1].isHotspot, isTrue);
      router.leases.add({'address': '10.5.50.20', 'mac-address': 'AA:BB', 'host-name': 'tel', 'status': 'bound'});
      final leases = await service.dhcpLeases();
      expect(leases.single.hostName, 'tel');
      expect(formatRateForTest(1500000), '1.5 Mb/s');
    });
  });

  group('verrouillage', () {
    test('code enregistré en empreinte, vérifié, désactivé', () async {
      SharedPreferences.setMockInitialValues({});
      final lock = AppLock();
      expect(await lock.isEnabled(), isFalse);
      expect(AppLock.validPin('123'), isFalse);
      expect(AppLock.validPin('12345678'), isTrue);
      expect(AppLock.validPin('12ab'), isFalse);
      await expectLater(lock.setPin('12'), throwsArgumentError);
      await lock.setPin('4821');
      expect(await lock.isEnabled(), isTrue);
      expect(await lock.verify('4821'), isTrue);
      expect(await lock.verify('0000'), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().any((k) => (prefs.get(k) ?? '').toString().contains('4821')), isFalse);
      await lock.disable();
      expect(await lock.isEnabled(), isFalse);
    });

    testWidgets('écran de code au démarrage puis déverrouillage', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await AppLock().setPin('1234');
      await tester.pumpWidget(const MaterialApp(home: LockGate(child: Text('contenu secret'))));
      await tester.pump();
      await tester.pump();
      expect(find.text('Entrez votre code'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '0000');
      await tester.tap(find.text('Déverrouiller'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Code incorrect.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Déverrouiller'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Entrez votre code'), findsNothing);
      expect(find.text('contenu secret'), findsOneWidget);
    });

    testWidgets('sans code, aucun écran de verrouillage', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const MaterialApp(home: LockGate(child: Text('contenu'))));
      await tester.pump();
      await tester.pump();
      expect(find.text('Entrez votre code'), findsNothing);
      expect(find.text('contenu'), findsOneWidget);
    });
  });

  test('alerte de stock bas', () {
    const profiles = [
      HotspotProfile(name: '24H', price: 500),
      HotspotProfile(name: '1H', price: 100),
      HotspotProfile(name: 'gratuit', price: 0),
    ];
    final batches = [
      VoucherBatch(comment: 'vc-1', profile: '24H', vouchers: [for (var i = 0; i < 30; i++) Voucher(name: 'a$i', password: 'a$i', profile: '24H')]),
      VoucherBatch(comment: 'vc-2', profile: '1H', vouchers: [for (var i = 0; i < 3; i++) Voucher(name: 'b$i', password: 'b$i', profile: '1H')]),
    ];
    final low = lowStock(profiles, batches, 20);
    expect(low.map((l) => l.profile).toList(), ['1H']);
    expect(low.single.left, 3);
    expect(lowStock(profiles, batches, 0), isEmpty);
    expect(lowStock(profiles, [], 5).map((l) => l.profile).toList(), ['24H', '1H']);
  });

  test('vérification du certificat enregistrée avec le routeur', () {
    final s = Session(id: 'a', name: 'n', host: 'h', useSsl: true, verifyCert: true, username: 'u');
    expect(Session.fromJson(s.toJson()).verifyCert, isTrue);
    expect(Session.fromJson({'id': 'a', 'name': 'n', 'host': 'h'}).verifyCert, isFalse);
  });
}

String formatRateForTest(int v) => '${(v / 1000000).toStringAsFixed(1)} Mb/s';
