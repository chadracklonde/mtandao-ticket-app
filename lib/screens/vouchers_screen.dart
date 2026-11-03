import 'package:flutter/material.dart';

import '../models.dart';
import '../services/mikhmon_service.dart';
import '../widgets/async_body.dart';
import 'voucher_list_screen.dart';

/// Lots de tickets non utilisés : permet de réimprimer ou supprimer un lot.
class VouchersScreen extends StatefulWidget {
  const VouchersScreen({super.key, required this.service, required this.session});

  final MikhmonService service;
  final Session session;

  @override
  State<VouchersScreen> createState() => _VouchersScreenState();
}

class _VouchersScreenState extends State<VouchersScreen> {
  // Change la clé pour forcer un rechargement après suppression d'un lot.
  int _generation = 0;

  @override
  Widget build(BuildContext context) {
    return AsyncBody<List<VoucherBatch>>(
      key: ValueKey(_generation),
      load: widget.service.unusedBatches,
      builder: (context, batches, reload) {
        if (batches.isEmpty) {
          return const EmptyList('Aucun ticket non utilisé.');
        }
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: batches.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final b = batches[i];
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
              title: Text('Lot du ${b.label}'),
              subtitle: Text('${b.vouchers.length} tickets · profil ${b.profile}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final deleted = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => VoucherListScreen(
                      title: 'Lot du ${b.label}',
                      vouchers: b.vouchers,
                      session: widget.session,
                      onDelete: () => widget.service.removeVouchers(b.vouchers),
                    ),
                  ),
                );
                if (deleted == true && mounted) setState(() => _generation++);
              },
            );
          },
        );
      },
    );
  }
}
