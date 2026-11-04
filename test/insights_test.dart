import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/routeros/api_client.dart';
import 'package:mtandao_ticket/services/insights.dart';
import 'package:mtandao_ticket/services/mikhmon_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_router.dart';

Sale sale(DateTime t, String user, String profile, int price, {String mac = 'AA'}) => Sale(
      time: t,
      user: user,
      price: price,
      address: '10.0.0.1',
      mac: mac,
      uptime: '1d',
      profile: profile,
      comment: '',
    );

VoucherBatch batch(String profile, int n) => VoucherBatch(
      comment: 'vc-010126-1000',
      profile: profile,
      vouchers: [
        for (var i = 0; i < n; i++) Voucher(name: 'u$i', password: 'u$i', profile: profile),
      ],
    );

HotspotUser user(String name, String profile, {bool used = true, int bytes = 1000}) => HotspotUser(
      id: '*$name',
      name: name,
      password: name,
      profile: profile,
      comment: used ? 'used-vc-1' : 'vc-1',
      disabled: false,
      uptime: used ? const Duration(minutes: 5) : Duration.zero,
      limitUptime: null,
      bytesIn: used ? bytes : 0,
      bytesOut: 0,
      limitBytes: 0,
    );

ActiveUser active(String id, String user, String mac, int bytes) => ActiveUser(
      id: id,
      user: user,
      address: '10.0.0.$id',
      mac: mac,
      uptime: '10m',
      bytesIn: bytes,
      bytesOut: 0,
    );

