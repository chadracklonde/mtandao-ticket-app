import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/routeros/api_client.dart';
import 'package:mtandao_ticket/screens/home_shell.dart';
import 'package:mtandao_ticket/services/mikhmon_service.dart';
import 'package:mtandao_ticket/util.dart';

import 'support/fake_router.dart';

/// Laisse le temps aux vraies connexions réseau (faux routeur local) de répondre.
Future<void> settle(WidgetTester tester, [int rounds = 25]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Finder inNav(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  testWidgets('parcours : générer, actifs, ventes, profils', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late FakeRouter router;
    late RouterOsClient client;
    final now = DateTime.now();
    final today = '${now.year}-${two(now.month)}-${two(now.day)}';

    await tester.runAsync(() async {
      router = await FakeRouter.start();
      router.profiles.add({
        '.id': '*P1',
        'name': '24H',
        'shared-users': '1',
        'on-login': '#mkm:price=500;uptime=1d\n',
      });
      router.hotspotUsers.add({
        '.id': '*U1',
        'name': 'K7M2Q9',
        'password': 'K7M2Q9',
        'profile': '24H',
        'comment': 'used-vc-021126-1400',
      });
      router.active.add({
        '.id': '*A1',
        'user': 'K7M2Q9',
        'address': '10.5.50.21',
        'mac-address': 'AA:BB',
        'uptime': '1h12m',
        'bytes-in': '1000',
        'bytes-out': '2000',
      });
      router.scripts.add({
        '.id': '*S1',
        'comment': 'mikhmon',
        'name': '$today-|-14:05:00-|-K7M2Q9-|-500-|-10.5.50.21-|-AA:BB-|-1d-|-24H-|-vc-021126-1400',
      });
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

    final session = Session(id: 's', name: 'Wifi zone', host: '127.0.0.1', username: 'admin');
    await tester.pumpWidget(MaterialApp(
      home: HomeShell(session: session, service: MikhmonService(client, session)),
    ));
    await settle(tester);

    // Générer : le profil du routeur est proposé, on crée 3 tickets.
    expect(find.text('Générer les tickets'), findsOneWidget);
    // Champs : limite de temps (préremplie par le profil), données, puis nombre de tickets.
    expect(find.text('1d'), findsWidgets);
    await tester.enterText(find.byType(TextFormField).at(2), '3');
    await tester.tap(find.text('Générer les tickets'));
    await settle(tester, 40);
    expect(find.text('3 tickets générés'), findsOneWidget);
    final made = router.hotspotUsers.where((u) => (u['comment'] ?? '').startsWith('vc-'));
    expect(made.length, 3);
    expect(made.every((u) => u['limit-uptime'] == '1d'), isTrue);
    await tester.pageBack();
    await settle(tester, 5);

    // Actifs
    await tester.tap(inNav('Actifs'));
    await settle(tester);
    expect(find.text('K7M2Q9'), findsWidgets);
    expect(find.textContaining('1 utilisateur(s) connecté(s)'), findsOneWidget);

    // Ventes : la vente d'aujourd'hui apparaît dans le rapport du jour.
    await tester.tap(inNav('Ventes'));
    await settle(tester, 60);
    expect(find.text('Tickets vendus'), findsOneWidget);
    expect(find.text(formatMoney(500, 'FC')), findsWidgets);

    // Plus > Profils
    await tester.tap(inNav('Plus'));
    await settle(tester, 5);
    await tester.tap(find.text('Profils'));
    await settle(tester);
    expect(find.text('24H'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      client.close();
      await router.stop();
    });
  });
}
