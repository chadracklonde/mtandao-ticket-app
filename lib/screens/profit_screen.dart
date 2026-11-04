import 'package:flutter/material.dart';

import '../models.dart';
import '../services/insights.dart';
import '../services/mikhmon_service.dart';
import '../util.dart';
import '../widgets/async_body.dart';
import '../widgets/desktop.dart';

class _ProfitData {
  _ProfitData(this.sales, this.costs);
  final List<Sale> sales;
  final List<CostItem> costs;
}

/// Bénéfice net du mois : encaissé − coûts mensuels − coûts par ticket.
class ProfitScreen extends StatefulWidget {
  const ProfitScreen({super.key, required this.service, required this.session});

  final MikhmonService service;
  final Session session;

  @override
  State<ProfitScreen> createState() => _ProfitScreenState();
}

class _ProfitScreenState extends State<ProfitScreen> {
  late final CostStore _store = CostStore(widget.session.id);
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  static const _monthNames = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];

  Future<_ProfitData> _load() async => _ProfitData(await widget.service.sales(), await _store.load());

  Future<void> _addCost(List<CostItem> costs, Future<void> Function() reload) async {
    final label = TextEditingController();
    final amount = TextEditingController();
    final key = GlobalKey<FormState>();
    var perTicket = false;
    final item = await showDialog<CostItem>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Ajouter un coût'),
          content: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: label,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nom (Starlink, électricité…)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Champ obligatoire' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Montant (${widget.session.currency})',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    return (n == null || n <= 0) ? 'Entrez un montant' : null;
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Par ticket vendu'),
                  subtitle: const Text('Sinon : par mois'),
                  value: perTicket,
                  onChanged: (v) => setLocal(() => perTicket = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                if (key.currentState!.validate()) {
                  Navigator.pop(
                    ctx,
                    CostItem(
                      label: label.text.trim(),
                      amount: int.parse(amount.text.trim()),
                      perTicket: perTicket,
                    ),
                  );
                }
              },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    amount.dispose();
    if (item == null) return;
    await _store.save([...costs, item]);
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.session.currency;
    final t = Theme.of(context).textTheme;
    return AsyncBody<_ProfitData>(
      load: _load,
      builder: (context, data, reload) {
        final r = NetProfit.forMonth(data.sales, _month, data.costs);
        final positive = r.net >= 0;
        final now = DateTime.now();
        final isCurrent = _month.year == now.year && _month.month == now.month;
        return ContentWidth(
          maxWidth: 820,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'Mois précédent',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                  ),
                  Text('${_monthNames[_month.month - 1]} ${_month.year}', style: t.titleMedium),
                  IconButton(
                    tooltip: 'Mois suivant',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: isCurrent
                        ? null
                        : () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                  ),
                ],
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Bénéfice net', style: t.bodySmall),
                      Text(
                        formatMoney(r.net, currency),
                        style: t.headlineMedium?.copyWith(
                          color: positive ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                      if (r.margin != null)
                        Text('${r.margin!.toStringAsFixed(0)} % de l\'encaissé', style: t.bodySmall),
                      const Divider(height: 24),
                      _line('Encaissé (${r.tickets} ticket(s))', formatMoney(r.revenue, currency)),
                      _line('Coûts mensuels', '- ${formatMoney(r.monthlyCosts, currency)}'),
                      _line('Coûts par ticket', '- ${formatMoney(r.perTicketCosts, currency)}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Text('Mes coûts', style: t.titleMedium)),
                  TextButton.icon(
                    onPressed: () => _addCost(data.costs, reload),
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter'),
                  ),
                ],
              ),
              if (data.costs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Ajoutez vos dépenses (abonnement Starlink, électricité, papier…) '
                      'pour voir ce qu\'il vous reste vraiment.'),
                ),
              for (var i = 0; i < data.costs.length; i++)
                ListTile(
                  dense: true,
                  title: Text(data.costs[i].label),
                  subtitle: Text(data.costs[i].perTicket ? 'Par ticket vendu' : 'Par mois'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formatMoney(data.costs[i].amount, currency)),
                      IconButton(
                        tooltip: 'Supprimer',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final list = [...data.costs]..removeAt(i);
                          await _store.save(list);
                          await reload();
                        },
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Les coûts enregistrés sont appliqués tels quels à chaque mois affiché. '
                'Ils restent sur cet appareil.',
                style: t.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _line(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Flexible(child: Text(a)), Text(b)],
        ),
      );
}