void main() {
  final now = DateTime(2026, 11, 4, 12);
  const day = HotspotProfile(name: '24H', price: 500, uptime: '1d');
  const free = HotspotProfile(name: 'gratuit', price: 0, uptime: '10m');

  group('prévision de stock', () {
    test('rythme, jours restants et quantité conseillée', () {
      // 14 ventes de 24H sur 14 jours = 1 par jour ; 3 tickets en stock.
      final sales = [
        for (var i = 0; i < 14; i++) sale(DateTime(2026, 11, 4 - i, 10), 'u$i', '24H', 500),
      ];
      final f = forecastStock([day, free], [batch('24H', 3)], sales, now).single;
      expect(f.profile, '24H');
      expect(f.left, 3);
      expect(f.perDay, closeTo(1.0, 0.01));
      expect(f.daysLeft, closeTo(3.0, 0.1));
      expect(f.suggested, 5); // 7 jours - 3 en stock = 4, arrondi à 5
      expect(f.critical, isFalse);
      expect(f.soon, isTrue);
    });

    test('profil qui ne se vend pas : pas de rupture annoncée, rien à générer', () {
      final f = forecastStock([day], [batch('24H', 10)], const [], now).single;
      expect(f.daysLeft, isNull);
      expect(f.suggested, 0);
    });

    test('stock vide et ventes récentes : critique', () {
      final sales = [for (var i = 0; i < 6; i++) sale(DateTime(2026, 11, 4, 8 + i), 'u$i', '24H', 500)];
      final f = forecastStock([day], const [], sales, now).single;
      expect(f.left, 0);
      expect(f.critical, isTrue);
      expect(f.suggested, greaterThan(0));
    });

    test('les profils les plus urgents sont en premier', () {
      const other = HotspotProfile(name: '1H', price: 100, uptime: '1h');
      final sales = [
        for (var i = 0; i < 6; i++) sale(DateTime(2026, 11, 4, 8 + i), 'a$i', '24H', 500),
        for (var i = 0; i < 6; i++) sale(DateTime(2026, 11, 4, 8 + i), 'b$i', '1H', 100),
      ];
      final out = forecastStock([other, day], [batch('1H', 100), batch('24H', 1)], sales, now);
      expect(out.first.profile, '24H');
    });
  });

  group('rapprochement de caisse', () {
    test('ticket payant utilisé sans vente', () {
      final sales = [sale(now, 'k1', '24H', 500)];
      final missing = usedWithoutSale(
        [user('k1', '24H'), user('k2', '24H'), user('k3', '24H', used: false), user('g1', 'gratuit')],
        sales,
        [day, free],
      );
      expect(missing.map((u) => u.name), ['k2']);
      expect(missingRevenue(missing, [day, free]), 500);
    });

    test('clôtures enregistrées, remplacées par jour et relues', () async {
      SharedPreferences.setMockInitialValues({});
      final store = CashStore('r1');
      await store.save(CashClosing(day: '2026-11-03', expected: 1000, counted: 900, savedAt: now));
      await store.save(CashClosing(day: '2026-11-04', expected: 500, counted: 500, savedAt: now));
      await store.save(CashClosing(day: '2026-11-03', expected: 1000, counted: 1000, savedAt: now));
      final all = await store.load();
      expect(all.map((c) => c.day), ['2026-11-04', '2026-11-03']);
      expect(all.last.difference, 0);
      expect(await CashStore('autre').load(), isEmpty);
    });
  });

  group('détection d\'abus', () {
    test('ticket partagé : un même ticket sur deux appareils', () {
      final alerts = detectAbuse([
        active('1', 'K1', 'AA:AA:AA:AA:AA:01', 10),
        active('2', 'K1', 'AA:AA:AA:AA:AA:02', 10),
        active('3', 'K2', 'AA:AA:AA:AA:AA:03', 10),
      ]);
      expect(alerts.length, 1);
      expect(alerts.single.kind, AbuseKind.sharedTicket);
      expect(alerts.single.user, 'K1');
      expect(alerts.single.sessions.length, 2);
    });

    test('gros consommateur : au moins le seuil et trois fois la moyenne des autres', () {
      const gb = 1024 * 1024 * 1024;
      final alerts = detectAbuse([
        active('1', 'big', 'M1', 5 * gb),
        active('2', 'a', 'M2', 100 * 1024 * 1024),
        active('3', 'b', 'M3', 200 * 1024 * 1024),
      ]);
      expect(alerts.single.kind, AbuseKind.heavyUser);
      expect(alerts.single.user, 'big');
      // Tout le monde consomme beaucoup : personne n'est signalé.
      expect(
        detectAbuse([active('1', 'a', 'M1', 2 * gb), active('2', 'b', 'M2', 2 * gb)]),
        isEmpty,
      );
    });

    test('rien d\'anormal', () {
      expect(detectAbuse([active('1', 'a', 'M1', 1000)]), isEmpty);
    });
  });

  group('bénéfice net', () {
    test('encaissé moins coûts mensuels et par ticket', () {
      final sales = [
        for (var i = 0; i < 10; i++) sale(DateTime(2026, 11, 1 + i), 'u$i', '24H', 500),
        sale(DateTime(2026, 10, 30), 'old', '24H', 500), // autre mois
      ];
      final r = NetProfit.forMonth(sales, DateTime(2026, 11), [
        const CostItem(label: 'Starlink', amount: 2000, perTicket: false),
        const CostItem(label: 'Papier', amount: 10, perTicket: true),
      ]);
      expect(r.revenue, 5000);
      expect(r.tickets, 10);
      expect(r.monthlyCosts, 2000);
      expect(r.perTicketCosts, 100);
      expect(r.net, 2900);
      expect(r.margin, closeTo(58, 0.1));
    });

    test('coûts conservés par routeur', () async {
      SharedPreferences.setMockInitialValues({});
      await CostStore('r1').save(const [CostItem(label: 'Starlink', amount: 2000, perTicket: false)]);
      expect((await CostStore('r1').load()).single.label, 'Starlink');
      expect(await CostStore('r2').load(), isEmpty);
    });
  });

  group('vente rapide', () {
    test('message pour le client', () {
      const v = Voucher(name: '482913', password: '482913', profile: '24H', uptime: '1d', dataLimit: '1 Go');
      final m = ticketMessage(network: 'Wifi zone', voucher: v, loginAddress: 'wifi.local');
      expect(m, contains('Code : 482913'));
      expect(m, contains('Durée : 1d'));
      expect(m, contains('Données : 1 Go'));
      expect(m, contains('http://wifi.local'));
      const sep = Voucher(name: 'abc', password: 'xyz', profile: '1H');
      final m2 = ticketMessage(network: 'Wifi zone', voucher: sep);
      expect(m2, contains('Utilisateur : abc'));
      expect(m2, contains('Mot de passe : xyz'));
      expect(m2, isNot(contains('Connexion')));
    });
  });

  group('appareils bloqués (routeur simulé)', () {
    test('bloquer coupe la session, lister, débloquer, MAC invalide refusée', () async {
      final router = await FakeRouter.start();
      addTearDown(router.stop);
      final client = RouterOsClient(
        host: '127.0.0.1',
        port: router.port,
        useSsl: false,
        username: 'admin',
        password: 'secret',
        connectTimeout: const Duration(seconds: 2),
        commandTimeout: const Duration(seconds: 5),
      );
      addTearDown(client.close);
      await client.connect();
      final service = MikhmonService(
          client, Session(id: 's', name: 'Wifi', host: '127.0.0.1', username: 'admin'));
      router.active.add({'.id': '*A1', 'user': 'K1', 'mac-address': 'AA:BB:CC:11:22:33', 'address': '10.0.0.2'});

      await expectLater(service.blockDevice('pas-une-mac'), throwsA(isA<RouterOsException>()));
      await service.blockDevice('aa:bb:cc:11:22:33', note: 'K1');
      expect(router.active, isEmpty);
      final blocked = await service.blockedDevices();
      expect(blocked.single.mac, 'AA:BB:CC:11:22:33');
      expect(blocked.single.comment, contains('mkm-bloque'));
      await service.unblockDevice(blocked.single.id);
      expect(await service.blockedDevices(), isEmpty);
    });
  });
}
