import 'package:flutter/material.dart';

import '../models.dart';
import '../services/mikhmon_service.dart';
import '../util.dart';
import '../widgets/async_body.dart';

/// Rapport de ventes par mois, avec détail par jour.
class SalesScreen extends StatelessWidget {
  const SalesScreen({super.key, required this.service, required this.session});

  final MikhmonService service;
  final Session session;

  @override
  Widget build(BuildContext context) {
    return AsyncBody<List<Sale>>(
      load: service.sales,
      builder: (context, sales, reload) => _SalesReport(sales: sales, session: session),
    );
  }
}

class _SalesReport extends StatefulWidget {
  const _SalesReport({required this.sales, required this.session});

  final List<Sale> sales;
  final Session session;

  @override
  State<_SalesReport> createState() => _SalesReportState();
}

class _SalesReportState extends State<_SalesReport> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _shift(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  void _showDay(BuildContext context, DateTime day, List<Sale> sales) {
    final currency = widget.session.currency;
    final total = sales.fold<int>(0, (a, s) => a + s.price);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, controller) => ListView(
          controller: controller,
          children: [
            ListTile(
              title: Text(formatDate(day), style: Theme.of(ctx).textTheme.titleMedium),
              subtitle: Text('${sales.length} ticket(s)'),
              trailing: Text(formatMoney(total, currency),
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            const Divider(height: 1),
            for (final s in sales)
              ListTile(
                dense: true,
                title: Text(s.user),
                subtitle: Text('${formatTime(s.time)} · ${s.profile} · ${s.address}'),
                trailing: Text(formatMoney(s.price, currency)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.session.currency;
    final inMonth = widget.sales
        .where((s) => s.time.year == _month.year && s.time.month == _month.month)
        .toList();
    final total = inMonth.fold<int>(0, (a, s) => a + s.price);

    final byDay = <DateTime, List<Sale>>{};
    for (final s in inMonth) {
      byDay.putIfAbsent(DateTime(s.time.year, s.time.month, s.time.day), () => []).add(s);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
            Text('${monthNames[_month.month - 1]} ${_month.year}',
                style: Theme.of(context).textTheme.titleMedium),
            IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
          ],
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Stat(label: 'Encaissé', value: formatMoney(total, currency)),
                _Stat(label: 'Tickets vendus', value: '${inMonth.length}'),
              ],
            ),
          ),
        ),
        if (days.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Aucune vente ce mois-ci.', textAlign: TextAlign.center)),
          ),
        for (final day in days)
          ListTile(
            title: Text(formatDate(day)),
            subtitle: Text('${byDay[day]!.length} ticket(s)'),
            trailing: Text(
              formatMoney(byDay[day]!.fold<int>(0, (a, s) => a + s.price), currency),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            onTap: () => _showDay(context, day, byDay[day]!),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
