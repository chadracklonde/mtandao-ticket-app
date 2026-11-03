import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/services/sales_report.dart';

Sale sale(DateTime t, int price, {String profile = '24H', String user = 'u'}) => Sale(
      time: t,
      user: user,
      price: price,
      address: '10.0.0.2',
      mac: 'AA',
      uptime: '1d',
      profile: profile,
      comment: 'vc-x',
    );

void main() {
  final all = [
    sale(DateTime(2026, 10, 31, 23, 59, 59), 500), // veille du mois
    sale(DateTime(2026, 11, 1, 0, 0, 0), 500),
    sale(DateTime(2026, 11, 2, 9, 0), 100, profile: '1H'),
    sale(DateTime(2026, 11, 2, 14, 5), 500),
    sale(DateTime(2026, 11, 3, 8, 30), 3000, profile: '7J'),
    sale(DateTime(2026, 11, 30, 23, 59, 59), 500), // dernier jour du mois
    sale(DateTime(2026, 12, 1, 0, 0, 0), 500), // mois suivant
  ];

  test('rapport du jour', () {
    final d = DateTime(2026, 11, 2);
    final r = SalesSummary.of(all, d, d);
    expect(r.count, 2);
    expect(r.total, 600);
    expect(r.sales.first.time, DateTime(2026, 11, 2, 14, 5)); // le plus récent d'abord
    expect(r.days.single.day, d);
  });

  test('rapport du mois : bornes incluses, mois voisins exclus', () {
    final (a, b) = SalesSummary.monthRange(DateTime(2026, 11, 15));
    expect(a, DateTime(2026, 11, 1));
    expect(b, DateTime(2026, 11, 30));
    final r = SalesSummary.of(all, a, b);
    expect(r.count, 5);
    expect(r.total, 500 + 100 + 500 + 3000 + 500);
    expect(r.days.map((d) => d.day.day).toList(), [30, 3, 2, 1]);
  });

  test('rapport d\'une période choisie', () {
    final r = SalesSummary.of(all, DateTime(2026, 11, 2), DateTime(2026, 11, 3));
    expect(r.count, 3);
    expect(r.total, 3600);
  });

  test('dates inversées : la période est remise dans l\'ordre', () {
    final r = SalesSummary.of(all, DateTime(2026, 11, 3), DateTime(2026, 11, 2));
    expect(r.count, 3);
    expect(r.start, DateTime(2026, 11, 2));
    expect(r.end, DateTime(2026, 11, 3));
  });

  test('totaux par profil, du plus rentable au moins rentable', () {
    final r = SalesSummary.of(all, DateTime(2026, 11, 1), DateTime(2026, 11, 30));
    expect(r.byProfile.map((p) => p.profile).toList(), ['7J', '24H', '1H']);
    expect(r.byProfile.firstWhere((p) => p.profile == '24H').count, 3);
    expect(r.byProfile.fold<int>(0, (n, p) => n + p.total), r.total);
  });

  test('période sans vente', () {
    final r = SalesSummary.of(all, DateTime(2026, 1, 1), DateTime(2026, 1, 31));
    expect(r.count, 0);
    expect(r.total, 0);
    expect(r.days, isEmpty);
  });

  test('mois de février d\'une année bissextile', () {
    final (a, b) = SalesSummary.monthRange(DateTime(2028, 2, 10));
    expect(b, DateTime(2028, 2, 29));
    expect(a, DateTime(2028, 2, 1));
  });
}
