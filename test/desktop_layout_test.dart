import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/routeros/api_client.dart';
import 'package:mtandao_ticket/screens/home_shell.dart';
import 'package:mtandao_ticket/services/mikhmon_service.dart';

import 'support/fake_router.dart';

Future<void> settle(WidgetTester tester, [int rounds = 25]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  testWidgets('ordinateur : barre latérale, deux colonnes, écrans secondaires dans le contenu',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late FakeRouter router;
    late RouterOsClient client;
    await tester.runAsync(() async {
      router = await FakeRouter.start();
      router.profiles.add({
        '.id': '*P1',
        'name': '24H',
        'shared-users': '1',
        'on-login': '#mkm:price=500;uptime=1d\n',
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

    try {
      final session = Session(id: 's', name: 'Wifi zone', host: '127.0.0.1', username: 'admin');
      await tester.pumpWidget(MaterialApp(
        home: HomeShell(session: session, service: MikhmonService(client, session)),
      ));
      await settle(tester);

      // Pas de barre du bas : une barre latérale à la place.
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byKey(const ValueKey('nav-Ventes')), findsOneWidget);
      expect(find.text('Changer de routeur'), findsOneWidget);

      // Générer : formulaire sur deux colonnes (limite de temps à gauche, nombre à droite).
      final left = tester.getTopLeft(find.text('Limite de temps').first);
      final right = tester.getTopLeft(find.text('Nombre de tickets').first);
      expect(right.dx, greaterThan(left.dx + 300));

      // Plus : cartes ; ouvrir Profils garde la barre latérale visible.
      await tester.tap(find.byKey(const ValueKey('nav-Plus')));
      await settle(tester, 5);
      await tester.tap(find.text('Profils'));
      await settle(tester);
      expect(find.text('24H'), findsWidgets);
      expect(find.byKey(const ValueKey('nav-Ventes')), findsOneWidget);

      // Changer d'onglet ferme l'écran secondaire.
      await tester.tap(find.byKey(const ValueKey('nav-Actifs')));
      await settle(tester);
      expect(find.text('24H'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      client.close();
      await router.stop();
    });
  });
}
