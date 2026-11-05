import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/routeros/api_client.dart';
import 'package:mtandao_ticket/screens/diagnosis_screen.dart';
import 'package:mtandao_ticket/services/diagnosis.dart';
import 'package:mtandao_ticket/services/mikhmon_service.dart';

import 'support/fake_router.dart';

HotspotUser u(String name,
        {bool disabled = false,
        Duration uptime = Duration.zero,
        Duration? limit = const Duration(hours: 1),
        String bound = '',
        String password = ''}) =>
    HotspotUser(
      id: '*$name',
      name: name,
      password: password.isEmpty ? name : password,
      profile: '1H',
      comment: 'vc-1',
      disabled: disabled,
      uptime: uptime,
      limitUptime: limit,
      bytesIn: 0,
      bytesOut: 0,
      limitBytes: 0,
      boundMac: bound,
    );

Sale sale(String user, {String mac = 'AA:BB:CC:00:00:01'}) => Sale(
      time: DateTime(2026, 11, 3, 10, 5),
      user: user,
      price: 100,
      address: '10.5.50.9',
      mac: mac,
      uptime: '1h',
      profile: '1H',
      comment: 'vc-1',
    );

Diagnosis run(String code,
        {List<HotspotUser> users = const [],
        List<Sale> sales = const [],
        List<ActiveUser> active = const [],
        List<BlockedDevice> blocked = const []}) =>
    diagnoseTicket(code, users: users, sales: sales, active: active, blocked: blocked);

void main() {
  group('diagnostic de ticket', () {
    test('ticket valide : pas de problème', () {
      final d = run('abc123', users: [u('abc123')]);
      expect(d.hasProblem, isFalse);
      expect(d.verdict, 'Le ticket est valide.');
    });

    test('désactivé, épuisé, lié à un appareil', () {
      expect(run('a', users: [u('a', disabled: true)]).actions, contains(DiagAction.reactivate));
      final out = run('a', users: [u('a', uptime: const Duration(hours: 1))]);
      expect(out.hasProblem, isTrue);
      expect(out.actions, containsAll([DiagAction.extend, DiagAction.resetCounters, DiagAction.replace]));
      final bound = run('a', users: [u('a', bound: 'AA:BB:CC:00:00:09')]);
      expect(bound.hasProblem, isTrue);
      expect(bound.actions, contains(DiagAction.unbind));
    });

    test('appareil bloqué', () {
      final d = run('a',
          users: [u('a')],
          sales: [sale('a', mac: 'aa:bb:cc:00:00:01')],
          blocked: const [BlockedDevice(id: '*B', mac: 'AA:BB:CC:00:00:01', comment: '')]);
      expect(d.hasProblem, isTrue);
      expect(d.actions, contains(DiagAction.unblock));
      expect(d.blocked.length, 1);
    });

    test('supprimé après vente : expiré, remplaçable', () {
      final d = run('old', sales: [sale('old')]);
      expect(d.verdict, 'Ticket expiré.');
      expect(d.actions, contains(DiagAction.replace));
      expect(d.profile, '1H');
    });

    test('code inconnu, faute de frappe, majuscules', () {
      final typo = run('abc124', users: [u('abc123')]);
      expect(typo.similar, ['abc123']);
      final swap = run('abc132', users: [u('abc123')]);
      expect(swap.similar, ['abc123']);
      final caps = run('ABC123', users: [u('abc123')]);
      expect(caps.verdict, contains('Majuscules'));
      expect(run('zzz', users: [u('abc123')]).similar, isEmpty);
    });
  });

  group('écran', () {
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
      router.profiles.add({'.id': '*P1', 'name': '1H', 'on-login': '#mkm:price=100;uptime=1h\n'});
      router.hotspotUsers.add({
        '.id': '*U1',
        'name': 'abc123',
        'password': 'abc123',
        'profile': '1H',
        'comment': 'vc-1',
        'disabled': 'true',
        'limit-uptime': '1h',
      });
    });

    tearDown(() async {
      client.close();
      await router.stop();
    });

    testWidgets('trouve un ticket désactivé et le réactive', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DiagnosisScreen(
              service: service, session: Session(id: 's', name: 'Wifi', host: '127.0.0.1', username: 'admin')),
        ),
      ));
      await tester.enterText(find.byType(TextField), 'abc123');
      await tester.tap(find.text('Vérifier le ticket'));
      for (var i = 0; i < 25; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(find.text('Un problème trouvé.'), findsOneWidget);
      expect(find.text('Le ticket est désactivé.'), findsOneWidget);
      await tester.tap(find.text('Réactiver'));
      for (var i = 0; i < 25; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(router.hotspotUsers.first['disabled'], anyOf('false', 'no'));
      expect(find.text('Le ticket est valide.'), findsOneWidget);
    });
  });
}
