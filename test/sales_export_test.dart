import 'dart:convert';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/services/sales_export.dart';
import 'package:mtandao_ticket/services/sales_report.dart';

Sale sale(DateTime t, String user, int price, String profile) => Sale(
      time: t,
      user: user,
      price: price,
      address: '10.5.50.2',
      mac: 'AA:BB',
      uptime: '1d',
      profile: profile,
      comment: 'vc-1',
    );

void main() {
  final session = Session(id: 's', name: 'Wifi zone', host: 'h', username: 'u');
  final sales = [
    sale(DateTime(2026, 11, 2, 9), 'a1', 500, '24H'),
    sale(DateTime(2026, 11, 3, 10), 'b2', 100, '1H'),
    sale(DateTime(2026, 11, 3, 11), 'c3', 500, '24H'),
  ];
  final summary = SalesSummary.of(sales, DateTime(2026, 11, 1), DateTime(2026, 11, 30));

  test('PDF du rapport : valide, même vide', () async {
    final pdf = await buildSalesPdf(summary, session, 'novembre 2026');
    expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');
    expect(pdf.length, greaterThan(1500));
    final empty = SalesSummary.of(const [], DateTime(2026, 11, 1), DateTime(2026, 11, 1));
    expect((await buildSalesPdf(empty, session, 'jour')).length, greaterThan(500));
  });

  test('Excel du rapport : fichier xlsx avec les ventes', () {
    final bytes = buildSalesXlsx(summary, session, 'novembre 2026');
    expect(bytes.sublist(0, 2), [0x50, 0x4B]); // en-tête zip
    final back = Excel.decodeBytes(bytes);
    expect(back.tables.keys, containsAll(['Résumé', 'Ventes']));
    final rows = back.tables['Ventes']!.rows;
    expect(rows.length, 4); // en-tête + 3 ventes
    expect(rows[1][2]?.value.toString(), 'c3'); // la plus récente d'abord
    expect(rows.skip(1).fold<int>(0, (n, r) => n + int.parse(r[5]!.value.toString())), 1100);
  });

  test('nom de fichier sûr', () {
    expect(salesFileName(session, 'Du 01/11/2026 au 30/11/2026'), 'ventes-Wifi-zone-Du-01-11-2026-au-30-11-2026');
  });
}
