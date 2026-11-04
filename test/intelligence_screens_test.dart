import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/routeros/api_client.dart';
import 'package:mtandao_ticket/screens/abuse_screen.dart';
import 'package:mtandao_ticket/screens/cash_screen.dart';
import 'package:mtandao_ticket/screens/dashboard_screen.dart';
import 'package:mtandao_ticket/screens/profit_screen.dart';
import 'package:mtandao_ticket/screens/quick_sale_screen.dart';
import 'package:mtandao_ticket/services/mikhmon_service.dart';
import 'package:mtandao_ticket/util.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_router.dart';

Future<void> settle(WidgetTester tester, [int rounds = 25]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
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
      router.profiles.add({
        '.id': '*P1',
        'name': '24H',
        'shared-users': '1',
        'on-login': '#mkm:price=500;uptime=1d\n',
      });
      router.hotspotUsers.addAll([
        {'.id': '*U1', 'name': 'PAID1', 'profile': '24H', 'comment': 'used-vc-1', 'uptime': '5m', 'bytes-in': '5000'},
        {'.id': '*U2', 'name': 'NOSALE', 'profile': '24H', 'comment': 'used-vc-1', 'uptime': '9m', 'bytes-in': '9000'},
        {'.id': '*U3', 'name': 'FRESH', 'profile': '24H', 'comment': 'vc-021126-1400'},
      ]);
      router.scripts.add({
        '.id': '*S1',
        'comment': 'mikhmon',
        'name': '$today-|-10:05:00-|-PAID1-|-500-|-10.5.50.21-|-AA:BB-|-1d-|-24H-|-vc-1',
      });
      router.active.addAll([
        {'.id': '*A1', 'user': 'SHARED', 'mac-address': 'AA:AA:AA:AA:AA:01', 'address': '10.0.0.2'},
        {'.id': '*A2', 'user': 'SHARED', 'mac-address': 'AA:AA:AA:AA:AA:02', 'address': '10.0.0.3'},
      ]);
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

  testWidgets('accueil : ventes du jour, connectés, points à vérifier, stock', (tester) async {
    await start(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DashboardScreen(service: service, session: session)),
    ));
    await settle(tester);
    expect(find.text('Aujourd\'hui'), findsOneWidget);
    expect(find.text(formatMoney(500, 'FC')), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // connectés
    expect(find.textContaining('1 comportement(s) suspect(s)'), findsOneWidget);
    expect(find.textContaining('1 ticket(s) utilisé(s) sans vente'), findsOneWidget);
    expect(find.textContaining('24H : 1 en stock'), findsOneWidget);
    expect(find.text('Vente rapide'), findsOneWidget);
    await stop(tester);
  });

  testWidgets('caisse : écart saisi puis clôture enregistrée', (tester) async {
    await start(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CashScreen(service: service, session: session)),
    ));
    await settle(tester);
    expect(find.text(formatMoney(500, 'FC')), findsWidgets);
    expect(find.text('NOSALE'), findsOneWidget); // utilisé sans vente
    expect(find.text('PAID1'), findsNothing);
    await tester.enterText(find.byType(TextField), '400');
    await tester.pump();
    expect(find.textContaining('Il manque'), findsOneWidget);
    await tester.tap(find.text('Clôturer la journée'));
    await settle(tester, 10);
    expect(find.text('Mettre à jour la clôture'), findsOneWidget);
    expect(find.textContaining('encaissé'), findsWidgets);
    await stop(tester);
  });

  testWidgets('abus : ticket partagé signalé, appareil bloqué puis débloqué', (tester) async {
    await start(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AbuseScreen(service: service)),
    ));
    await settle(tester);
    expect(find.text('SHARED'), findsOneWidget);
    expect(find.textContaining('2 appareils'), findsOneWidget);
    await tester.tap(find.byTooltip('Bloquer cet appareil').first);
    await settle(tester, 5);
    await tester.tap(find.text('Bloquer'));
    await settle(tester, 20);
    expect(router.bindings.single['mac-address'], 'AA:AA:AA:AA:AA:01');
    expect(find.text('Débloquer'), findsOneWidget);
    await tester.tap(find.text('Débloquer'));
    await settle(tester, 20);
    expect(router.bindings, isEmpty);
    await stop(tester);
  });

  testWidgets('bénéfice net : un coût ajouté fait baisser le résultat', (tester) async {
    await start(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ProfitScreen(service: service, session: session)),
    ));
    await settle(tester);
    expect(find.text('Bénéfice net'), findsOneWidget);
    await tester.tap(find.text('Ajouter'));
    await settle(tester, 5);
    await tester.enterText(find.byType(TextFormField).at(0), 'Starlink');
    await tester.enterText(find.byType(TextFormField).at(1), '200');
    await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
    await settle(tester, 15);
    expect(find.text('Starlink'), findsOneWidget);
    expect(find.text(formatMoney(300, 'FC')), findsWidgets); // 500 - 200
    await stop(tester);
  });

  testWidgets('vente rapide : un ticket est créé sur le routeur et affiché', (tester) async {
    await start(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: QuickSaleScreen(service: service, session: session)),
    ));
    await settle(tester);
    await tester.tap(find.text('Créer le ticket'));
    await settle(tester, 30);
    final made = router.hotspotUsers.where((u) => (u['comment'] ?? '').startsWith('vc-') && u['name'] != 'FRESH');
    expect(made.length, 1);
    expect(find.text(made.single['name']!), findsOneWidget);
    expect(find.text('Envoyer (WhatsApp, SMS…)'), findsOneWidget);
    expect(find.text('Copier le message'), findsOneWidget);
    await stop(tester);
  });
}
