import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/util.dart';

void main() {
  test('conversion des tailles saisies', () {
    expect(parseDataSize('500M'), 524288000);
    expect(parseDataSize('1g'), 1073741824);
    expect(parseDataSize('1.5G'), 1610612736);
    expect(parseDataSize('100k'), 102400);
    expect(parseDataSize('12'), isNull);
    expect(parseDataSize('0M'), isNull);
    expect(parseDataSize('Go'), isNull);
    expect(parseDataSize(''), isNull);
  });

  test('libellés', () {
    expect(dataLimitLabel(1073741824), '1 Go');
    expect(dataLimitLabel(524288000), '500 Mo');
    expect(dataLimitLabel(1610612736), '1.5 Go');
    expect(dataLimitLabel(102400), '100 Ko');
  });

  test('la limite de données du profil est relue depuis le routeur', () {
    const p = HotspotProfile(name: 'Go', price: 1000, uptime: '1d', dataLimit: '1G');
    final back = HotspotProfile.fromRow({'.id': '*1', 'name': 'Go', 'on-login': p.buildOnLogin()});
    expect(back.dataLimit, '1G');
    expect(back.uptime, '1d');
    expect(back.price, 1000);
  });
}
