import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/routeros/api_client.dart';
import 'package:mtandao_ticket/screens/network_screen.dart';
import 'package:mtandao_ticket/screens/profile_form_screen.dart';
import 'package:mtandao_ticket/screens/search_screen.dart';
import 'package:mtandao_ticket/services/mikhmon_service.dart';
import 'package:mtandao_ticket/services/search.dart';
import 'package:mtandao_ticket/services/speed.dart';
import 'package:mtandao_ticket/util.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_router.dart';

Future<void> settle(WidgetTester tester, [int rounds = 25]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Sale sale(DateTime t, String user, int price, {String mac = 'AA:BB:CC:00:00:01', String profile = '24H'}) =>
    Sale(
      time: t,
      user: user,
      price: price,
      address: '10.5.50.9',
      mac: mac,
      uptime: '1d',
      profile: profile,
      comment: 'vc-1',
    );

HotspotUser user(String name, {String profile = '24H', bool used = true, String bound = ''}) => HotspotUser(
      id: '*$name',
      name: name,
      password: name,
      profile: profile,
      comment: used ? 'used-vc-1' : 'vc-1',
      disabled: false,
      uptime: used ? const Duration(minutes: 3) : Duration.zero,
      limitUptime: const Duration(days: 1),
      bytesIn: used ? 1000 : 0,
      bytesOut: 0,
      limitBytes: 0,
      boundMac: bound,
    );

void main() {
  group('vitesses', () {
    test('lecture et écriture des débits', () {
      expect(parseRateBits('2M'), 2000000);
      expect(parseRateBits('512k'), 512000);
      expect(parseRateBits('abc'), isNull);
      expect(formatRateBits(1500000), '1500k');
      expect(formatRateBits(4000000), '4M');
      expect(normalizeRate('2M'), '2M/2M');
      expect(normalizeRate('1M/5M'), '1M/5M');
      expect(isValidRate('1M/5M'), isTrue);
      expect(isValidRate('2 mega'), isFalse);
    });

    test('limite complète : départ rapide et minimum garanti', () {
      expect(buildRateLimit(const RateParts(base: '2M')), '2M/2M');
      expect(buildRateLimit(const RateParts()), '');
      expect(buildRateLimit(const RateParts(base: '2M', burst: true)), '2M/2M 4M/4M 1500k/1500k 10s/10s');
      expect(buildRateLimit(const RateParts(base: '1M/2M', burst: true, minimum: '256k')),
          '1M/2M 2M/4M 750k/1500k 10s/10s 8 256k/256k');
      expect(buildRateLimit(const RateParts(base: '2M', minimum: '128k')), '2M/2M 2M/2M 2M/2M 1s/1s 8 128k/128k');
    });

    test('relecture : on retrouve ce qu\'on a écrit', () {
      for (final p in const [
        RateParts(base: '2M/2M'),
        RateParts(base: '2M/2M', burst: true),
        RateParts(base: '1M/2M', burst: true, minimum: '256k/256k'),
        RateParts(base: '2M/2M', minimum: '128k/128k'),
      ]) {
        final back = parseRateLimit(buildRateLimit(p));
        expect(back.base, p.base);
        expect(back.burst, p.burst);
        expect(back.minimum, p.minimum);
      }
      expect(parseRateLimit('').base, '');
    });

    test('réseau d\'une adresse', () {
      expect(networkOf('10.5.50.1/24'), '10.5.50.0/24');
      expect(networkOf('192.168.88.130/25'), '192.168.88.128/25');
      expect(networkOf('pas une adresse'), isNull);
    });
  });

  group('profil : lier le ticket à l\'appareil', () {
    test('le script ne lie l\'appareil que si demandé, et la case est relue', () {
      const plain = HotspotProfile(name: '24H', price: 500, uptime: '1d');
      const bound = HotspotProfile(name: '24H', price: 500, uptime: '1d', bindDevice: true);
      expect(plain.buildOnLogin(), isNot(contains('mac-address=')));
      expect(bound.buildOnLogin(), contains(r'mac-address=$"mac-address"'));
      expect(bound.buildOnLogin(), startsWith('#mkm:price=500;uptime=1d;bind=1'));
      final back = HotspotProfile.fromRow({'name': '24H', 'on-login': bound.buildOnLogin()});
      expect(back.bindDevice, isTrue);
      expect(back.price, 500);
      expect(HotspotProfile.fromRow({'name': 'x', 'on-login': plain.buildOnLogin()}).bindDevice, isFalse);
    });
  });

  group('routeur simulé : bande passante et connexions', () {
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
      router.profiles.addAll([
        {'.id': '*P1', 'name': '24H', 'on-login': '#mkm:price=500;uptime=1d\n'},
        {'.id': '*P2', 'name': '1H', 'on-login': '#mkm:price=100;uptime=1h\n'},
      ]);
      router.hotspots.add({'.id': '*H1', 'interface': 'bridge-lan'});
      router.addresses.add({'.id': '*A1', 'interface': 'bridge-lan', 'address': '10.5.50.1/24'});
    });

    tearDown(() async {
      client.close();
      await router.stop();
    });

    test('l\'enveloppe commune est créée, rattachée aux profils, retirée', () async {
      expect(await service.sharedBandwidth(), isNull);
      expect(await service.detectHotspotNetwork(), '10.5.50.0/24');
      await expectLater(
          service.enableSharedBandwidth(downMbps: 0, upMbps: 10, target: '10.5.50.0/24'),
          throwsA(isA<RouterOsException>()));

      await service.enableSharedBandwidth(downMbps: 80, upMbps: 40, target: '10.5.50.0/24');
      final q = router.queues.single;
      expect(q['name'], 'mkm-total');
      expect(q['max-limit'], '40M/80M');
      expect(router.profiles.every((p) => p['parent-queue'] == 'mkm-total'), isTrue);
      final shared = (await service.sharedBandwidth())!;
      expect(shared.downBits, 80000000);
      expect(shared.upBits, 40000000);

      // Un profil créé ensuite rejoint l'enveloppe.
      await service.saveProfile(const HotspotProfile(name: '7J', price: 2000, uptime: '7d'));
      expect(router.profiles.last['parent-queue'], 'mkm-total');

      // Mise à jour : pas de doublon.
      await service.enableSharedBandwidth(downMbps: 100, upMbps: 50, target: '10.5.50.0/24');
      expect(router.queues.length, 1);
      expect(router.queues.single['max-limit'], '50M/100M');

      await service.disableSharedBandwidth();
      expect(router.queues, isEmpty);
      expect(router.profiles.every((p) => p['parent-queue'] == 'none'), isTrue);
      expect((await service.profiles()).every((p) => p.parentQueue.isEmpty), isTrue);
    });

    test('modifier un profil conserve son enveloppe', () async {
      await service.enableSharedBandwidth(downMbps: 80, upMbps: 40, target: '10.5.50.0/24');
      final p = (await service.profiles()).first;
      await service.saveProfile(HotspotProfile(
          id: p.id, name: p.name, price: 600, uptime: '1d', parentQueue: p.parentQueue));
      expect(router.profiles.first['parent-queue'], 'mkm-total');
    });

    test('limite de connexions : règle placée en premier, mise à jour, retirée', () async {
      router.firewall.add({'.id': '*F1', 'chain': 'forward', 'action': 'accept', 'comment': 'défaut'});
      expect(await service.connectionLimit(), isNull);
      await expectLater(service.setConnectionLimit(5), throwsA(isA<RouterOsException>()));
      await service.setConnectionLimit(300);
      expect(router.firewall.first['comment'], 'mkm-connlimit');
      expect(router.firewall.first['connection-limit'], '300,32');
      expect(await service.connectionLimit(), 300);
      await service.setConnectionLimit(500);
      expect(router.firewall.length, 2);
      expect(await service.connectionLimit(), 500);
      await service.setConnectionLimit(null);
      expect(router.firewall.single['comment'], 'défaut');
      expect(await service.connectionLimit(), isNull);
    });

    test('un ticket lié à un appareil peut être libéré', () async {
      router.hotspotUsers.add({'.id': '*U1', 'name': 'T1', 'mac-address': 'AA:BB:CC:11:22:33'});
      expect((await service.hotspotUsers()).single.boundMac, 'AA:BB:CC:11:22:33');
      await service.unbindUser('*U1');
      expect((await service.hotspotUsers()).single.boundMac, '');
    });
  });

  group('recherche', () {
    final now = DateTime(2026, 11, 4, 18);
    final users = [user('482913'), user('777000', used: false), user('555111', bound: 'AA:BB:CC:00:00:02')];
    final sales = [
      sale(DateTime(2026, 11, 4, 14, 5), '482913', 500),
      sale(DateTime(2026, 11, 4, 9, 30), '999000', 100, mac: 'AA:BB:CC:00:00:03', profile: '1H'),
      sale(DateTime(2026, 10, 20, 14, 0), '123123', 500), // trop ancienne pour une recherche par heure
    ];
    const active = [
      ActiveUser(
          id: '*1', user: '482913', address: '10.5.50.9', mac: 'AA:BB:CC:00:00:01', uptime: '10m', bytesIn: 1, bytesOut: 1),
    ];
    const leases = [
      DhcpLease(address: '10.5.50.9', mac: 'AA:BB:CC:00:00:01', hostName: 'tecno-spark', status: 'bound', comment: ''),
    ];

    SearchResult run(String q) =>
        search(q, users: users, sales: sales, active: active, leases: leases, now: now);

    test('par code, avec sa vente et sa session', () {
      final r = run('4829');
      expect(r.tickets.map((t) => t.name), ['482913']);
      expect(r.tickets.single.sales.length, 1);
      expect(r.tickets.single.sessions.length, 1);
    });

    test('par heure et montant : ventes vers 14 h à 500', () {
      final r = run('500 14h');
      expect(r.tickets.map((t) => t.name), ['482913']);
      expect(run('14h').tickets.map((t) => t.name), ['482913']); // la vente du 20/10 est exclue
      expect(run('9h').tickets.map((t) => t.name), ['999000']);
      // Le ticket supprimé du routeur est quand même retrouvé par sa vente.
      expect(run('9h').tickets.single.user, isNull);
    });

    test('par appareil : tickets liés, ventes et appareil du DHCP', () {
      final r = run('aa:bb:cc:00:00:02');
      expect(r.tickets.map((t) => t.name), ['555111']);
      final d = run('tecno');
      expect(d.devices.single.mac, 'AA:BB:CC:00:00:01');
      expect(d.devices.single.tickets, unorderedEquals(['482913', '123123']));
    });

    test('requête vide ou sans résultat', () {
      expect(run('   ').isEmpty, isTrue);
      expect(run('zzzz').isEmpty, isTrue);
    });
  });

  group('écrans', () {
    late FakeRouter router;
    late RouterOsClient client;
    late MikhmonService service;
    final session = Session(id: 's', name: 'Wifi zone', host: '127.0.0.1', username: 'admin');

    Future<void> start(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      final today = '${now.year}-${two(now.month)}-${two(now.day)}';
      await tester.runAsync(() async {
        router = await FakeRouter.start();
        router.profiles.add({'.id': '*P1', 'name': '24H', 'on-login': '#mkm:price=500;uptime=1d\n'});
        router.hotspotUsers.add({
          '.id': '*U1',
          'name': 'K482913',
          'profile': '24H',
          'comment': 'used-vc-1',
          'uptime': '5m',
          'limit-uptime': '1d',
          'bytes-in': '5000',
        });
        router.scripts.add({
          '.id': '*S1',
          'comment': 'mikhmon',
          'name': '$today-|-14:05:00-|-K482913-|-500-|-10.5.50.21-|-AA:BB:CC:00:00:01-|-1d-|-24H-|-vc-1',
        });
        router.hotspots.add({'.id': '*H1', 'interface': 'bridge-lan'});
        router.addresses.add({'.id': '*A1', 'interface': 'bridge-lan', 'address': '10.5.50.1/24'});
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
      });
      service = MikhmonService(client, session);
    }

    Future<void> stop(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        client.close();
        await router.stop();
      });
    }

    testWidgets('recherche : on retrouve un ticket par heure et montant, puis on agit', (tester) async {
      await start(tester);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SearchScreen(service: service, session: session)),
      ));
      await settle(tester);
      await tester.enterText(find.byType(TextField), '500 14h');
      await settle(tester, 3);
      expect(find.text('K482913'), findsOneWidget);
      expect(find.textContaining('Vendu le'), findsOneWidget);
      expect(find.text('Renvoyer au client'), findsOneWidget);
      await tester.ensureVisible(find.text('Désactiver'));
      await tester.tap(find.text('Désactiver'));
      await settle(tester, 20);
      expect(router.hotspotUsers.single['disabled'], 'yes');
      await stop(tester);
    });

    testWidgets('vitesse et équité : activer l\'enveloppe et la limite de connexions', (tester) async {
      await start(tester);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NetworkScreen(service: service)),
      ));
      await settle(tester);
      expect(find.textContaining('Détecté sur le routeur : 10.5.50.0/24'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), '80');
      await tester.enterText(find.byType(TextField).at(1), '40');
      await tester.tap(find.text('Activer').first);
      await settle(tester, 20);
      expect(router.queues.single['max-limit'], '40M/80M');
      expect(router.queues.single['target'], '10.5.50.0/24');
      await tester.ensureVisible(find.text('Activer').last);
      await tester.tap(find.text('Activer').last);
      await settle(tester, 20);
      expect(router.firewall.single['connection-limit'], '300,32');
      await stop(tester);
    });

    testWidgets('formulaire de profil : départ rapide, minimum garanti et liaison relus puis enregistrés',
        (tester) async {
      await start(tester);
      const profile = HotspotProfile(
        id: '*P1',
        name: '24H',
        rateLimit: '2M/2M 4M/4M 1500k/1500k 10s/10s 8 256k/256k',
        price: 500,
        uptime: '1d',
        bindDevice: true,
      );
      await tester.pumpWidget(MaterialApp(
        home: ProfileFormScreen(service: service, session: session, profile: profile),
      ));
      await settle(tester, 3);
      expect(find.widgetWithText(SwitchListTile, 'Départ rapide'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Départ rapide')).value, isTrue);
      expect(find.text('256k/256k'), findsOneWidget);
      expect(find.text('2M/2M'), findsOneWidget);
      await tester.ensureVisible(find.text('Enregistrer sur le routeur'));
      await tester.tap(find.text('Enregistrer sur le routeur'));
      await settle(tester, 20);
      final saved = router.profiles.single;
      expect(saved['rate-limit'], '2M/2M 4M/4M 1500k/1500k 10s/10s 8 256k/256k');
      expect(saved['on-login'], contains('bind=1'));
      await stop(tester);
    });
  });
}
