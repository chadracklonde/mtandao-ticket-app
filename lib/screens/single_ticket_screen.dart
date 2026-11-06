import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../services/insights.dart';
import '../services/mikhmon_service.dart';
import '../util.dart';
import '../widgets/desktop.dart';

/// Ticket sur mesure : un seul ticket, avec le profil, la durée, les données,
/// le code, l'appareil et le nom du client choisis à la main.
class SingleTicketScreen extends StatefulWidget {
  const SingleTicketScreen({super.key, required this.service, required this.session});

  final MikhmonService service;
  final Session session;

  @override
  State<SingleTicketScreen> createState() => _SingleTicketScreenState();
}

class _SingleTicketScreenState extends State<SingleTicketScreen> {
  final _form = GlobalKey<FormState>();
  final _time = TextEditingController();
  final _data = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _mac = TextEditingController();
  final _note = TextEditingController();

  List<HotspotProfile>? _profiles;
  String? _error;
  String? _profileName;
  bool _busy = false;
  Voucher? _voucher;
  String _madeFor = '';
  String _madeMac = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_time, _data, _code, _password, _mac, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await widget.service.profiles();
      if (!mounted) return;
      setState(() {
        _profiles = list;
        _profileName ??= list.isEmpty ? null : list.first.name;
        _fillFromProfile();
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

  /// Propose la durée et les données du profil ; l'utilisateur peut les changer.
  void _fillFromProfile() {
    final p = _profile;
    _time.text = p?.uptime ?? '';
    _data.text = p?.dataLimit ?? '';
  }

  Future<void> _create() async {
    final profile = _profile;
    if (profile == null || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final mac = _mac.text.trim().toUpperCase();
      final made = await widget.service.generate(GenerateRequest(
        profile: profile,
        count: 1,
        timeLimit: _time.text.trim().toLowerCase(),
        dataLimit: _data.text.trim(),
        customCode: _code.text.trim(),
        customPassword: _password.text.trim(),
        bindMac: mac,
        note: _note.text,
      ));
      if (mounted) {
        setState(() {
          _voucher = made.first;
          _madeFor = cleanNote(_note.text);
          _madeMac = mac;
        });
      }
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

  Future<void> _copy(Voucher v) async {
    await Clipboard.setData(ClipboardData(text: _message(v)));
    if (mounted) showMessage(context, 'Message copié. Collez-le dans WhatsApp ou un SMS.');
  }

  Future<void> _share(Voucher v) async {
    try {
      await Share.share(_message(v));
    } catch (_) {
      await _copy(v);
    }
  }

  Widget _chips(List<String> values, TextEditingController c) => Wrap(
        spacing: 8,
        children: [
          for (final t in values)
            ActionChip(
              label: Text(t),
              onPressed: _busy ? null : () => setState(() => c.text = t),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final profiles = _profiles;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Réessayer')),
          ]),
        ),
      );
    }
    if (profiles == null) return const Center(child: CircularProgressIndicator());
    if (profiles.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aucun profil sur le routeur.\nCréez-en un dans Plus > Profils.', textAlign: TextAlign.center),
        ),
      );
    }
    final v = _voucher;
    final profile = _profile;
    return ContentWidth(
      maxWidth: 620,
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Ticket sur mesure', style: t.titleLarge),
            const SizedBox(height: 4),
            Text('Un seul ticket, avec les réglages que vous choisissez pour ce client.', style: t.bodySmall),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _profileName,
              decoration: const InputDecoration(labelText: 'Profil', border: OutlineInputBorder()),
              items: [
                for (final p in profiles)
                  DropdownMenuItem(
                    value: p.name,
                    child: Text(p.price > 0 ? '${p.name} · ${formatMoney(p.price, widget.session.currency)}' : p.name),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (x) => setState(() {
                        _profileName = x;
                        _fillFromProfile();
                      }),
            ),
            if (profile != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  [
                    if (profile.speedLabel.isNotEmpty) 'Vitesse ${profile.speedLabel}',
                    '${profile.sharedUsers} appareil(s)',
                    if (profile.price > 0)
                      'Le prix enregistré est celui du profil'
                    else
                      'Profil gratuit : aucune vente enregistrée',
                  ].join(' · '),
                  style: t.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _time,
              enabled: !_busy,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Durée du ticket',
                helperText: '1h = 1 heure, 1d = 1 jour. Elle démarre à la première connexion. Vide = illimitée',
                border: OutlineInputBorder(),
              ),
              validator: (x) {
                final s = (x ?? '').trim().toLowerCase();
                return (s.isNotEmpty && !uptimePattern.hasMatch(s)) ? 'Format invalide (ex. 1h, 1d)' : null;
              },
            ),
            const SizedBox(height: 8),
            _chips(const ['30m', '1h', '3h', '12h', '1d', '3d', '7d', '30d'], _time),
            const SizedBox(height: 16),
            TextFormField(
              controller: _data,
              enabled: !_busy,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Données',
                helperText: 'Envoyées + reçues : 500M, 1G, 2G… Vide = illimitées',
                border: OutlineInputBorder(),
              ),
              validator: (x) {
                final s = (x ?? '').trim();
                return (s.isNotEmpty && parseDataSize(s) == null) ? 'Format invalide (ex. 500M, 1G)' : null;
              },
            ),
            const SizedBox(height: 8),
            _chips(const ['100M', '500M', '1G', '2G', '5G'], _data),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              enabled: !_busy,
              maxLength: 30,
              decoration: const InputDecoration(
                labelText: 'Nom du client (facultatif)',
                helperText: 'Gardé dans le ticket : retrouvez-le avec la recherche',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _code,
              enabled: !_busy,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Code choisi (facultatif)',
                helperText: 'Vide = code aléatoire. Lettres, chiffres, point, tiret : 3 à 32 caractères',
                border: OutlineInputBorder(),
              ),
              validator: (x) {
                final s = (x ?? '').trim();
                return (s.isNotEmpty && !customCodePattern.hasMatch(s)) ? 'Code invalide' : null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              enabled: !_busy,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Mot de passe choisi (facultatif)',
                helperText: 'Vide = identique au code. Seulement avec un code choisi',
                border: OutlineInputBorder(),
              ),
              validator: (x) {
                final s = (x ?? '').trim();
                if (s.isEmpty) return null;
                if (_code.text.trim().isEmpty) return 'Choisissez aussi un code';
                return customCodePattern.hasMatch(s) ? null : 'Mot de passe invalide';
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _mac,
              enabled: !_busy,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Lier à un appareil (facultatif)',
                helperText: 'Adresse MAC AA:BB:CC:DD:EE:FF. Le ticket ne marchera que sur cet appareil',
                border: OutlineInputBorder(),
              ),
              validator: (x) {
                final s = (x ?? '').trim().toUpperCase();
                return (s.isNotEmpty && !macPattern.hasMatch(s)) ? 'Adresse MAC invalide' : null;
              },
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy || profile == null ? null : _create,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.confirmation_number_outlined),
              label: Text(v == null ? 'Créer le ticket' : 'Créer un autre ticket'),
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
                          v.uptime.isEmpty ? 'durée illimitée' : v.uptime,
                          if (v.dataLimit.isNotEmpty) v.dataLimit,
                          if (_madeFor.isNotEmpty) 'pour $_madeFor',
                          if (_madeMac.isNotEmpty) 'lié à $_madeMac',
                        ].join(' · '),
                        style: t.bodySmall,
                        textAlign: TextAlign.center,
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
            ],
          ],
        ),
      ),
    );
  }
}
