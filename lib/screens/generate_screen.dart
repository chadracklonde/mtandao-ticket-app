import 'package:flutter/material.dart';

import '../models.dart';
import '../services/mikhmon_service.dart';
import '../util.dart';
import '../widgets/async_body.dart';
import 'voucher_list_screen.dart';

/// Génération d'un lot de tickets.
class GenerateScreen extends StatelessWidget {
  const GenerateScreen({super.key, required this.service, required this.session});

  final MikhmonService service;
  final Session session;

  @override
  Widget build(BuildContext context) {
    return AsyncBody<List<HotspotProfile>>(
      load: service.profiles,
      builder: (context, profiles, reload) {
        if (profiles.isEmpty) {
          return const EmptyList('Aucun profil sur le routeur.\nCréez-en un dans l\'onglet Profils.');
        }
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [_GenerateForm(profiles: profiles, service: service, session: session)],
        );
      },
    );
  }
}

class _GenerateForm extends StatefulWidget {
  const _GenerateForm({required this.profiles, required this.service, required this.session});

  final List<HotspotProfile> profiles;
  final MikhmonService service;
  final Session session;

  @override
  State<_GenerateForm> createState() => _GenerateFormState();
}

class _GenerateFormState extends State<_GenerateForm> {
  final _formKey = GlobalKey<FormState>();
  final _count = TextEditingController(text: '10');
  final _prefix = TextEditingController();
  final _limit = TextEditingController();
  String? _limitFor;
  String? _profileName;
  int _length = 6;
  bool _separate = false;
  CodeCharset _charset = CodeCharset.digits;
  bool _busy = false;
  int _done = 0;
  int _total = 0;

  @override
  void dispose() {
    _count.dispose();
    _prefix.dispose();
    _limit.dispose();
    super.dispose();
  }

  HotspotProfile? get _profile {
    for (final p in widget.profiles) {
      if (p.name == _profileName) return p;
    }
    return widget.profiles.isEmpty ? null : widget.profiles.first;
  }

  Future<void> _generate() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = _profile;
    if (profile == null) return;
    final count = int.parse(_count.text.trim());
    setState(() {
      _busy = true;
      _done = 0;
      _total = count;
    });
    try {
      final vouchers = await widget.service.generate(
        GenerateRequest(
          profile: profile,
          count: count,
          prefix: _prefix.text.trim(),
          length: _length,
          separate: _separate,
          charset: _charset,
          timeLimit: _limit.text.trim().toLowerCase(),
        ),
        onProgress: (d, t) {
          if (mounted) setState(() => _done = d);
        },
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VoucherListScreen(
            title: '${vouchers.length} tickets générés',
            vouchers: vouchers,
            session: widget.session,
          ),
        ),
      );
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final currency = widget.session.currency;
    if (profile != null && _limitFor != profile.name) {
      _limitFor = profile.name;
      _limit.text = profile.uptime;
    }
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: profile?.name,
            decoration: const InputDecoration(labelText: 'Profil', border: OutlineInputBorder()),
            items: [
              for (final p in widget.profiles)
                DropdownMenuItem(value: p.name, child: Text(p.name)),
            ],
            onChanged: _busy ? null : (v) => setState(() => _profileName = v),
          ),
          if (profile != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(
                [
                  if (profile.price > 0) formatMoney(profile.price, currency),
                  if (profile.rateLimit.isNotEmpty) 'Débit ${profile.rateLimit}',
                  '${profile.sharedUsers} appareil(s)',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _limit,
            enabled: !_busy,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Limite de temps',
              helperText: '1h = 1 heure, 1d = 1 jour. Le temps démarre à la première '
                  'connexion et se termine à l\'échéance, même après déconnexion. Vide = illimité',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              final t = (v ?? '').trim().toLowerCase();
              return (t.isNotEmpty && !uptimePattern.hasMatch(t)) ? 'Format invalide (ex. 1h, 1d)' : null;
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final t in const ['30m', '1h', '3h', '12h', '1d', '3d', '7d', '30d'])
                ActionChip(
                  label: Text(t),
                  onPressed: _busy ? null : () => setState(() => _limit.text = t),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _count,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Nombre de tickets',
              helperText: 'De 1 à 500',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              final n = int.tryParse((v ?? '').trim());
              return (n == null || n < 1 || n > 500) ? 'Entrez un nombre entre 1 et 500' : null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _prefix,
            enabled: !_busy,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Préfixe (facultatif)',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              return (t.isNotEmpty && !RegExp(r'^[A-Za-z0-9_.\-]+$').hasMatch(t))
                  ? 'Lettres, chiffres, point, tiret ou _ seulement'
                  : null;
            },
          ),
          const SizedBox(height: 16),
          Text('Longueur du code : $_length'),
          Slider(
            value: _length.toDouble(),
            min: 4,
            max: 10,
            divisions: 6,
            label: '$_length',
            onChanged: _busy ? null : (v) => setState(() => _length = v.round()),
          ),
          const SizedBox(height: 8),
          SegmentedButton<CodeCharset>(
            segments: const [
              ButtonSegment(value: CodeCharset.digits, label: Text('123')),
              ButtonSegment(value: CodeCharset.lower, label: Text('abc')),
              ButtonSegment(value: CodeCharset.mixed, label: Text('ab12')),
            ],
            selected: {_charset},
            onSelectionChanged: _busy ? null : (s) => setState(() => _charset = s.first),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Utilisateur et mot de passe distincts'),
            subtitle: const Text('Sinon, un seul code sert aux deux'),
            value: _separate,
            onChanged: _busy ? null : (v) => setState(() => _separate = v),
          ),
          const SizedBox(height: 16),
          if (_busy) ...[
            LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
            const SizedBox(height: 8),
            Text('Création : $_done / $_total', textAlign: TextAlign.center),
          ] else
            FilledButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Générer les tickets'),
            ),
        ],
      ),
    );
  }
}
