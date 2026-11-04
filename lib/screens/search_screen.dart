import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../services/insights.dart';
import '../services/mikhmon_service.dart';
import '../services/search.dart';
import '../util.dart';
import '../widgets/async_body.dart';
import '../widgets/desktop.dart';
import '../widgets/extend_dialog.dart';

class _SearchData {
  _SearchData(this.users, this.sales, this.active, this.leases);
  final List<HotspotUser> users;
  final List<Sale> sales;
  final List<ActiveUser> active;
  final List<DhcpLease> leases;
}

/// Recherche rapide : retrouver un ticket (code, appareil, heure, montant) et agir dessus.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.service, required this.session});

  final MikhmonService service;
  final Session session;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _query = '';

  Future<_SearchData> _load() async {
    final users = await widget.service.hotspotUsers();
    final sales = await widget.service.sales();
    final active = await widget.service.activeUsers();
    var leases = <DhcpLease>[];
    try {
      leases = await widget.service.dhcpLeases();
    } catch (_) {}
    return _SearchData(users, sales, active, leases);
  }

  Future<void> _run(Future<void> Function() action, Future<void> Function() reload, String done) async {
    try {
      await action();
      await reload();
      if (mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    }
  }

  Future<void> _shareTicket(HotspotUser u) async {
    final v = Voucher(
      name: u.name,
      password: u.password.isEmpty ? u.name : u.password,
      profile: u.profile,
      uptime: u.limitUptime == null ? '' : toRouterDuration(u.limitUptime!),
      dataLimit: u.limitBytes > 0 ? dataLimitLabel(u.limitBytes) : '',
    );
    final text = ticketMessage(
      network: widget.session.name,
      voucher: v,
      loginAddress: widget.session.dnsName,
    );
    try {
      await Share.share(text);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) showMessage(context, 'Message copié.');
    }
  }

  Widget _ticketCard(BuildContext context, TicketHit h, Future<void> Function() reload) {
    final t = Theme.of(context).textTheme;
    final u = h.user;
    final currency = widget.session.currency;
    final sale = h.sales.isEmpty ? null : h.sales.first;
    final status = u == null
        ? 'Supprimé du routeur (expiré ou effacé)'
        : u.disabled
            ? 'Désactivé'
            : u.isExhausted
                ? 'Épuisé'
                : u.isNew
                    ? 'Neuf, jamais utilisé'
                    : 'Utilisé';
    final macs = {
      for (final s in h.sessions) if (s.mac.isNotEmpty) s.mac,
      if (sale != null && sale.mac.isNotEmpty) sale.mac,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: SelectableText(h.name,
                    style: t.titleLarge?.copyWith(fontFamily: 'monospace', letterSpacing: 1)),
              ),
              if (h.sessions.isNotEmpty)
                Chip(
                  avatar: Icon(Icons.wifi, size: 16, color: Colors.green.shade700),
                  label: const Text('Connecté'),
                  visualDensity: VisualDensity.compact,
                ),
            ]),
            Text(status, style: t.bodyMedium),
            const SizedBox(height: 6),
            if (u != null)
              Text(
                [
                  u.profile,
                  if (u.limitUptime != null) 'reste ${formatDuration(u.timeLeft!)}',
                  if (u.limitBytes > 0) 'reste ${dataLimitLabel(u.bytesLeft!)}',
                  if (u.bytesTotal > 0) '${formatBytes(u.bytesTotal)} consommés',
                ].join(' · '),
                style: t.bodySmall,
              ),
            if (sale != null)
              Text(
                'Vendu le ${formatDate(sale.time)} à ${formatTime(sale.time)} · '
                '${formatMoney(sale.price, currency)} · appareil ${sale.mac}',
                style: t.bodySmall,
              ),
            if (u != null && u.boundMac.isNotEmpty)
              Text('Lié à l\'appareil ${u.boundMac}', style: t.bodySmall),
            for (final s in h.sessions)
              Text('En ligne : ${s.address} · ${s.mac} · ${s.uptime}', style: t.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (u != null)
                  OutlinedButton.icon(
                    onPressed: () => _shareTicket(u),
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Renvoyer au client'),
                  ),
                if (u != null)
                  OutlinedButton(
                    onPressed: () async {
                      final ask = await askExtension(context, u);
                      if (ask == null) return;
                      await _run(() => widget.service.extendUser(u, addTime: ask.time, addBytes: ask.bytes),
                          reload, 'Ticket prolongé');
                    },
                    child: const Text('Prolonger'),
                  ),
                if (u != null)
                  OutlinedButton(
                    onPressed: () => _run(() => widget.service.resetUserCounters(u.id), reload,
                        'Compteurs remis à zéro'),
                    child: const Text('Remettre à zéro'),
                  ),
                if (u != null)
                  OutlinedButton(
                    onPressed: () => _run(() => widget.service.setUserDisabled(u.id, !u.disabled), reload,
                        u.disabled ? 'Ticket réactivé' : 'Ticket désactivé'),
                    child: Text(u.disabled ? 'Réactiver' : 'Désactiver'),
                  ),
                if (u != null && u.boundMac.isNotEmpty)
                  OutlinedButton(
                    onPressed: () => _run(() => widget.service.unbindUser(u.id), reload, 'Appareil libéré'),
                    child: const Text('Libérer l\'appareil'),
                  ),
                for (final s in h.sessions)
                  OutlinedButton(
                    onPressed: () => _run(() => widget.service.disconnect(s.id), reload, 'Session coupée'),
                    child: Text('Déconnecter ${s.address}'),
                  ),
                for (final m in macs)
                  TextButton.icon(
                    onPressed: () => _run(() => widget.service.blockDevice(m, note: h.name), reload,
                        'Appareil bloqué'),
                    icon: const Icon(Icons.block, size: 18),
                    label: Text('Bloquer $m'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AsyncBody<_SearchData>(
      load: _load,
      builder: (context, d, reload) {
        final r = search(_query,
            users: d.users, sales: d.sales, active: d.active, leases: d.leases, now: DateTime.now());
        return ContentWidth(
          maxWidth: 820,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                autofocus: true,
                autocorrect: false,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Code, appareil (MAC), adresse, montant, heure',
                  helperText: 'Ex. « 482913 », « AA:BB:CC », « 500 14h » (500 FC vendus vers 14 h)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 12),
              if (_query.trim().isEmpty)
                Text('${d.users.length} ticket(s) sur le routeur, ${d.active.length} connecté(s).',
                    style: t.bodySmall)
              else if (r.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Aucun résultat.')),
                ),
              for (final h in r.tickets) ...[
                _ticketCard(context, h, reload),
                const SizedBox(height: 8),
              ],
              if (r.devices.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Appareils', style: t.titleMedium),
                for (final dev in r.devices)
                  ListTile(
                    leading: const Icon(Icons.devices_outlined),
                    title: Text(dev.hostName.isEmpty ? dev.mac : '${dev.hostName} · ${dev.mac}'),
                    subtitle: Text(
                      [dev.address, if (dev.tickets.isNotEmpty) 'tickets : ${dev.tickets.join(', ')}']
                          .join(' · '),
                    ),
                    trailing: TextButton(
                      onPressed: () => _run(() => widget.service.blockDevice(dev.mac), reload, 'Appareil bloqué'),
                      child: const Text('Bloquer'),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
