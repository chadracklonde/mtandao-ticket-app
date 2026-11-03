import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models.dart';
import '../util.dart';
import 'ticket_layout.dart';

/// Génère le PDF des tickets : feuille A4 (2 à 4 colonnes) ou rouleau
/// 58/80 mm (un ticket par page), avec QR code de connexion facultatif.
Future<Uint8List> buildVouchersPdf(
  List<Voucher> vouchers,
  Session session, {
  TicketLayout layout = const TicketLayout(),
  Uint8List? logo,
}) {
  final doc = pw.Document(title: 'Tickets ${session.name}');
  final dns = session.dnsName.trim();
  final logoImage = (layout.showLogo && logo != null) ? pw.MemoryImage(logo) : null;
  final title = layout.header.trim().isEmpty ? session.name : layout.header.trim();
  final footer = layout.footer.trim();

  pw.Widget label(String text, double s) =>
      pw.Text(text, style: pw.TextStyle(fontSize: 6.5 * s, color: PdfColors.grey700));

  pw.Widget value(String text, double size) => pw.Text(
        text,
        style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold),
      );

  pw.Widget ticket(Voucher v, double width, {bool roll = false}) {
    // Ticket étroit (4 colonnes, rouleau 58 mm) : le QR passe sous le code.
    final narrow = width < 165;
    final s = roll ? 1.15 : 1.0;
    final qrData = dns.isEmpty
        ? v.name
        : 'http://$dns/login?username=${Uri.encodeQueryComponent(v.name)}'
            '&password=${Uri.encodeQueryComponent(v.password)}';
    final info = [
      v.profile,
      if (v.uptime.isNotEmpty) 'valable ${v.uptime}',
      if (v.dataLimit.isNotEmpty) v.dataLimit,
      if (v.price > 0) formatMoney(v.price, session.currency),
    ].join(' · ');

    final credentials = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (v.separate) ...[
          label('Utilisateur', s),
          value(v.name, 10 * s),
          pw.SizedBox(height: 2),
          label('Mot de passe', s),
          value(v.password, 10 * s),
        ] else ...[
          label('Code', s),
          value(v.name, (narrow ? 12 : 14) * s),
        ],
        pw.SizedBox(height: 4),
        pw.Text(info, style: pw.TextStyle(fontSize: 7 * s)),
      ],
    );

    final qr = layout.showQr
        ? pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: qrData,
            width: roll ? 70 : 52,
            height: roll ? 70 : 52,
            drawText: false,
          )
        : null;

    return pw.Container(
      width: width,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.6),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              if (logoImage != null) ...[
                pw.Image(logoImage, width: 16 * s, height: 16 * s),
                pw.SizedBox(width: 4),
              ],
              pw.Expanded(
                child: pw.Text(title,
                    maxLines: 1,
                    style: pw.TextStyle(fontSize: 9 * s, fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          if (qr == null)
            credentials
          else if (narrow)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [credentials, pw.SizedBox(height: 4), qr],
            )
          else
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [pw.Expanded(child: credentials), qr],
            ),
          if (footer.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(footer, style: pw.TextStyle(fontSize: 6.5 * s, color: PdfColors.grey800)),
          ],
        ],
      ),
    );
  }

  if (layout.paper == TicketPaper.a4) {
    const margin = 20.0;
    const spacing = 8.0;
    final usable = PdfPageFormat.a4.width - 2 * margin;
    final width = (usable - spacing * (layout.columns - 1)) / layout.columns - 0.5;
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(margin),
        build: (context) => [
          pw.Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: vouchers.map((v) => ticket(v, width)).toList(),
          ),
        ],
      ),
    );
  } else {
    final fmt = layout.paper == TicketPaper.roll58 ? PdfPageFormat.roll57 : PdfPageFormat.roll80;
    for (final v in vouchers) {
      doc.addPage(
        pw.Page(
          pageFormat: fmt,
          build: (context) => ticket(v, fmt.availableWidth, roll: true),
        ),
      );
    }
  }
  return doc.save();
}
