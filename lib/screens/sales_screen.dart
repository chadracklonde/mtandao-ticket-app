import 'package:flutter/material.dart';

import '../models.dart';
import '../services/mikhmon_service.dart';
import '../services/file_delivery.dart';
import '../services/sales_export.dart';
import '../services/sales_report.dart';
import '../util.dart';
import '../widgets/async_body.dart';
import '../widgets/sales_chart.dart';

/// Rapport de ventes : jour, mois ou période choisie.
class SalesScreen extends StatelessWidget {
  const SalesScreen({super.key, required this.service, required this.session});

  final MikhmonService service;
  final Session session;

  @override
  Widget build(BuildContext context) {
    return AsyncBody<List<Sale>>(
      load: service.sales,
      builder: (context, sales, reload) => SalesReportView(
        sales: sales,
        session: session,
        service: service,
        onChanged: reload,
      ),
    );
  }
}

enum ReportMode { day, month, period }

class SalesReportView extends StatefulWidget {
  const SalesReportView({
    super.key,
    required this.sales,
    required this.session,
    this.service,
    this.onChanged,
  });

  final List<Sale> sales;
  final Session session;

  /// Nécessaire pour effacer des ventes ; sans lui, le rapport est en lecture seule.
  final MikhmonService? service;
  final Future<void> Function()? onChanged;

  @override
  State<SalesReportView> createState() => _SalesReportViewState();
}

