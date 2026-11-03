import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/routeros/api_client.dart';
import 'package:mtandao_ticket/services/mikhmon_service.dart';

import 'support/fake_router.dart';

Future<({FakeRouter router, MikhmonService service})> setUpService() async {
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
  final session = Session(id: 's1', name: 'Test', host: '127.0.0.1', username: 'admin');
  return (router: r, service: MikhmonService(c, session, random: Random(7)));
}

void main() {
  const day = HotspotProfile(name: '24H', price: 500, uptime: '1d');
  const hour = HotspotProfile(name: '1H', price: 100, uptime: '1h');

  group('profils (T2)', () {
    test('création puis relecture du prix et de la durée', () async {
      final t = await setUpService();
      await t.service.saveProfile(day);
      final onLogin = t.router.profiles.single['on-login']!;
      expect(onLogin, startsWith('#mkm:price=500;uptime=1d'));
      final back = await t.service.profiles();
      expect(back.single.name, '24H');
      expect(back.single.price, 500);
      expect(back.single.uptime, '1d');
    });

    test('modification d\'un profil existant', () async {
      final t = await setUpService();
      await t.service.saveProfile(day);
      final saved = (await t.service.profiles()).single;
      await t.service.saveProfile(HotspotProfile(
          id: saved.id, name: '24H', price: 700, uptime: '1d', sharedUsers: 2));
      final back = (await t.service.profiles()).single;
      expect(back.price, 700);
      expect(back.sharedUsers, 2);
      expect(t.router.profiles.length, 1);
    });

    test('noms et durées invalides refusés', () async {
      final t = await setUpService();
      await expectLater(t.service.saveProfile(const HotspotProfile(name: 'a;b')),
          throwsA(isA<RouterOsException>()));
      await expectLater(
          t.service.saveProfile(const HotspotProfile(name: 'ok', uptime: '24 heures')),
          throwsA(isA<RouterOsException>()));
    });

    test('validité calendaire enregistrée et relue (F19)', () async {
      final t = await setUpService();
      await t.service.saveProfile(const HotspotProfile(name: '7J', price: 3000, validity: '7d'));
      final back = (await t.service.profiles()).single;
      expect(back.validity, '7d');
      expect(t.router.profiles.single['on-login'], contains('interval=7d'));
      final v = (await t.service.generate(GenerateRequest(profile: back, count: 1))).single;
      expect(v.validity, '7d');
      await expectLater(
          t.service.saveProfile(const HotspotProfile(name: 'x', validity: '7 jours')),
          throwsA(isA<RouterOsException>()));
    });

    test('suppression', () async {
      final t = await setUpService();
      await t.service.saveProfile(day);
      await t.service.removeProfile((await t.service.profiles()).single.id);
      expect(t.router.profiles, isEmpty);
    });
  });

  group('génération (T3, T4)', () {
    test('100 tickets, tous différents', () async {
      final t = await setUpService();
      await t.service.saveProfile(day);
      final profile = (await t.service.profiles()).single;
      var last = 0;
      final list = await t.service.generate(
        GenerateRequest(profile: profile, count: 100, prefix: 'wz', length: 6),
        onProgress: (done, total) => last = done,
      );
      expect(list.length, 100);
      expect(last, 100);
      expect(list.map((v) => v.name).toSet().length, 100);
      expect(list.every((v) => v.name.startsWith('wz') && v.name.length == 8), isTrue);
      expect(list.every((v) => !v.separate), isTrue);
      expect(t.router.hotspotUsers.length, 100);
      final u = t.router.hotspotUsers.first;
      expect(u['profile'], '24H');
      expect(u['limit-uptime'], '1d');
      expect(u['comment'], matches(RegExp(r'^vc-\d{6}-\d{4}$')));
    });

    test('mode identifiant + mot de passe', () async {
      final t = await setUpService();
      await t.service.saveProfile(hour);
      final profile = (await t.service.profiles()).single;
      final list = await t.service.generate(GenerateRequest(
          profile: profile, count: 20, separate: true, charset: CodeCharset.mixed));
      expect(list.every((v) => v.comment.startsWith('up-')), isTrue);
      expect(list.where((v) => v.separate).length, greaterThan(15));
    });

    test('code déjà pris sur le routeur : un autre code est essayé', () async {
      final t = await setUpService();
      await t.service.saveProfile(hour);
      final profile = (await t.service.profiles()).single;
      for (var d = 0; d < 9; d++) {
        t.router.hotspotUsers.add({'.id': '*X$d', 'name': '$d', 'password': '$d'});
      }
      final list = await t.service.generate(
          GenerateRequest(profile: profile, count: 1, length: 1),
          maxAttempts: 500);
      expect(list.single.name, '9');
    });

    test('plus de code libre : message clair', () async {
      final t = await setUpService();
      await t.service.saveProfile(hour);
      final profile = (await t.service.profiles()).single;
      for (var d = 0; d < 10; d++) {
        t.router.hotspotUsers.add({'.id': '*X$d', 'name': '$d', 'password': '$d'});
      }
      await expectLater(
        t.service.generate(GenerateRequest(profile: profile, count: 1, length: 1),
            maxAttempts: 50),
        throwsA(isA<RouterOsException>()
            .having((e) => e.message, 'message', contains('Augmentez la longueur'))),
      );
    });

    test('coupure au milieu : les tickets déjà créés restent sur le routeur', () async {
      final t = await setUpService();
      await t.service.saveProfile(hour);
      final profile = (await t.service.profiles()).single;
      await expectLater(
        t.service.generate(
          GenerateRequest(profile: profile, count: 20),
          onProgress: (done, total) {
            if (done == 5) t.router.stop();
          },
        ),
        throwsA(isA<GenerationInterrupted>()
            .having((e) => e.created.length, 'créés', greaterThanOrEqualTo(5))
            .having((e) => e.message, 'message', contains('onglet Lots'))),
      );
      expect(t.router.hotspotUsers.length, greaterThanOrEqualTo(5));
      expect(t.router.hotspotUsers.length, lessThan(20));
    });
  });

  group('lots', () {
    test('regroupés par lot et profil, tickets utilisés exclus', () async {
      final t = await setUpService();
      await t.service.saveProfile(day);
      await t.service.saveProfile(hour);
      final profiles = await t.service.profiles();
      final p24 = profiles.firstWhere((p) => p.name == '24H');
      final p1 = profiles.firstWhere((p) => p.name == '1H');
      await t.service.generate(GenerateRequest(profile: p24, count: 5));
      final h = await t.service.generate(GenerateRequest(profile: p1, count: 3));
      t.router.hotspotUsers.add({'.id': '*Z', 'name': 'manuel', 'password': 'x', 'comment': 'créé à la main'});

      var batches = await t.service.unusedBatches();
      expect(batches.length, 2);
      expect(batches.map((b) => b.vouchers.length).toList()..sort(), [3, 5]);
      expect(batches.firstWhere((b) => b.profile == '24H').vouchers.first.price, 500);

      t.router.simulateFirstLogin(h.first.name);
      batches = await t.service.unusedBatches();
      expect(batches.fold<int>(0, (n, b) => n + b.vouchers.length), 7);

      await t.service.removeVouchers(batches.firstWhere((b) => b.profile == '24H').vouchers);
      batches = await t.service.unusedBatches();
      expect(batches.single.profile, '1H');
    });
  });

  group('actifs (T6)', () {
    test('liste puis déconnexion', () async {
      final t = await setUpService();
      await t.service.saveProfile(hour);
      final profile = (await t.service.profiles()).single;
      final v = (await t.service.generate(GenerateRequest(profile: profile, count: 1))).single;
      t.router.simulateFirstLogin(v.name);
      final list = await t.service.activeUsers();
      expect(list.single.user, v.name);
      expect(list.single.address, '10.5.50.20');
      await t.service.disconnect(list.single.id);
      expect(await t.service.activeUsers(), isEmpty);
    });
  });

  group('ventes (T7, T8)', () {
    test('une vente par ticket, même s\'il se reconnecte (simulation du script)', () async {
      final t = await setUpService();
      await t.service.saveProfile(day);
      final profile = (await t.service.profiles()).single;
      final v = (await t.service.generate(GenerateRequest(profile: profile, count: 3)));
      t.router.simulateFirstLogin(v[0].name);
      t.router.simulateFirstLogin(v[0].name, ip: '10.5.50.99');
      t.router.simulateFirstLogin(v[1].name);
      final sales = await t.service.sales();
      expect(sales.length, 2);
      expect(sales.fold<int>(0, (n, s) => n + s.price), 1000);
      expect(sales.first.profile, '24H');
      expect(sales.first.time, DateTime(2026, 11, 3, 8, 30));
    });

    test('ventes triées de la plus récente à la plus ancienne, dates RouterOS 6 et 7', () async {
      final t = await setUpService();
      t.router.scripts.addAll([
        {'.id': '*1', 'comment': 'mikhmon', 'name': 'oct/30/2026-|-10:00:00-|-a-|-500-|-ip-|-mac-|-1d-|-24H-|-vc-300126-0900'},
        {'.id': '*2', 'comment': 'mikhmon', 'name': '2026-11-02-|-09:00:00-|-b-|-100-|-ip-|-mac-|-1h-|-1H-|-vc-021126-0800'},
        {'.id': '*3', 'comment': 'autre', 'name': 'script sans rapport'},
      ]);
      final sales = await t.service.sales();
      expect(sales.map((s) => s.user).toList(), ['b', 'a']);
    });
  });
}
