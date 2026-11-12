import 'package:flutter/material.dart';

import '../models.dart';
import '../services/insights.dart';
import '../services/mikhmon_service.dart';
import '../services/sales_report.dart';
import '../util.dart';
import '../widgets/async_body.dart';
import '../widgets/open_page.dart';
import 'abuse_screen.dart';
import 'cash_screen.dart';
import 'profit_screen.dart';
import 'quick_sale_screen.dart';
import 'search_screen.dart';
import 'single_ticket_screen.dart';

class _Dash {
  _Dash({
    required this.sales,
    required this.active,
    required this.profiles,
    required this.batches,
    required this.users,
    required this.costs,
    this.resource,
  });
  final List<Sale> sales;
  final List<ActiveUser> active;
  final List<HotspotProfile> profiles;
  final List<VoucherBatch> batches;
  final List<HotspotUser> users;
  final List<CostItem> costs;
  final RouterResource? resource;
}

/// Page d'accueil : l'essentiel de l'activité en un coup d'œil.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.service, required this.session});

  final MikhmonService service;
  final Session session;

  Future<_Dash> _load() async {
    final results = await Future.wait<Object?>([
      service.sales(),
      service.activeUsers(),
      service.profiles(),
      service.unusedBatches(),
      service.hotspotUsers(),
      CostStore(session.id).load(),
      service.resource().then<Object?>((r) => r).catchError((_) => null),
    ]);
    return _Dash(
      sales: results[0] as List<Sale>,
      active: results[1] as List<ActiveUser>,
      profiles: results[2] as List<HotspotProfile>,
      batches: results[3] as List<VoucherBatch>,
      users: results[4] as List<HotspotUser>,
      costs: results[5] as List<CostItem>,
      resource: results[6] as RouterResource?,
    );
  }

  /// Heure de la journée où l'on vend le plus (30 derniers jours), s'il y a assez de ventes.
  static int? peakHour(List<Sale> sales, DateTime now) {
    final from = DateTime(now.year, now.month, now.day - 29);
    final counts = List<int>.filled(24, 0);
    var n = 0;
    for (final s in sales) {
      if (s.time.isBefore(from)) continue;
      counts[s.time.hour]++;
      n++;
    }
    if (n < 5) return null;
    var best = 0;
    for (var h = 1; h < 24; h++) {
      if (counts[h] > counts[best]) best = h;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<_Dash>(
      load: _load,
      builder: (context, d, reload) {
        final currency = session.currency;
        final t = Theme.of(context).textTheme;
        final now = DateTime.now();
        final today = SalesSummary.dayOf(now);
        final yesterday = DateTime(today.year, today.month, today.day - 1);
        final sToday = SalesSummary.of(d.sales, today, today);
        final sYesterday = SalesSummary.of(d.sales, yesterday, yesterday);
        final change = SalesSummary.changePercent(sToday.total, sYesterday.total);
        final peak = peakHour(d.sales, now);
        final net = d.costs.isEmpty ? null : NetProfit.forMonth(d.sales, now, d.costs);

        final forecast = forecastStock(d.profiles, d.batches, d.sales, now);
        final alerts = detectAbuse(d.active, format: formatBytes);
        final missing = usedWithoutSale(d.users, d.sales, d.profiles);

        Widget card({required String title, required Widget child, VoidCallback? onTap}) => Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: t.labelLarge),
                      const SizedBox(height: 8),
                      child,
                    ],
                  ),
                ),
              ),
            );

        final cards = <Widget>[
          card(
            title: 'Aujourd\'hui',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatMoney(sToday.total, currency), style: t.headlineSmall),
                Text('${sToday.count} ticket(s) vendu(s)', style: t.bodySmall),
                const SizedBox(height: 4),
                Text(
                  change == null
                      ? 'Hier : ${formatMoney(sYesterday.total, currency)}'
                      : 'Hier : ${formatMoney(sYesterday.total, currency)} '
                          '(${change >= 0 ? '+' : ''}${change.round()} %)',
                  style: t.bodySmall,
                ),
                if (peak != null)
                  Text('Heure de pointe : ${peak}h - ${(peak + 1) % 24}h', style: t.bodySmall),
                if (net != null)
                  Text('Bénéfice net du mois : ${formatMoney(net.net, currency)}', style: t.bodySmall),
              ],
            ),
            onTap: net == null && d.costs.isEmpty
                ? null
                : () => openPage(context, 'Bénéfice net', ProfitScreen(service: service, session: session)),
          ),
          card(
            title: 'Connectés maintenant',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${d.active.length}', style: t.headlineSmall),
                if (d.resource != null)
                  Text(
                    'Routeur : processeur ${d.resource!.cpuLoad} % · '
                    'mémoire ${(d.resource!.memoryRatio * 100).round()} %',
                    style: t.bodySmall,
                  )
                else
                  Text('État du routeur indisponible', style: t.bodySmall),
              ],
            ),
          ),
          card(
            title: 'À vérifier',
            child: (alerts.isEmpty && missing.isEmpty)
                ? Row(children: [
                    Icon(Icons.check_circle_outline, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Tout est en ordre.')),
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (alerts.isNotEmpty)
                        InkWell(
                          onTap: () => openPage(context, 'Abus et appareils bloqués',
                              AbuseScreen(service: service)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(children: [
                              Icon(Icons.warning_amber, color: Colors.orange.shade800),
                              const SizedBox(width: 8),
                              Expanded(child: Text('${alerts.length} comportement(s) suspect(s) en ligne')),
                            ]),
                          ),
                        ),
                      if (missing.isNotEmpty)
                        InkWell(
                          onTap: () => openPage(context, 'Clôture de caisse',
                              CashScreen(service: service, session: session)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(children: [
                              Icon(Icons.help_outline, color: Colors.orange.shade800),
                              const SizedBox(width: 8),
                              Expanded(child: Text('${missing.length} ticket(s) utilisé(s) sans vente')),
                            ]),
                          ),
                        ),
                    ],
                  ),
          ),
          card(
            title: 'Stock de tickets',
            child: forecast.isEmpty
                ? const Text('Aucun profil payant.')
                : Column(
                    children: [
                      for (final f in forecast)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                f.critical ? Icons.error : (f.soon ? Icons.warning_amber : Icons.inventory_2_outlined),
                                size: 18,
                                color: f.critical
                                    ? Colors.red.shade700
                                    : (f.soon ? Colors.orange.shade800 : null),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${f.profile} : ${f.left} en stock'
                                  '${f.daysLeft == null ? '' : ' (~${f.daysLeft!.floor()} j)'}'
                                  '${f.suggested > 0 ? ' · générez ~${f.suggested}' : ''}',
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ];

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 760;
                if (!wide) {
                  return Column(children: [
                    for (final w in cards) ...[w, const SizedBox(height: 12)],
                  ]);
                }
                final half = (c.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [for (final w in cards) SizedBox(width: half, child: w)],
                );
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => openPage(context, 'Vente rapide',
                      QuickSaleScreen(service: service, session: session)),
                  icon: const Icon(Icons.bolt),
                  label: const Text('Vente rapide'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => openPage(context, 'Ticket sur mesure',
                      SingleTicketScreen(service: service, session: session)),
                  icon: const Icon(Icons.tune),
                  label: const Text('Ticket sur mesure'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      openPage(context, 'Recherche', SearchScreen(service: service, session: session)),
                  icon: const Icon(Icons.search),
                  label: const Text('Rechercher un ticket'),
                ),
                OutlinedButton.icon(
                  onPressed: () => openPage(context, 'Clôture de caisse',
                      CashScreen(service: service, session: session)),
                  icon: const Icon(Icons.lock_clock),
                  label: const Text('Clôture de caisse'),
                ),
                OutlinedButton.icon(
                  onPressed: () => openPage(context, 'Bénéfice net',
                      ProfitScreen(service: service, session: session)),
                  icon: const Icon(Icons.savings_outlined),
                  label: const Text('Bénéfice net'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
