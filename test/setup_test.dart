import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/routeros/api_client.dart';
import 'package:mtandao_ticket/screens/hotspot_setup_screen.dart';
import 'package:mtandao_ticket/services/hotspot_setup.dart';
import 'package:mtandao_ticket/services/mikhmon_service.dart';

import 'support/fake_router.dart';

const _facts = RouterFacts(
  interfaces: ['ether1', 'wlan1', 'bridge'],
  addresses: [
    {'address': '192.168.88.1/24', 'interface': 'bridge'}
  ],
  users: [
    {'name': 'admin'}
  ],
  services: [
    {'.id': '*1', 'name': 'telnet', 'disabled': 'false'},
    {'.id': '*2', 'name': 'ssh', 'disabled': 'false'},
    {'.id': '*3', 'name': 'www', 'disabled': 'false'},
  ],
);

HotspotSetup _setup({String wan = 'ether1', String password = '', String dns = ''}) => HotspotSetup(
      lanInterface: 'bridge',
      wanInterface: wan,
      dnsName: dns,
      adminPassword: password,
      profiles: const [SetupProfile(name: '1H', price: 100, uptime: '1h')],
    );

void main() {
  group('plan d\'installation', () {
    test('plage d\'adresses', () {
      expect(poolRange('10.5.50.1/24'), '10.5.50.10-10.5.50.254');
      expect(poolRange('192.168.88.1/24'), '192.168.88.10-192.168.88.254');
      expect(poolRange('10.0.0.1/30'), isNull);
      expect(poolRange('abc'), isNull);
    });

    test('garde l\'adresse existante et crée le reste', () {
      final steps = planHotspotSetup(_setup(password: 'motdepasse1'), _facts);
      final cmds = steps.map((s) => s.words.isEmpty ? '' : s.words.first).toList();
      expect(cmds, isNot(contains('/ip/address/add')));
      expect(cmds, containsAll(['/ip/pool/add', '/ip/dhcp-server/add', '/ip/firewall/nat/add',
          '/ip/hotspot/profile/add', '/ip/hotspot/add', '/user/set']));
      expect(steps.where((s) => s.profile != null).length, 1);
      // telnet et www seulement (ssh reste actif)
      expect(steps.where((s) => s.title.startsWith('Désactiver')).length, 2);
      expect(steps.last.secret, isTrue);
      final pool = steps.firstWhere((s) => s.words.isNotEmpty && s.words.first == '/ip/pool/add');
      expect(pool.words, contains('=ranges=192.168.88.10-192.168.88.254'));
    });

    test('refus clairs', () {
      expect(() => planHotspotSetup(_setup(wan: ''), _facts), throwsA(isA<RouterOsException>()));
      expect(() => planHotspotSetup(_setup(wan: 'bridge'), _facts), throwsA(isA<RouterOsException>()));
      expect(() => planHotspotSetup(_setup(password: 'court'), _facts), throwsA(isA<RouterOsException>()));
      expect(() => planHotspotSetup(_setup(dns: 'mauvais nom!'), _facts), throwsA(isA<RouterOsException>()));
      expect(
          () => planHotspotSetup(
              _setup(),
              const RouterFacts(interfaces: ['ether1', 'bridge'], hotspots: [
                {'name': 'h', 'interface': 'bridge'}
              ])),
          throwsA(isA<RouterOsException>()));
    });
  });

  group('routeur simulé : installation', () {
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
      router.interfaces.add({'name': 'bridge', 'running': 'true', 'disabled': 'false'});
      router.addresses.add({'.id': '*A1', 'interface': 'bridge', 'address': '192.168.88.1/24'});
      router.tables['/user']!.add({'.id': '*U1', 'name': 'admin'});
      router.tables['/ip/service']!.addAll([
        {'.id': '*S1', 'name': 'telnet', 'disabled': 'false'},
        {'.id': '*S2', 'name': 'www', 'disabled': 'false'},
      ]);
    });

    tearDown(() async {
      client.close();
      await router.stop();
    });

    test('installation puis annulation', () async {
      final facts = await service.routerFacts();
      expect(facts.interfaces, contains('bridge'));
      expect(facts.hotspots, isEmpty);
      expect(facts.hasInstallLog, isFalse);

      final steps = planHotspotSetup(_setup(password: 'motdepasse1'), facts);
      final progress = <int>[];
      await service.runSetup(steps, onProgress: (d, t) => progress.add(d));
      expect(progress.last, steps.length);

      expect(router.hotspots.length, 1);
      expect(router.hotspots.first['interface'], 'bridge');
      expect(router.tables['/ip/pool']!.length, 1);
      expect(router.tables['/ip/firewall/nat']!.length, 1);
      expect(router.profiles.map((p) => p['name']), contains('1H'));
      expect(router.tables['/ip/service']!.every((s) => s['disabled'] == 'yes'), isTrue);
      expect(router.tables['/user']!.first['password'], 'motdepasse1');
      expect((await service.routerFacts()).hasInstallLog, isTrue);

      // Un hotspot existe maintenant : une 2e installation est refusée.
      final again = await service.routerFacts();
      expect(again.hotspots, isNotEmpty);
      expect(() => planHotspotSetup(_setup(), again), throwsA(isA<RouterOsException>()));

      await service.undoInstall();
      expect(router.hotspots, isEmpty);
      expect(router.tables['/ip/pool']!, isEmpty);
      expect(router.tables['/ip/firewall/nat']!, isEmpty);
      expect(router.profiles.map((p) => p['name']), isNot(contains('1H')));
      expect((await service.routerFacts()).hasInstallLog, isFalse);
    });

    test('échec : ce qui a été créé est retiré', () async {
      // Un hotspot apparaît entre le plan et l'exécution : le routeur refuse.
      final steps = planHotspotSetup(_setup(), await service.routerFacts());
      router.hotspots.add({'.id': '*H9', 'name': 'autre', 'interface': 'ether1'});
      await expectLater(service.runSetup(steps), throwsA(isA<RouterOsException>()));
      expect(router.tables['/ip/pool']!, isEmpty);
      expect(router.tables['/ip/hotspot/profile']!, isEmpty);
      expect(router.tables['/ip/firewall/nat']!, isEmpty);
      expect(router.hotspots.length, 1);
      expect((await service.routerFacts()).hasInstallLog, isFalse);
    });

    testWidgets('écran : plan affiché puis installation', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HotspotSetupScreen(
              service: service, session: Session(id: 's', name: 'Wifi', host: '127.0.0.1', username: 'admin')),
        ),
      ));
      for (var i = 0; i < 25; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(find.text('Nouveau hotspot'), findsOneWidget);
      await tester.tap(find.text('Voir le plan et installer'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Installer le hotspot ?'), findsOneWidget);
    });
  });
}
