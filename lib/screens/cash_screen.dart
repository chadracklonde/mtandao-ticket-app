import 'package:flutter/material.dart';

import '../models.dart';
import '../services/insights.dart';
import '../services/mikhmon_service.dart';
import '../services/sales_report.dart';
import '../util.dart';
import '../widgets/async_body.dart';
import '../widgets/desktop.dart';

class _CashData {
  _CashData(this.sales, this.users, this.profiles, this.closings);
  final List<Sale> sales;
  final List<HotspotUser> users;
  final List<HotspotProfile> profiles;
  final List<CashClosing> closings;
}

/// Clôture de caisse : montant attendu (ventes du jour) contre montant encaissé,
/// et tickets utilisés sans vente enregistrée.
class CashScreen extends StatefulWidget {
  const CashScreen({super.key, required this.service, required this.session});

  final MikhmonService service;
  final Session session;

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  late final CashStore _store = CashStore(widget.session.id);
  final _counted = TextEditingController();
  DateTime _day = SalesSummary.dayOf(DateTime.now());
  String? _filledFor;

  @override
  void dispose() {
    _counted.dispose();
    super.dispose();
  }

  Future<_CashData> _load() async {
    final sales = await widget.service.sales();
    final users = await widget.service.hotspotUsers();
    final profiles = await widget.service.profiles();
    final closings = await _store.load();
    _filledFor = null;
    return _CashData(sales, users, profiles, closings);
  }

  Future<void> _save(int expected, Future<void> Function() reload) async {
    final counted = int.tryParse(_counted.text.replaceAll(RegExp(r'[\s.,]'), ''));
    if (counted == null || counted < 0) {
      showMessage(context, 'Entrez le montant réellement encaissé.');
      return;
    }
    await _store.save(CashClosing(
      day: dayKey(_day),
      expected: expected,
      counted: counted,
      savedAt: DateTime.now(),
    ));
    await reload();
    if (mounted) showMessage(context, 'Clôture enregistrée.');
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.session.currency;
    final t = Theme.of(context).textTheme;
    return AsyncBody<_CashData>(
      load: _load,
      builder: (context, data, reload) {
        final summary = SalesSummary.of(data.sales, _day, _day);
        final expected = summary.total;
        final key = dayKey(_day);
        final existing = data.closings.where((c) => c.day == key).firstOrNull;
        if (_filledFor != key) {
          _filledFor = key;
          _counted.text = existing == null ? '' : '${existing.counted}';
        }
        final typed = int.tryParse(_counted.text.replaceAll(RegExp(r'[\s.,]'), ''));
        final diff = typed == null ? null : typed - expected;
        final missing = usedWithoutSale(data.users, data.sales, data.profiles);
        final lost = missingRevenue(missing, data.profiles);

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
                    tooltip: 'Jour précédent',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() => _day = DateTime(_day.year, _day.month, _day.day - 1)),
                  ),
                  Text(formatDate(_day), style: t.titleMedium),
                  IconButton(
                    tooltip: 'Jour suivant',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: SalesSummary.dayOf(_day).isBefore(SalesSummary.dayOf(DateTime.now()))
                        ? () => setState(() => _day = DateTime(_day.year, _day.month, _day.day + 1))
                        : null,
                  ),
                ],
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Montant attendu', style: t.bodySmall),
                      Text(formatMoney(expected, currency), style: t.headlineSmall),
                      Text('${summary.count} ticket(s) vendu(s)', style: t.bodySmall),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _counted,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Montant réellement encaissé ($currency)',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      if (diff != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          diff == 0
                              ? 'La caisse est juste.'
                              : diff < 0
                                  ? 'Il manque ${formatMoney(-diff, currency)}.'
                                  : 'Il y a ${formatMoney(diff, currency)} de trop.',
                          style: t.titleSmall?.copyWith(
                            color: diff == 0 ? Colors.green.shade700 : Colors.red.shade700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => _save(expected, reload),
                        icon: const Icon(Icons.lock_clock),
                        label: Text(existing == null ? 'Clôturer la journée' : 'Mettre à jour la clôture'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Tickets à vérifier', style: t.titleMedium),
              const SizedBox(height: 4),
              if (missing.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.check_circle_outline, color: Colors.green),
                    title: Text('Tout concorde'),
                    subtitle: Text('Chaque ticket utilisé a une vente enregistrée.'),
                  ),
                )
              else ...[
                Text(
                  '${missing.length} ticket(s) utilisé(s) sans vente enregistrée, soit environ '
                  '${formatMoney(lost, currency)} : vente effacée, ticket offert, ou ticket '
                  'utilisé avant l\'installation du suivi des ventes.',
                  style: t.bodySmall,
                ),
                for (final u in missing.take(50))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.help_outline),
                    title: Text(u.name),
                    subtitle: Text('${u.profile} · ${formatBytes(u.bytesTotal)} consommés'),
                  ),
                if (missing.length > 50) Text('… et ${missing.length - 50} autres.', style: t.bodySmall),
              ],
              const SizedBox(height: 16),
              Text('Historique des clôtures', style: t.titleMedium),
              if (data.closings.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Aucune clôture enregistrée.'),
                ),
              for (final c in data.closings.take(30))
                ListTile(
                  dense: true,
                  title: Text(formatDate(DateTime.parse(c.day))),
                  subtitle: Text('Attendu ${formatMoney(c.expected, currency)} · '
                      'encaissé ${formatMoney(c.counted, currency)}'),
                  trailing: Text(
                    c.difference == 0
                        ? 'Juste'
                        : (c.difference > 0 ? '+' : '') + formatMoney(c.difference, currency),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: c.difference == 0
                          ? Colors.green.shade700
                          : (c.difference < 0 ? Colors.red.shade700 : Colors.orange.shade800),
                    ),
                  ),
                  onTap: () => setState(() => _day = DateTime.parse(c.day)),
                ),
            ],
          ),
        );
      },
    );
  }
}
