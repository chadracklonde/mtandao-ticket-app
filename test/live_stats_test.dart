import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/services/live_stats.dart';

Sale _sale(DateTime t, int price) => Sale(
      time: t,
      user: 'u${t.microsecondsSinceEpoch}',
      price: price,
      address: '10.5.50.9',
      mac: 'AA:BB:CC:00:00:01',
      uptime: '1d',
      profile: '24H',
      comment: 'vc-1',
    );

void main() {
  final now = DateTime(2026, 11, 5, 19, 30);

  test('ne compte que les ventes du jour', () {
    final s = computeLiveStats([
      _sale(DateTime(2026, 11, 5, 0, 1), 500),
      _sale(DateTime(2026, 11, 5, 18, 0), 100),
      _sale(DateTime(2026, 11, 4, 23, 59), 700),
      _sale(DateTime(2026, 11, 6, 0, 0), 900),
    ], 12, now);
    expect(s.salesToday, 2);
    expect(s.amountToday, 600);
    expect(s.connected, 12);
  });

  test('textes de la notification', () {
    final s = computeLiveStats([_sale(DateTime(2026, 11, 5, 9), 500), _sale(DateTime(2026, 11, 5, 10), 500)], 1, now,
        lowStock: const [MapEntry('1H', 4), MapEntry('24H', 0)]);
    expect(liveTitle(s, 'FC'), contains('2 ventes'));
    expect(liveTitle(s, 'FC'), contains('FC'));
    final body = liveBody(s);
    expect(body, contains('1 appareil connecté'));
    expect(body, contains('Stock bas : 1H (4), 24H (0)'));
    expect(body, contains('à 19:30'));
  });

  test('journée vide', () {
    final s = computeLiveStats(const [], 0, now);
    expect(liveTitle(s, 'FC'), "Aucune vente aujourd'hui");
    expect(liveBody(s), startsWith('Aucun appareil connecté'));
  });
}
