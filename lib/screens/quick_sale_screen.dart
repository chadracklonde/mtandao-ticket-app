import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../services/insights.dart';
import '../services/mikhmon_service.dart';
import '../util.dart';
import '../widgets/open_page.dart';
import 'single_ticket_screen.dart';
import '../widgets/desktop.dart';

/// Vente rapide : un seul ticket, prêt à envoyer au client (WhatsApp, SMS…).
class QuickSaleScreen extends StatefulWidget {
  const QuickSaleScreen({super.key, required this.service, required this.session});

  final MikhmonService service;
  final Session session;

  @override
  State<QuickSaleScreen> createState() => _QuickSaleScreenState();
}

class _QuickSaleScreenState extends State<QuickSaleScreen> {
  List<HotspotProfile>? _profiles;
  String? _error;
  String? _profileName;
  bool _busy = false;
  Voucher? _voucher;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = (await widget.service.profiles()).where((p) => p.price > 0).toList();
      if (!mounted) return;
      setState(() {
        _profiles = list;
        _profileName ??= list.isEmpty ? null : list.first.name;
      });
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  HotspotProfile? get _profile {
    final list = _profiles;
    if (list == null) return null;
    for (final p in list) {
      if (p.name == _profileName) return p;
    }
    return null;
  }

  Future<void> _create() async {
    final profile = _profile;
    if (profile == null) return;
    setState(() => _busy = true);
    try {
      final made = await widget.service.generate(GenerateRequest(profile: profile, count: 1));
      if (mounted) setState(() => _voucher = made.first);
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Voucher v) => ticketMessage(
        network: widget.session.name,
        voucher: v,
        loginAddress: widget.session.dnsName,
        currency: widget.session.currency,
      );

  Future<void> _share(Voucher v) async {
    try {
      await Share.share(_message(v));
    } catch (_) {
      await _copy(v);
    }
  }

  Future<void> _copy(Voucher v) async {
    await Clipboard.setData(ClipboardData(text: _message(v)));
    if (mounted) showMessage(context, 'Message copié. Collez-le dans WhatsApp ou un SMS.');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final profiles = _profiles;
    Widget body;
    if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Réessayer')),
          ]),
        ),
      );
    } else if (profiles == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (profiles.isEmpty) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aucun profil payant sur le routeur.\nCréez-en un dans Plus > Profils.',
              textAlign: TextAlign.center),
        ),
      );
    } else {
      final v = _voucher;
      final profile = _profile;
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _profileName,
            decoration: const InputDecoration(labelText: 'Profil à vendre', border: OutlineInputBorder()),
            items: [
              for (final p in profiles)
                DropdownMenuItem(
                  value: p.name,
                  child: Text('${p.name} · ${formatMoney(p.price, widget.session.currency)}'),
                ),
            ],
            onChanged: _busy ? null : (x) => setState(() => _profileName = x),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy || profile == null ? null : _create,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.bolt),
            label: Text(v == null ? 'Créer le ticket' : 'Créer un autre ticket'),
          ),
          TextButton.icon(
            onPressed: _busy
                ? null
                : () => openPage(context, 'Ticket sur mesure',
                    SingleTicketScreen(service: widget.service, session: widget.session)),
            icon: const Icon(Icons.tune),
            label: const Text('Choisir la durée, le code, l\'appareil…'),
          ),
          if (v != null) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(v.profile, style: t.titleMedium),
                    const SizedBox(height: 8),
                    SelectableText(v.name,
                        style: t.displaySmall?.copyWith(fontFamily: 'monospace', letterSpacing: 2)),
                    if (v.separate) ...[
                      const SizedBox(height: 4),
                      SelectableText('Mot de passe : ${v.password}'),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      [
                        if (v.price > 0) formatMoney(v.price, widget.session.currency),
                        if (v.uptime.isNotEmpty) v.uptime,
                        if (v.dataLimit.isNotEmpty) v.dataLimit,
                      ].join(' · '),
                      style: t.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => _share(v),
              icon: const Icon(Icons.send),
              label: const Text('Envoyer (WhatsApp, SMS…)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _copy(v),
              icon: const Icon(Icons.copy),
              label: const Text('Copier le message'),
            ),
            const SizedBox(height: 12),
            Text(
              'La vente est enregistrée automatiquement à la première connexion du client.',
              style: t.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      );
    }
    return ContentWidth(maxWidth: 560, child: body);
  }
}
