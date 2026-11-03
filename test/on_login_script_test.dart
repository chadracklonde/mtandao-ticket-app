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
  const expiring = HotspotProfile(name: '7J', price: 3000, uptime: '7d');

  group('script on-login', () {
    test('forme correcte et lecture de la limite sur le ticket', () {
      final s = simple.buildOnLogin();
      expect(checkBalanced(s), isNull);
      expect(s, startsWith('#mkm:price=500;uptime=1d\n'));
      expect(s, contains(r':local lu [/ip hotspot user get [find where name=$user] limit-uptime]'));
    });

    test('expiration programmée à partir de la limite du ticket', () {
      final s = expiring.buildOnLogin();
      expect(checkBalanced(s), isNull);
      expect(s, contains(r'/system scheduler add name=("mkm-e-" . $user) interval=$lu'));
      expect(s, contains(r'start-date=$d start-time=$st'));
      // Pas d'expiration si le ticket est illimité.
      expect(s, contains(r':if ([:len $lu] > 0 and $lu > 00:00:00) do={'));
      // Le planificateur est créé après l'enregistrement de la vente.
      expect(s.indexOf('comment=mikhmon\n'), lessThan(s.indexOf('scheduler add')));
      expect(s.indexOf('"used-"'), lessThan(s.indexOf('scheduler add')));
    });

    test('la vente garde le format date-|-heure-|-ticket-|-prix-|-ip-|-mac-|-durée-|-profil-|-lot', () {
      final s = simple.buildOnLogin();
      expect(
        s,
        contains(r'"-|-500-|-" . $a . "-|-" . $m . "-|-" . [:tostr $lu] . "-|-24H-|-" . $c'),
      );
    });

    test('le détecteur repère un script cassé', () {
      expect(checkBalanced('/system script add name=("a" . [x]'), isNotNull);
      expect(checkBalanced(':local a "ouvert'), isNotNull);
      expect(checkBalanced(':if (1) do={ }}'), isNotNull);
    });

    test('prix et limite par défaut relus depuis le routeur', () {
      final back = HotspotProfile.fromRow({
        '.id': '*1',
        'name': '7J',
        'on-login': expiring.buildOnLogin(),
      });
      expect(back.price, 3000);
      expect(back.uptime, '7d');
    });

    test('profils créés par une version précédente (sans validité)', () {
      final back = HotspotProfile.fromRow({
        '.id': '*2',
        'name': 'vieux',
        'on-login': '#mkm:price=500;uptime=1d\n:local d [/system clock get date]\n',
      });
      expect(back.price, 500);
      expect(back.uptime, '1d');
    });
  });
}
