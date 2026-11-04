import 'package:flutter/material.dart';

import '../models.dart';
import '../widgets/desktop.dart';
import '../services/mikhmon_service.dart';
import '../services/speed.dart';
import '../util.dart';

/// Création / modification d'un profil hotspot.
class ProfileFormScreen extends StatefulWidget {
  const ProfileFormScreen({
    super.key,
    required this.service,
    required this.session,
    this.profile,
  });

  final MikhmonService service;
  final Session session;
  final HotspotProfile? profile;

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _rate;
  late final TextEditingController _shared;
  late final TextEditingController _price;
  late final TextEditingController _uptime;
  late final TextEditingController _data;
  late final TextEditingController _minRate;
  late bool _burst;
  late bool _bind;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _name = TextEditingController(text: p?.name ?? '');
    final parts = parseRateLimit(p?.rateLimit ?? '');
    _rate = TextEditingController(text: parts.base);
    _minRate = TextEditingController(text: parts.minimum);
    _burst = parts.burst;
    _bind = p?.bindDevice ?? false;
    _shared = TextEditingController(text: '${p?.sharedUsers ?? 1}');
    _price = TextEditingController(text: p == null || p.price == 0 ? '' : '${p.price}');
    _uptime = TextEditingController(text: p?.uptime ?? '');
    _data = TextEditingController(text: p?.dataLimit ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    _minRate.dispose();
    _shared.dispose();
    _price.dispose();
    _uptime.dispose();
    _data.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.service.saveProfile(HotspotProfile(
        id: widget.profile?.id ?? '',
        name: _name.text.trim(),
        rateLimit: buildRateLimit(RateParts(base: _rate.text, burst: _burst, minimum: _minRate.text)),
        parentQueue: widget.profile?.parentQueue ?? '',
        bindDevice: _bind,
        dataLimit: _data.text.trim().toUpperCase(),
        sharedUsers: int.parse(_shared.text.trim()),
        price: int.tryParse(_price.text.trim()) ?? 0,
        uptime: _uptime.text.trim().toLowerCase(),
      ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, describeError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile == null ? 'Nouveau profil' : 'Modifier le profil'),
      ),
      body: ContentWidth(maxWidth: 720, child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              enabled: !_busy,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Nom du profil', border: OutlineInputBorder()),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'Champ obligatoire';
                if (!safeNamePattern.hasMatch(t)) {
                  return 'Lettres, chiffres, espace, point, tiret ou _ seulement';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _uptime,
              enabled: !_busy,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Limite de temps par défaut',
                helperText: 'Ex. 1h, 1d, 7d. Modifiable à chaque génération. Vide = illimitée',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final t = (v ?? '').trim().toLowerCase();
                return (t.isNotEmpty && !uptimePattern.hasMatch(t)) ? 'Format invalide (ex. 24h)' : null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _price,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Prix de vente (${widget.session.currency})',
                helperText: 'Compté dans le rapport de ventes',
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                return (t.isNotEmpty && int.tryParse(t) == null) ? 'Nombre entier uniquement' : null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _data,
              enabled: !_busy,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Limite de données par défaut',
                helperText: 'Envoyées + reçues, ex. 500M, 1G, 5G. Modifiable à chaque génération. Vide = illimitée',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                return (t.isNotEmpty && parseDataSize(t) == null) ? 'Format invalide (ex. 500M, 1G)' : null;
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final t in const ['100M', '500M', '1G', '2G', '5G'])
                  ActionChip(
                    label: Text(t),
                    onPressed: _busy ? null : () => setState(() => _data.text = t),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _rate,
              enabled: !_busy,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Vitesse maximale (facultatif)',
                helperText: 'Ex. 2M = 2 Mb/s dans les deux sens, ou 1M/5M (envoi/réception). Vide = pleine vitesse',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                return (t.isNotEmpty && !isValidRate(t)) ? 'Format invalide (ex. 2M ou 1M/5M)' : null;
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final t in const ['512k', '1M', '2M', '5M', '10M'])
                  ActionChip(
                    label: Text(t),
                    onPressed: _busy ? null : () => setState(() => _rate.text = t),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Départ rapide'),
              subtitle: const Text('Vitesse doublée pendant les premières secondes : les pages '
                  's\'ouvrent plus vite. Sans effet sans vitesse maximale.'),
              value: _burst,
              onChanged: _busy ? null : (v) => setState(() => _burst = v),
            ),
            TextFormField(
              controller: _minRate,
              enabled: !_busy,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Débit minimum garanti (facultatif)',
                helperText: 'Ex. 256k : chaque client garde au moins ce débit quand le réseau est chargé',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                return (t.isNotEmpty && !isValidRate(t)) ? 'Format invalide (ex. 256k)' : null;
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Lier le ticket au premier appareil'),
              subtitle: const Text('Le ticket ne fonctionne plus que sur l\'appareil qui s\'est '
                  'connecté en premier : impossible de le partager.'),
              value: _bind,
              onChanged: _busy ? null : (v) => setState(() => _bind = v),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _shared,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Appareils simultanés',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                return (n == null || n < 1 || n > 100) ? 'Entre 1 et 100' : null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Text('Enregistrer sur le routeur'),
            ),
          ],
        ),
      )),
    );
  }
}
