import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/routeros/api_client.dart';
import 'package:mtandao_ticket/util.dart';

import 'support/fake_router.dart';

RouterOsClient clientFor(FakeRouter r, {String password = 'secret'}) => RouterOsClient(
      host: '127.0.0.1',
      port: r.port,
      useSsl: false,
      username: 'admin',
      password: password,
      connectTimeout: const Duration(seconds: 2),
      commandTimeout: const Duration(seconds: 2),
    );

void main() {
  group('connexion (T1)', () {
    test('identification simple (RouterOS 6.43 et 7)', () async {
      final r = await FakeRouter.start();
      addTearDown(r.stop);
      final c = clientFor(r);
      addTearDown(c.close);
      await c.connect();
      expect(await c.run(['/ip/hotspot/active/print']), isEmpty);
    });

    test('mauvais mot de passe : message clair', () async {
      final r = await FakeRouter.start();
      addTearDown(r.stop);
      final c = clientFor(r, password: 'faux');
      addTearDown(c.close);
      await expectLater(
        c.connect(),
        throwsA(isA<RouterOsException>().having(
            (e) => e.message, 'message', 'Identifiant ou mot de passe incorrect.')),
      );
    });

    test('identification par défi MD5 (RouterOS avant 6.43)', () async {
      final r = await FakeRouter.start(md5Login: true);
      addTearDown(r.stop);
      final c = clientFor(r);
      addTearDown(c.close);
      await c.connect();
      expect(await c.run(['/ip/hotspot/active/print']), isEmpty);
    });

    test('défi MD5 avec mauvais mot de passe', () async {
      final r = await FakeRouter.start(md5Login: true);
      addTearDown(r.stop);
      final c = clientFor(r, password: 'faux');
      addTearDown(c.close);
      await expectLater(c.connect(), throwsA(isA<RouterOsException>()));
    });

    test('routeur injoignable : message lisible', () async {
      final r = await FakeRouter.start();
      final port = r.port;
      await r.stop();
      final c = RouterOsClient(
        host: '127.0.0.1',
        port: port,
        useSsl: false,
        username: 'admin',
        password: 'secret',
        connectTimeout: const Duration(seconds: 2),
      );
      Object? error;
      try {
        await c.connect();
      } catch (e) {
        error = e;
      }
      expect(error, isA<SocketException>());
      expect(describeError(error!), contains('Impossible de joindre le routeur'));
    });
  });

  group('commandes', () {
    test('erreur du routeur renvoyée telle quelle', () async {
      final r = await FakeRouter.start();
      addTearDown(r.stop);
      final c = clientFor(r);
      addTearDown(c.close);
      await expectLater(
        c.run(['/commande/inconnue']),
        throwsA(isA<RouterOsException>()
            .having((e) => e.message, 'message', 'no such command')),
      );
      // La connexion reste utilisable après une erreur.
      expect(await c.run(['/ip/hotspot/active/print']), isEmpty);
    });

    test('reconnexion automatique après une coupure', () async {
      final r = await FakeRouter.start();
      addTearDown(r.stop);
      final c = clientFor(r);
      addTearDown(c.close);
      await c.connect();
      expect(r.connectionCount, 1);
      r.dropConnections();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await c.run(['/ip/hotspot/active/print']), isEmpty);
      expect(r.connectionCount, 2);
    });

    test('commandes en parallèle : exécutées l\'une après l\'autre', () async {
      final r = await FakeRouter.start();
      addTearDown(r.stop);
      final c = clientFor(r);
      addTearDown(c.close);
      final results = await Future.wait([
        for (var i = 0; i < 20; i++)
          c.exec(['/ip/hotspot/user/add', '=name=u$i', '=password=u$i']),
      ]);
      expect(results.length, 20);
      expect(r.hotspotUsers.length, 20);
      expect(r.hotspotUsers.map((u) => u['.id']).toSet().length, 20);
    });
  });
}
