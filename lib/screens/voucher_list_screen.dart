import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../models.dart';
import '../services/file_delivery.dart';
import '../services/voucher_pdf.dart';
import '../util.dart';

/// Liste des tickets d'un lot, avec export / impression PDF.
class VoucherListScreen extends StatelessWidget {
  const VoucherListScreen({
    super.key,
    required this.title,
    required this.vouchers,
    required this.session,
    this.onDelete,
  });

  final String title;
  final List<Voucher> vouchers;
  final Session session;

  /// Si fourni, affiche un bouton « supprimer le lot ».
  final Future<void> Function()? onDelete;

  Future<void> _share(BuildContext context) async {
    try {
      final bytes = await buildVouchersPdf(vouchers, session);
      final clean = session.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
      final path = await deliverFile(bytes, 'tickets-$clean.pdf', mimeType: 'application/pdf');
      if (path != null && context.mounted) showMessage(context, 'Enregistré : $path');
    } catch (e) {
      if (context.mounted) showMessage(context, describeError(e));
    }
  }

  Future<void> _print(BuildContext context) async {
    try {
      final bytes = await buildVouchersPdf(vouchers, session);
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'Tickets ${session.name}');
    } catch (e) {
      if (context.mounted) showMessage(context, describeError(e));
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce lot ?'),
        content: Text('${vouchers.length} tickets non utilisés seront supprimés du routeur.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await onDelete!();
      if (context.mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (context.mounted) showMessage(context, describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Partager le PDF',
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () => _share(context),
          ),
          IconButton(
            tooltip: 'Imprimer',
            icon: const Icon(Icons.print),
            onPressed: () => _print(context),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Supprimer le lot',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context),
            ),
        ],
      ),
      body: ListView.separated(
        itemCount: vouchers.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final v = vouchers[i];
          return ListTile(
            title: Text(
              v.separate ? '${v.name}  /  ${v.password}' : v.name,
              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
            ),
            subtitle: Text([
              v.profile,
              if (v.uptime.isNotEmpty) v.uptime,
              if (v.dataLimit.isNotEmpty) v.dataLimit,
              if (v.price > 0) formatMoney(v.price, session.currency),
            ].join(' · ')),
            onTap: () {
              Clipboard.setData(ClipboardData(text: v.name));
              showMessage(context, 'Code copié');
            },
          );
        },
      ),
    );
  }
}