class _SalesReportViewState extends State<SalesReportView> {
  ReportMode _mode = ReportMode.day;
  late DateTime _day;
  late DateTime _month;
  late DateTimeRange _period;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _day = SalesSummary.dayOf(now);
    _month = DateTime(now.year, now.month);
    final (first, _) = SalesSummary.monthRange(now);
    _period = DateTimeRange(start: first, end: SalesSummary.dayOf(now));
  }

  SalesSummary get _summary {
    switch (_mode) {
      case ReportMode.day:
        return SalesSummary.of(widget.sales, _day, _day);
      case ReportMode.month:
        final (a, b) = SalesSummary.monthRange(_month);
        return SalesSummary.of(widget.sales, a, b);
      case ReportMode.period:
        return SalesSummary.of(widget.sales, _period.start, _period.end);
    }
  }

  SalesSummary get _previous {
    switch (_mode) {
      case ReportMode.day:
        final p = DateTime(_day.year, _day.month, _day.day - 1);
        return SalesSummary.of(widget.sales, p, p);
      case ReportMode.month:
        final (a, b) = SalesSummary.monthRange(DateTime(_month.year, _month.month - 1));
        return SalesSummary.of(widget.sales, a, b);
      case ReportMode.period:
        final days = _period.end.difference(_period.start).inDays + 1;
        return SalesSummary.of(
          widget.sales,
          _period.start.subtract(Duration(days: days)),
          _period.start.subtract(const Duration(days: 1)),
        );
    }
  }

  String get _previousLabel => switch (_mode) {
        ReportMode.day => 'la veille',
        ReportMode.month => 'le mois précédent',
        ReportMode.period => 'la période précédente',
      };

  Future<void> _deleteSales(List<Sale> sales, String what) async {
    final service = widget.service;
    if (service == null || sales.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Effacer ces ventes ?'),
        content: Text('$what sera effacé du rapport. Cette action est définitive ; '
            'les tickets ne sont pas supprimés.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Effacer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final n = await service.deleteSales(sales);
      if (!mounted) return;
      showMessage(context, '$n vente(s) effacée(s)');
      await widget.onChanged?.call();
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    }
  }

  String get _title {
    switch (_mode) {
      case ReportMode.day:
        return formatDate(_day);
      case ReportMode.month:
        return '${monthNames[_month.month - 1]} ${_month.year}';
      case ReportMode.period:
        return 'Du ${formatDate(_period.start)} au ${formatDate(_period.end)}';
    }
  }

  Future<void> _export(SalesSummary summary, {required bool excel}) async {
    try {
      final name = salesFileName(widget.session, _title);
      final String path;
      if (excel) {
        final bytes = buildSalesXlsx(summary, widget.session, _title);
        path = await deliverFile(bytes, '$name.xlsx',
                mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') ??
            '';
      } else {
        final bytes = await buildSalesPdf(summary, widget.session, _title);
        path = await deliverFile(bytes, '$name.pdf', mimeType: 'application/pdf') ?? '';
      }
      if (mounted && path.isNotEmpty) showMessage(context, 'Enregistré : $path');
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    }
  }

  void _shift(int delta) {
    setState(() {
      if (_mode == ReportMode.day) {
        _day = DateTime(_day.year, _day.month, _day.day + delta);
      } else if (_mode == ReportMode.month) {
        _month = DateTime(_month.year, _month.month + delta);
      }
    });
  }

  Future<void> _pick() async {
    if (_mode == ReportMode.day) {
      final d = await showDatePicker(
        context: context,
        initialDate: _day,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 1)),
      );
      if (d != null) setState(() => _day = SalesSummary.dayOf(d));
    } else if (_mode == ReportMode.period) {
      final r = await showDateRangePicker(
        context: context,
        initialDateRange: _period,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 1)),
      );
      if (r != null) setState(() => _period = r);
    }
  }

  void _showDay(BuildContext context, DayTotal d) {
    final currency = widget.session.currency;
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
              title: Text(formatDate(d.day), style: Theme.of(ctx).textTheme.titleMedium),
              subtitle: Text('${d.sales.length} ticket(s)'),
              trailing: Text(formatMoney(d.total, currency),
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            const Divider(height: 1),
            for (final s in d.sales) _saleTile(s, currency),
          ],
        ),
      ),
    );
  }

  Widget _saleTile(Sale s, String currency) => ListTile(
        dense: true,
        title: Text(s.user),
        subtitle: Text('${formatTime(s.time)} · ${s.profile} · ${s.address}'),
        trailing: Text(formatMoney(s.price, currency)),
        onLongPress: widget.service == null
            ? null
            : () => _deleteSales([s], 'La vente de ${s.user} (${formatMoney(s.price, currency)})'),
      );

  Widget _comparison(BuildContext context, SalesSummary summary, String currency) {
    final prev = _previous;
    final pct = SalesSummary.changePercent(summary.total, prev.total);
    final text = prev.total <= 0
        ? 'Aucune vente $_previousLabel pour comparer.'
        : '${pct! >= 0 ? '+' : '−'}${pct.abs().toStringAsFixed(0)} % par rapport à $_previousLabel '
            '(${formatMoney(prev.total, currency)})';
    final color = pct == null
        ? null
        : (pct >= 0 ? const Color(0xFF17784E) : const Color(0xFFC63D2F));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
    );
  }

  Widget _chart(SalesSummary summary) {
    final List<int> values;
    String? Function(int) label;
    if (_mode == ReportMode.day) {
      values = summary.perHourTotals();
      label = (i) => i % 3 == 0 ? '${i}h' : null;
    } else {
      values = summary.perDayTotals();
      final start = summary.start;
      final step = values.length > 20 ? 5 : 1;
      label = (i) {
        final d = DateTime(start.year, start.month, start.day + i);
        return (i % step == 0) ? '${d.day}' : null;
      };
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SalesBarChart(values: values, labelOf: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.session.currency;
    final summary = _summary;
    final canShift = _mode != ReportMode.period;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<ReportMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ReportMode.day, label: Text('Jour')),
              ButtonSegment(value: ReportMode.month, label: Text('Mois')),
              ButtonSegment(value: ReportMode.period, label: Text('Période')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              tooltip: 'Précédent',
              onPressed: canShift ? () => _shift(-1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Flexible(
              child: TextButton(
                onPressed: _mode == ReportMode.month ? null : _pick,
                child: Text(_title, style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            IconButton(
              tooltip: 'Suivant',
              onPressed: canShift ? () => _shift(1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Stat(label: 'Encaissé', value: formatMoney(summary.total, currency)),
                _Stat(label: 'Tickets vendus', value: '${summary.count}'),
              ],
            ),
          ),
        ),
        if (summary.count > 0) ...[
          _comparison(context, summary, currency),
          _chart(summary),
        ],
        if (summary.count > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _export(summary, excel: false),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Exporter PDF'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _export(summary, excel: true),
                    icon: const Icon(Icons.table_chart_outlined),
                    label: const Text('Exporter Excel'),
                  ),
                ),
                if (widget.service != null)
                  IconButton(
                    tooltip: 'Effacer ces ventes',
                    onPressed: () => _deleteSales(summary.sales, 'Les ${summary.count} vente(s) de « $_title »'),
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
              ],
            ),
          ),
        if (summary.count == 0)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Aucune vente sur cette période.', textAlign: TextAlign.center)),
          ),
        if (summary.byProfile.length > 1) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Par profil', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          for (final p in summary.byProfile)
            ListTile(
              dense: true,
              title: Text(p.profile),
              subtitle: Text('${p.count} ticket(s)'),
              trailing: Text(formatMoney(p.total, currency)),
            ),
        ],
        if (_mode == ReportMode.day)
          for (final s in summary.sales) _saleTile(s, currency)
        else
          for (final d in summary.days)
            ListTile(
              title: Text(formatDate(d.day)),
              subtitle: Text('${d.sales.length} ticket(s)'),
              trailing: Text(formatMoney(d.total, currency),
                  style: Theme.of(context).textTheme.titleSmall),
              onTap: () => _showDay(context, d),
            ),
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
