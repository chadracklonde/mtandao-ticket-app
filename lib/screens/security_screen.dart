import 'package:flutter/material.dart';

import '../services/app_lock.dart';
import '../services/stock_alert.dart';
import '../util.dart';
import '../widgets/desktop.dart';

/// Code de verrouillage de l'application et seuil d'alerte de stock.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final _lock = AppLock();
  final _stock = StockAlertStore();
  bool _loaded = false;
  bool _enabled = false;
  int _threshold = StockAlertStore.defaultThreshold;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final on = await _lock.isEnabled();
    final th = await _stock.load();
    if (mounted) {
      setState(() {
        _enabled = on;
        _threshold = th;
        _loaded = true;
      });
    }
  }

  Future<String?> _askPin(String title, {String? confirmLabel}) async {
    final first = TextEditingController();
    final second = TextEditingController();
    final key = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: first,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: const InputDecoration(labelText: 'Code (4 à 8 chiffres)', counterText: ''),
                validator: (v) => AppLock.validPin(v ?? '') ? null : '4 à 8 chiffres',
              ),
              if (confirmLabel != null)
                TextFormField(
                  controller: second,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  decoration: InputDecoration(labelText: confirmLabel, counterText: ''),
                  validator: (v) => v == first.text ? null : 'Les deux codes sont différents',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) Navigator.pop(ctx, first.text);
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    first.dispose();
    second.dispose();
    return result;
  }

  Future<void> _enable() async {
    final pin = await _askPin('Choisir un code', confirmLabel: 'Confirmer le code');
    if (pin == null) return;
    await _lock.setPin(pin);
    if (mounted) {
      setState(() => _enabled = true);
      showMessage(context, 'Verrouillage activé');
    }
  }

  Future<void> _disable() async {
    final pin = await _askPin('Entrez votre code pour désactiver');
    if (pin == null) return;
    if (await _lock.verify(pin)) {
      await _lock.disable();
      if (mounted) {
        setState(() => _enabled = false);
        showMessage(context, 'Verrouillage désactivé');
      }
    } else if (mounted) {
      showMessage(context, 'Code incorrect.');
    }
  }

  Future<void> _change() async {
    final old = await _askPin('Code actuel');
    if (old == null) return;
    if (!await _lock.verify(old)) {
      if (mounted) showMessage(context, 'Code incorrect.');
      return;
    }
    final pin = await _askPin('Nouveau code', confirmLabel: 'Confirmer le nouveau code');
    if (pin == null) return;
    await _lock.setPin(pin);
    if (mounted) showMessage(context, 'Code modifié');
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final t = Theme.of(context).textTheme;
    return ContentWidth(maxWidth: 760, child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Verrouillage', style: t.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Demande un code à l\'ouverture de l\'application et quand elle est restée '
          'en arrière-plan plus de 30 secondes. Le code protège l\'accès à vos routeurs et à vos ventes.',
          style: t.bodySmall,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Verrouiller par un code'),
          value: _enabled,
          onChanged: (v) => v ? _enable() : _disable(),
        ),
        if (_enabled)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.password),
            title: const Text('Changer le code'),
            onTap: _change,
          ),
        const SizedBox(height: 24),
        Text('Alerte de stock', style: t.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Un avertissement s\'affiche dans « Générer » quand il reste moins de tickets neufs '
          'que ce seuil pour un profil. 0 : pas d\'alerte.',
          style: t.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: _threshold > 0 ? () => _setThreshold(_threshold - 5 < 0 ? 0 : _threshold - 5) : null,
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Text(_threshold == 0 ? 'Désactivée' : 'Moins de $_threshold tickets',
                  textAlign: TextAlign.center, style: t.titleSmall),
            ),
            IconButton.filledTonal(
              onPressed: () => _setThreshold(_threshold + 5),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    ));
  }

  Future<void> _setThreshold(int v) async {
    setState(() => _threshold = v);
    await _stock.save(v);
  }
}
