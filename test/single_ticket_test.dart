import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/routeros/api_client.dart';
import 'package:mtandao_ticket/screens/single_ticket_screen.dart';
import 'package:mtandao_ticket/services/mikhmon_service.dart';

import 'support/fake_router.dart';

Future<({FakeRouter router, MikhmonService service, Session session})> setUp1() async {
  final r = await FakeRouter.start();
  addTearDown(r.stop);
  final c = RouterOsClient(
    host: '127.0.0.1',
    port: r.port,
    useSsl: false,
    username: 'admin',
    password: 'secret',
    connectTimeout: const Duration(seconds: 2),
    commandTimeout: const Duration(seconds: 5),
  );
  addTearDown(c.close);
  final session = Session(id: 's', name: 'Wifi', host: '127.0.0.1', username: 'admin');
  r.profiles.add({'.id': '*P1', 'name': '1H', 'on-login': '#mkm:price=100;uptime=1h\n'});
  return (router: r, service: MikhmonService(c, session), session: session);
}

void main() {
  const p = HotspotProfile(name: '1H', price: 100, uptime: '1h');

  test('cleanNote garde un texte simple', () {
    expect(cleanNote('  Jean   |"Paul" \$x  '), 'Jean Paul x');
    expect(cleanNote('a' * 50).length, 30);
  });

  group('ticket sur mesure', () {
    test('code, mot de passe, appareil, durée, données et nom', () async {
      final t = await setUp1();
      final v = (await t.service.generate(const GenerateRequest(
        profile: p,
        count: 1,
        timeLimit: '3h',
        dataLimit: '1G',
        customCode: 'jean01',
        customPassword: 'pw99',
        bindMac: 'aa:bb:cc:dd:ee:ff',
        note: 'Jean',
      )))
          .single;
      expect(v.name, 'jean01');
      final u = t.router.hotspotUsers.single;
      expect(u['name'], 'jean01');
      expect(u['password'], 'pw99');
      expect(u['mac-address'], 'AA:BB:CC:DD:EE:FF');
      expect(u['limit-uptime'], '3h');
      expect(u['limit-bytes-total'], '1073741824');
      expect(u['comment'], contains('Jean'));
      expect(u['comment'], startsWith('up-'));
    });

    test('code seul : le mot de passe est identique', () async {
      final t = await setUp1();
      await t.service.generate(const GenerateRequest(profile: p, count: 1, customCode: 'abc.12'));
      final u = t.router.hotspotUsers.single;
      expect(u['password'], 'abc.12');
      expect(u['comment'], startsWith('vc-'));
    });

    test('code déjà pris', () async {
      final t = await setUp1();
      const r = GenerateRequest(profile: p, count: 1, customCode: 'dup01');
      await t.service.generate(r);
      await expectLater(t.service.generate(r), throwsA(isA<RouterOsException>()));
      expect(t.router.hotspotUsers.length, 1);
    });

    test('entrées invalides refusées', () async {
      final t = await setUp1();
      for (final r in [
        const GenerateRequest(profile: p, count: 1, customCode: 'a b'),
        const GenerateRequest(profile: p, count: 1, customCode: 'ab'),
        const GenerateRequest(profile: p, count: 2, customCode: 'abcd'),
        const GenerateRequest(profile: p, count: 1, bindMac: 'zz'),
      ]) {
        await expectLater(t.service.generate(r), throwsA(isA<RouterOsException>()));
      }
      expect(t.router.hotspotUsers, isEmpty);
    });

    testWidgets('écran : création puis affichage du ticket', (tester) async {
      final t = await setUp1();
      await tester.runAsync(() async {
        await tester.binding.setSurfaceSize(const Size(800, 1800));
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SingleTicketScreen(service: t.service, session: t.session)),
        ));
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
        await tester.enterText(find.widgetWithText(TextFormField, 'Code choisi (facultatif)'), 'client7');
        await tester.enterText(find.widgetWithText(TextFormField, 'Nom du client (facultatif)'), 'Marie');
        await tester.tap(find.text('Créer le ticket'));
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });
      expect(t.router.hotspotUsers.single['name'], 'client7');
      expect(find.text('client7'), findsWidgets);
      expect(find.textContaining('pour Marie'), findsOneWidget);
      expect(find.text('Envoyer (WhatsApp, SMS…)'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });
  });
}
