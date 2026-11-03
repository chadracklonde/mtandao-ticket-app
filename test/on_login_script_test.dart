import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';

/// Contrôle de forme du script RouterOS : guillemets fermés, crochets,
/// parenthèses et accolades équilibrés. Ce n'est PAS une exécution : seul un
/// vrai routeur valide le script.
String? checkBalanced(String script) {
  final stack = <String>[];
  const pairs = {')': '(', ']': '[', '}': '{'};
  var inString = false;
  for (var i = 0; i < script.length; i++) {
    final ch = script[i];
    if (inString) {
      if (ch == r'\') {
        i++; // caractère échappé
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if ('([{'.contains(ch)) {
      stack.add(ch);
    } else if (pairs.containsKey(ch)) {
      if (stack.isEmpty || stack.removeLast() != pairs[ch]) {
        return 'fermeture inattendue "$ch" à la position $i';
      }
    }
  }
  if (inString) return 'guillemet non fermé';
  if (stack.isNotEmpty) return 'symboles non fermés : ${stack.join()}';
  return null;
}

void main() {
  const simple = HotspotProfile(name: '24H', price: 500, uptime: '1d');
  const expiring = HotspotProfile(name: '7J', price: 3000, uptime: '', validity: '7d');

  group('script on-login', () {
    test('forme correcte sans expiration', () {
      final s = simple.buildOnLogin();
      expect(checkBalanced(s), isNull);
      expect(s, startsWith('#mkm:price=500;uptime=1d;validity=\n'));
      expect(s, isNot(contains('scheduler')));
    });

    test('forme correcte avec expiration', () {
      final s = expiring.buildOnLogin();
      expect(checkBalanced(s), isNull);
      expect(s, startsWith('#mkm:price=3000;uptime=;validity=7d\n'));
      expect(s, contains('/system scheduler add name=("mkm-e-" . \$user) interval=7d'));
      expect(s, contains('start-date=\$d start-time=\$st'));
      // Le planificateur est créé après l'enregistrement de la vente.
      expect(s.indexOf('comment=mikhmon\n'), lessThan(s.indexOf('scheduler add')));
      expect(s.indexOf('"used-"'), lessThan(s.indexOf('scheduler add')));
    });

    test('la vente garde le format date-|-heure-|-ticket-|-prix-|-ip-|-mac-|-durée-|-profil-|-lot', () {
      final s = simple.buildOnLogin();
      expect(
        s,
        contains(r'"-|-500-|-" . $a . "-|-" . $m . "-|-1d-|-24H-|-" . $c'),
      );
    });

    test('le détecteur repère un script cassé', () {
      expect(checkBalanced('/system script add name=("a" . [x]'), isNotNull);
      expect(checkBalanced(':local a "ouvert'), isNotNull);
      expect(checkBalanced(':if (1) do={ }}'), isNotNull);
    });

    test('prix, durée et validité relus depuis le routeur', () {
      final back = HotspotProfile.fromRow({
        '.id': '*1',
        'name': '7J',
        'on-login': expiring.buildOnLogin(),
      });
      expect(back.price, 3000);
      expect(back.uptime, '');
      expect(back.validity, '7d');
    });

    test('profils créés par une version précédente (sans validité)', () {
      final back = HotspotProfile.fromRow({
        '.id': '*2',
        'name': 'vieux',
        'on-login': '#mkm:price=500;uptime=1d\n:local d [/system clock get date]\n',
      });
      expect(back.price, 500);
      expect(back.uptime, '1d');
      expect(back.validity, '');
    });
  });
}
