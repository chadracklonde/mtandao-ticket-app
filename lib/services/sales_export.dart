import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models.dart';
import '../util.dart';
import 'sales_report.dart';

/// Montant sans espace insécable (les polices de base du PDF ne l'affichent pas).
String _money(int v, String currency) =>
    formatMoney(v, currency).replaceAll(RegExp(r'\s'), ' ');

/// Nom de fichier sûr, sans extension : `ventes-<routeur>-<période>`.
String salesFileName(Session session, String periodTitle) {
  String clean(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return 'ventes-${clean(session.name)}-${clean(periodTitle)}';
}

/// Rapport de ventes en PDF A4 : résumé, totaux par profil, totaux par jour
/// puis liste détaillée.
Future<Uint8List> buildSalesPdf(SalesSummary s, Session session, String periodTitle) {
  final c = session.currency;
  final doc = pw.Document(title: 'Ventes ${session.name} - $periodTitle');

  pw.Widget heading(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 4),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget table(List<String> head, List<List<String>> rows, {Set<int> right = const {}}) =>
      pw.TableHelper.fromTextArray(
        headers: head,
        data: rows,
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
        cellAlignments: {
          for (final i in right) i: pw.Alignment.centerRight,
        },
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Text('Rapport de ventes',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text('${session.name} - $periodTitle', style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 10),
        pw.Row(children: [
          pw.Expanded(
            child: pw.Text('Encaissé : ${_money(s.total, c)}',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text('Tickets vendus : ${s.count}', style: const pw.TextStyle(fontSize: 11)),
        ]),
        if (s.count == 0)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 16),
            child: pw.Text('Aucune vente sur cette période.'),
          )
        else ...[
          if (s.byProfile.isNotEmpty) ...[
            heading('Par profil'),
            table(
              ['Profil', 'Tickets', 'Montant'],
              [for (final p in s.byProfile) [p.profile, '${p.count}', _money(p.total, c)]],
              right: {1, 2},
            ),
          ],
          if (s.days.length > 1) ...[
            heading('Par jour'),
            table(
              ['Jour', 'Tickets', 'Montant'],
              [
                for (final d in s.days)
                  [formatDate(d.day), '${d.sales.length}', _money(d.total, c)]
              ],
              right: {1, 2},
            ),
          ],
          heading('Détail des ventes'),
          table(
            ['Date', 'Heure', 'Ticket', 'Profil', 'Durée', 'Montant'],
            [
              for (final v in s.sales)
                [
                  formatDate(v.time),
                  formatTime(v.time),
                  v.user,
                  v.profile,
                  v.uptime,
                  _money(v.price, c),
                ]
            ],
            right: {5},
          ),
        ],
      ],
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ),
    ),
  );
  return doc.save();
}

/// Rapport de ventes au format Excel (.xlsx) : une feuille Résumé et une
/// feuille Ventes (une ligne par ticket vendu, montants numériques).
Uint8List buildSalesXlsx(SalesSummary s, Session session, String periodTitle) {
  final c = session.currency;
  final book = Excel.createExcel();
  final defaultSheet = book.getDefaultSheet();
  if (defaultSheet != null) book.rename(defaultSheet, 'Résumé');
  final summary = book['Résumé'];
  final sales = book['Ventes'];

  TextCellValue t(String v) => TextCellValue(v);

  summary.appendRow([t('Rapport de ventes')]);
  summary.appendRow([t('Routeur'), t(session.name)]);
  summary.appendRow([t('Période'), t(periodTitle)]);
  summary.appendRow([t('Encaissé ($c)'), IntCellValue(s.total)]);
  summary.appendRow([t('Tickets vendus'), IntCellValue(s.count)]);
  summary.appendRow([]);
  summary.appendRow([t('Profil'), t('Tickets'), t('Montant ($c)')]);
  for (final p in s.byProfile) {
    summary.appendRow([t(p.profile), IntCellValue(p.count), IntCellValue(p.total)]);
  }
  summary.appendRow([]);
  summary.appendRow([t('Jour'), t('Tickets'), t('Montant ($c)')]);
  for (final d in s.days) {
    summary.appendRow([t(formatDate(d.day)), IntCellValue(d.sales.length), IntCellValue(d.total)]);
  }

  sales.appendRow([
    t('Date'),
    t('Heure'),
    t('Ticket'),
    t('Profil'),
    t('Durée'),
    t('Montant ($c)'),
    t('Adresse IP'),
    t('Adresse MAC'),
    t('Lot'),
  ]);
  for (final v in s.sales) {
    sales.appendRow([
      t(formatDate(v.time)),
      t(formatTime(v.time)),
      t(v.user),
      t(v.profile),
      t(v.uptime),
      IntCellValue(v.price),
      t(v.address),
      t(v.mac),
      t(v.comment),
    ]);
  }

  book.setDefaultSheet('Résumé');
  final bytes = book.save();
  if (bytes == null) throw StateError('Export Excel impossible.');
  return Uint8List.fromList(bytes);
}
