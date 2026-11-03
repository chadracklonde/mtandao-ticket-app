import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/routeros/api_client.dart';

void main() {
  group('encodeLength', () {
    test('vecteurs connus du protocole', () {
      expect(encodeLength(0), [0x00]);
      expect(encodeLength(0x7F), [0x7F]);
      expect(encodeLength(0x80), [0x80, 0x80]);
      expect(encodeLength(0x3FFF), [0xBF, 0xFF]);
      expect(encodeLength(0x4000), [0xC0, 0x40, 0x00]);
      expect(encodeLength(0x1FFFFF), [0xDF, 0xFF, 0xFF]);
      expect(encodeLength(0x200000), [0xE0, 0x20, 0x00, 0x00]);
      expect(encodeLength(0x10000000), [0xF0, 0x10, 0x00, 0x00, 0x00]);
    });
  });

  group('lecture', () {
    test('aller-retour de longueurs', () async {
      for (final n in [0, 1, 127, 128, 300, 0x3FFF, 0x4000, 70000, 0x200000]) {
        final q = ByteQueue()..add(encodeLength(n));
        expect(await ApiReader(q).readLength(), n);
      }
    });

    test('phrase !re puis !done', () async {
      final q = ByteQueue()
        ..add(encodeSentence(['!re', '=name=ether1', '=comment=']))
        ..add(encodeSentence(['!done']));
      final r = ApiReader(q);
      final s1 = await r.readSentence();
      expect(s1.first, '!re');
      expect(parseAttributes(s1), {'name': 'ether1', 'comment': ''});
      expect((await r.readSentence()).first, '!done');
    });

    test('lecture en plusieurs morceaux', () async {
      final bytes = encodeSentence(['!re', '=user=é-ticket']);
      final q = ByteQueue();
      final f = ApiReader(q).readSentence();
      for (final b in bytes) {
        q.add(Uint8List.fromList([b]));
      }
      expect(parseAttributes(await f)['user'], 'é-ticket');
    });
  });

  group('ventes', () {
    test('date RouterOS 6', () {
      final s = Sale.tryParse('nov/02/2026-|-14:05:09-|-ab12-|-500-|-10.5.50.20-|-AA:BB:CC:DD:EE:FF-|-24h-|-24H-|-vc-021126-1400');
      expect(s, isNotNull);
      expect(s!.time, DateTime(2026, 11, 2, 14, 5, 9));
      expect(s.user, 'ab12');
      expect(s.price, 500);
      expect(s.profile, '24H');
      expect(s.comment, 'vc-021126-1400');
    });

    test('date RouterOS 7', () {
      final s = Sale.tryParse('2026-11-02-|-08:00:00-|-u-|-1000-|-10.0.0.2-|-AA-|--|-P-|-');
      expect(s, isNotNull);
      expect(s!.time, DateTime(2026, 11, 2, 8));
      expect(s.price, 1000);
    });

    test('nom invalide', () {
      expect(Sale.tryParse('autre script'), isNull);
    });
  });

  group('profil', () {
    test('lecture du prix et de la durée', () {
      final p = HotspotProfile(name: '24H', price: 500, uptime: '1d');
      final back = HotspotProfile.fromRow({
        '.id': '*1',
        'name': '24H',
        'on-login': p.buildOnLogin(),
        'shared-users': '2',
        'rate-limit': '1M/2M',
      });
      expect(back.price, 500);
      expect(back.uptime, '1d');
      expect(back.sharedUsers, 2);
    });
  });
}
