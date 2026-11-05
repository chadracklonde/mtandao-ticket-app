import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_lock.dart';
import '../services/biometric.dart';
import '../services/live_notification.dart';
import '../services/stock_alert.dart';
import '../util.dart';
import '../widgets/desktop.dart';

/// Code de verrouillage de l'application et seuil d'alerte de stock.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key, this.session, this.biometrics = const DeviceBiometricAuth()});

  final BiometricAuth biometrics;

  /// Routeur courant : permet d'activer la notification permanente.
  final Session? session;

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final _lock = AppLock();
  final _stock = StockAlertStore();
  bool _loaded = false;
  bool _enabled = false;
  int _threshold = StockAlertStore.defaultThreshold;
  bool _live = false;
  bool _bioAvailable = false;
  bool _bio = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final on = await _lock.isEnabled();
    final th = await _stock.load();
    final liveId = await LiveNotification.enabledFor();
    final bioAvail = await widget.biometrics.isAvailable();
    final bio = await _lock.biometricEnabled();
    if (mounted) {
      setState(() {
        _enabled = on;
        _threshold = th;
        _live = liveId != null && liveId == widget.session?.id;
        _bioAvailable = bioAvail;
        _bio = bio;
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

  Future<void> _toggleBio(bool on) async {
    if (on && !await widget.biometrics.authenticate('Confirmez avec votre empreinte')) {
      if (mounted) showMessage(context, 'Empreinte non reconnue : réglage inchangé.');
      return;
    }
    await _lock.setBiometricEnabled(on);
    if (mounted) setState(() => _bio = on);
  }

  Future<void> _disable() async {
    final pin = await _askPin('Entrez votre code pour désactiver');
    if (pin == null) return;
    if (await _lock.verify(pin)) {
      await _lock.disable();
      if (mounted) {
        setState(() {
          _enabled = false;
          _bio = false;
        });
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
        if (_enabled && _bioAvailable)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Déverrouiller par empreinte'),
            subtitle: const Text('Le code reste toujours possible.'),
            value: _bio,
            onChanged: _toggleBio,
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
        if (widget.session != null && LiveNotification.supported) ...[
          const SizedBox(height: 24),
          Text('Notification permanente', style: t.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Garde dans la barre de notifications les ventes du jour, le nombre d\'appareils connectés '
            'et les profils à court de tickets, mis à jour chaque minute, même application fermée. '
            'Elle consomme un peu de batterie et de données. Le même texte peut s\'afficher sur l\'écran '
            'd\'accueil : appuyez longuement sur l\'écran, choisissez Widgets, puis Mtandao Ticket.',
            style: t.bodySmall,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Afficher pour « ${widget.session!.name} »'),
            value: _live,
            onChanged: _toggleLive,
          ),
        ],
      ],
    ));
  }

  Future<void> _toggleLive(bool on) async {
    if (on) {
      final err = await LiveNotification.enable(widget.session!);
      if (!mounted) return;
      if (err != null) {
        showMessage(context, err);
        return;
      }
    } else {
      await LiveNotification.disable();
    }
    if (mounted) setState(() => _live = on);
  }

  Future<void> _setThreshold(int v) async {
    setState(() => _threshold = v);
    await _stock.save(v);
  }
}
