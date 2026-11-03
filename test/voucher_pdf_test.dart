import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/services/voucher_pdf.dart';

void main() {
  final session = Session(
      id: 's', name: 'Wifi zone', host: '192.168.88.1', username: 'admin', dnsName: 'wifi.local');

  List<Voucher> make(int n, {bool separate = false}) => [
        for (var i = 0; i < n; i++)
          Voucher(
            name: 'K${i.toString().padLeft(5, '0')}',
            password: separate ? 'P$i' : 'K${i.toString().padLeft(5, '0')}',
            profile: '24H',
            price: 500,
            uptime: '1d',
          ),
      ];

  test('PDF de 100 tickets (code unique)', () async {
    final bytes = await buildVouchersPdf(make(100), session);
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(5000));
  });

  test('PDF avec utilisateur et mot de passe, sans page de connexion', () async {
    final s = Session(id: 's', name: 'Wifi', host: 'h', username: 'u');
    final bytes = await buildVouchersPdf(make(10, separate: true), s);
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });
}
