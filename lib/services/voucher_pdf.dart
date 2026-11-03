import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models.dart';
import '../util.dart';

/// Génère un PDF A4 de tickets (3 colonnes) avec QR code de connexion.
Future<Uint8List> buildVouchersPdf(List<Voucher> vouchers, Session session) {
  final doc = pw.Document(title: 'Tickets ${session.name}');
  final dns = session.dnsName.trim();

  pw.Widget label(String text) =>
      pw.Text(text, style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700));

  pw.Widget value(String text, {double size = 10}) => pw.Text(
        text,
        style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold),
      );

  pw.Widget ticket(Voucher v) {
    final qrData = dns.isEmpty
        ? v.name
        : 'http://$dns/login?username=${Uri.encodeQueryComponent(v.name)}'
            '&password=${Uri.encodeQueryComponent(v.password)}';
    final info = [
      v.profile,
      if (v.uptime.isNotEmpty) v.uptime,
      if (v.price > 0) formatMoney(v.price, session.currency),
    ].join(' · ');

    return pw.Container(
      width: 174,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.6),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(session.name,
              style: const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (v.separate) ...[
                      label('Utilisateur'),
                      value(v.name),
                      pw.SizedBox(height: 2),
                      label('Mot de passe'),
                      value(v.password),
                    ] else ...[
                      label('Code'),
                      value(v.name, size: 14),
                    ],
                    pw.SizedBox(height: 4),
                    pw.Text(info, style: const pw.TextStyle(fontSize: 7)),
                  ],
                ),
              ),
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: qrData,
                width: 52,
                height: 52,
                drawText: false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20),
      build: (context) => [
        pw.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: vouchers.map(ticket).toList(),
        ),
      ],
    ),
  );
  return doc.save();
}
