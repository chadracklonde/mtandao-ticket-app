import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/routeros/api_client.dart';
import 'package:mtandao_ticket/services/mikhmon_service.dart';
import 'package:mtandao_ticket/services/sales_report.dart';

import 'support/fake_router.dart';

Sale sale(DateTime t, int price) => Sale(
    time: t, user: 'u', price: price, address: '', mac: '', uptime: '', profile: 'p', comment: '');

void main() {
  test('montants par jour et par heure', () {
    final s = SalesSummary.of([
      sale(DateTime(2026, 11, 1, 9), 100),
      sale(DateTime(2026, 11, 3, 14), 500),
      sale(DateTime(2026, 11, 3, 14, 30), 200),
    ], DateTime(2026, 11, 1), DateTime(2026, 11, 4));
    expect(s.perDayTotals(), [100, 0, 700, 0]);
    final h = s.perHourTotals();
    expect(h.length, 24);
    expect(h[14], 700);
    expect(h[9], 100);
  });

  test('variation par rapport à la période précédente', () {
    expect(SalesSummary.changePercent(150, 100), 50);
    expect(SalesSummary.changePercent(50, 100), -50);
    expect(SalesSummary.changePercent(10, 0), isNull);
  });

  test('effacer des ventes du journal du routeur', () async {
    final router = await FakeRouter.start();
    final client = RouterOsClient(
      host: '127.0.0.1', port: router.port, useSsl: false,
      username: 'admin', password: 'secret',
      connectTimeout: const Duration(seconds: 2), commandTimeout: const Duration(seconds: 5),
    );
    addTearDown(() async {
      client.close();
      await router.stop();
    });
    final service = MikhmonService(
        client, Session(id: 's', name: 'T', host: 'h', username: 'u'), random: Random(1));
    router.scripts.addAll([
      {'.id': '*1', 'comment': 'mikhmon', 'name': '2026-11-03-|-10:00:00-|-a-|-500-|-ip-|-mac-|-1d-|-24H-|-vc-1'},
      {'.id': '*2', 'comment': 'mikhmon', 'name': '2026-11-03-|-11:00:00-|-b-|-500-|-ip-|-mac-|-1d-|-24H-|-vc-1'},
      {'.id': '*3', 'comment': 'autre', 'name': 'script sans rapport'},
    ]);
    final sales = await service.sales();
    expect(sales.length, 2);
    expect(sales.every((x) => x.id.isNotEmpty), isTrue);
    expect(await service.deleteSales([sales.first]), 1);
    expect((await service.sales()).length, 1);
    expect(router.scripts.any((x) => x['comment'] == 'autre'), isTrue);
    expect(await service.deleteSales(await service.sales()), 1);
    expect(await service.sales(), isEmpty);
  });
}
