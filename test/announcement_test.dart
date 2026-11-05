import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/routeros/api_client.dart';
import 'package:mtandao_ticket/screens/announcement_screen.dart';
import 'package:mtandao_ticket/services/announcement.dart';
import 'package:mtandao_ticket/services/mikhmon_service.dart';

import 'support/fake_router.dart';

const _login = '<html>\r\n<head><title>Wifi</title></head>\r\n<body class="x" onload="go()">\r\n<form>…</form>\r\n</body></html>';

void main() {
  group('page et script d\'annonce', () {
    test('insertion après <body>, une seule fois, et retrait exact', () {
      final once = insertAnnounceLoader(_login)!;
      expect(once, contains(announceLoader));
      expect(once.indexOf(announceLoader), greaterThan(once.indexOf('<body class="x" onload="go()">')));
      expect(insertAnnounceLoader(once), once);
      expect(removeAnnounceLoader(once).replaceAll('\n\n', '\n'), isNot(contains('mkm-annonce')));
      expect(removeAnnounceLoader(once).contains('<form>'), isTrue);
      expect(insertAnnounceLoader('pas de page'), isNull);
    });

    test('script : texte protégé, relu par l\'application', () {
      const a = Announcement(
        text: 'Coupure à 14h </script><b>"test"</b>',
        kind: AnnounceKind.warning,
      );
      final js = buildAnnounceScript(a);
      expect(js, isNot(contains('</script>')));
      expect(js, contains('textContent'));
      final back = parseAnnounceScript(js)!;
      expect(back.text, a.text);
      expect(back.kind, AnnounceKind.warning);
      expect(back.expires, isNull);
    });

    test('expiration et annonce vide', () {
      final exp = DateTime(2026, 11, 6);
      final js = buildAnnounceScript(Announcement(text: 'Promo', kind: AnnounceKind.promo, expires: exp));
      expect(js, contains('var exp=${exp.millisecondsSinceEpoch};'));
      expect(parseAnnounceScript(js)!.expires, exp);
      expect(parseAnnounceScript(js)!.expiredAt(DateTime(2026, 11, 7)), isTrue);
      final empty = buildAnnounceScript(const Announcement(text: '  ', kind: AnnounceKind.info));
      expect(empty.contains('createElement'), isFalse);
      expect(parseAnnounceScript(empty)!.isEmpty, isTrue);
      expect(parseAnnounceScript('autre script'), isNull);
    });

    test('durées', () {
      final now = DateTime(2026, 11, 5, 22, 30);
      expect(AnnounceDuration.tonight.from(now), DateTime(2026, 11, 6));
      expect(AnnounceDuration.day.from(now), DateTime(2026, 11, 6, 22, 30));
      expect(AnnounceDuration.none.from(now), isNull);
    });
  });

  group('routeur simulé', () {
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
      router.tables['/file']!.add({'.id': '*F1', 'name': 'hotspot/login.html', 'contents': _login});
    });

    tearDown(() async {
      client.close();
      await router.stop();
    });

    Map<String, String> file(String name) =>
        router.tables['/file']!.firstWhere((f) => f['name'] == name, orElse: () => {});

    test('préparer, publier, retirer, tout remettre', () async {
      var st = await service.announcementState();
      expect(st.loginFound, isTrue);
      expect(st.installed, isFalse);

      await service.setAnnouncement(const Announcement(text: 'Promo ce soir', kind: AnnounceKind.promo));
      st = await service.announcementState();
      expect(st.installed, isTrue);
      expect(st.current!.text, 'Promo ce soir');
      expect(file('hotspot/login.html')['contents'], contains(announceStart));
      expect(file('hotspot/login.html.avant-annonce')['contents'], _login);

      await service.setAnnouncement(const Announcement(text: 'Autre texte', kind: AnnounceKind.info));
      expect((await service.announcementState()).current!.text, 'Autre texte');
      expect(router.tables['/file']!.where((f) => f['name'] == 'hotspot/annonce.js').length, 1);

      await service.setAnnouncement(const Announcement(text: '', kind: AnnounceKind.info));
      expect((await service.announcementState()).current!.isEmpty, isTrue);

      await service.uninstallAnnouncement();
      st = await service.announcementState();
      expect(st.installed, isFalse);
      expect(file('hotspot/annonce.js'), isEmpty);
      expect(file('hotspot/login.html')['contents']!.contains('mkm-annonce'), isFalse);
      expect(file('hotspot/login.html')['contents']!.contains('<form>'), isTrue);
    });

    test('dossier du profil, page absente, page illisible, texte trop long', () async {
      router.hotspots.add({'.id': '*H', 'name': 'h', 'profile': 'p1'});
      router.tables['/ip/hotspot/profile']!.add({'.id': '*HP', 'name': 'p1', 'html-directory': 'flash/hotspot'});
      expect(await service.hotspotHtmlDir(), 'flash/hotspot');
      expect((await service.announcementState()).loginFound, isFalse);
      router.tables['/file']!.add({'.id': '*F2', 'name': 'flash/hotspot/login.html'});
      final st = await service.announcementState();
      expect(st.loginFound, isTrue);
      expect(st.readable, isFalse);
      await expectLater(service.installAnnouncement(), throwsA(isA<RouterOsException>()));
      await expectLater(
        service.setAnnouncement(Announcement(text: 'x' * 200, kind: AnnounceKind.info)),
        throwsA(isA<RouterOsException>()),
      );
    });

    testWidgets('écran : préparer puis publier', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Future<void> wait([int n = 20]) async {
        for (var i = 0; i < n; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
          await tester.pump(const Duration(milliseconds: 40));
        }
      }

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AnnouncementScreen(service: service))));
      await wait();
      expect(find.text('Première utilisation'), findsOneWidget);
      await tester.tap(find.text('Préparer la page de connexion'));
      await wait(5);
      await tester.tap(find.text('Préparer'));
      await wait();
      expect(find.text('Publier l\'annonce'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Coupure à 14 h');
      await wait(3);
      await tester.tap(find.text('Publier l\'annonce'));
      await wait();
      expect(find.text('En ligne actuellement'), findsOneWidget);
      expect(file('hotspot/annonce.js')['contents'], contains('Coupure à 14 h'));
    });
  });
}
