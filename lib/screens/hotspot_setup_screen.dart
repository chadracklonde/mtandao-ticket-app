import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/hotspot_setup.dart';
import '../services/mikhmon_service.dart';
import '../services/session_store.dart';
import '../util.dart';
import '../widgets/async_body.dart';
import '../widgets/desktop.dart';

class _Prof {
  _Prof(String name, String price, String uptime)
      : name = TextEditingController(text: name),
        price = TextEditingController(text: price),
        uptime = TextEditingController(text: uptime);
  bool on = true;
  final TextEditingController name;
  final TextEditingController price;
  final TextEditingController uptime;
}

/// Installe un hotspot (wifi zone) sur un routeur MikroTik neuf ou remis à zéro.
class HotspotSetupScreen extends StatefulWidget {
  const HotspotSetupScreen({super.key, required this.service, required this.session, SessionStore? store})
      : _store = store;

  final MikhmonService service;
  final Session session;
  final SessionStore? _store;

  @override
  State<HotspotSetupScreen> createState() => _HotspotSetupScreenState();
}

class _HotspotSetupScreenState extends State<HotspotSetupScreen> {
  String? _lan;
  String? _wan;
  final _address = TextEditingController(text: '10.5.50.1/24');
  final _dnsName = TextEditingController();
  final _dnsServers = TextEditingController(text: '8.8.8.8,1.1.1.1');
  final _password = TextEditingController();
  bool _closeServices = true;
  bool _busy = false;
  int _done = 0;
  int _total = 0;
  bool _prepared = false;
  final List<_Prof> _profiles = [_Prof('1H', '100', '1h'), _Prof('24H', '500', '1d'), _Prof('7J', '2000', '7d')];

  @override
  void dispose() {
    _address.dispose();
    _dnsName.dispose();
    _dnsServers.dispose();
    _password.dispose();
    for (final p in _profiles) {
      p.name.dispose();
      p.price.dispose();
      p.uptime.dispose();
    }
    super.dispose();
  }

  void _prepare(RouterFacts f) {
    if (_prepared) return;
    _prepared = true;
    final names = f.interfaces;
    String? pick(List<String> wanted) {
      for (final w in wanted) {
        if (names.contains(w)) return w;
      }
      return null;
    }

    _lan = pick(['bridge', 'bridge-lan', 'bridge1']) ??
        names.firstWhere((n) => n.startsWith('wlan'), orElse: () => names.length > 1 ? names[1] : names.first);
    _wan = pick(['ether1']);
    if (_wan == _lan) _wan = null;
  }

  String _generatePassword() {
    const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(14, (_) => chars[r.nextInt(chars.length)]).join();
  }

  HotspotSetup _build() => HotspotSetup(
        lanInterface: _lan ?? '',
        wanInterface: _wan ?? '',
        lanAddress: _address.text.trim(),
        dnsName: _dnsName.text.trim(),
        dnsServers: _dnsServers.text.trim().isEmpty ? '8.8.8.8,1.1.1.1' : _dnsServers.text.trim(),
        adminUser: widget.session.username,
        adminPassword: _password.text,
        closeInsecureServices: _closeServices,
        profiles: [
          for (final p in _profiles)
            if (p.on && p.name.text.trim().isNotEmpty)
              SetupProfile(
                name: p.name.text.trim(),
                price: int.tryParse(p.price.text.trim()) ?? 0,
                uptime: p.uptime.text.trim().toLowerCase(),
              ),
        ],
      );

  Future<void> _install(RouterFacts facts, Future<void> Function() reload) async {
    final List<SetupStep> steps;
    try {
      steps = planHotspotSetup(_build(), facts);
    } catch (e) {
      showMessage(context, describeError(e));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Installer le hotspot ?'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Une sauvegarde du routeur est faite d\'abord. Voici ce qui sera modifié :'),
                const SizedBox(height: 8),
                for (var i = 0; i < steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('${i + 1}. ${steps[i].title}'),
                  ),
                const SizedBox(height: 12),
                const Text('Si une étape échoue, ce qui a déjà été créé est retiré. '
                    'Vous pourrez aussi annuler l\'installation ensuite.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Installer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _done = 0;
      _total = steps.length;
    });
    try {
      String backup = '';
      try {
        backup = await widget.service.createRouterBackup();
      } catch (_) {
        // La sauvegarde est une précaution : on continue sans elle.
      }
      await widget.service.runSetup(steps, onProgress: (d, t) {
        if (mounted) setState(() => _done = d);
      });
      if (!mounted) return;
      final newPassword = _password.text;
      if (newPassword.isNotEmpty) {
        final s = widget.session;
        await (widget._store ?? SessionStore()).save(Session(
          id: s.id,
          name: s.name,
          host: s.host,
          port: s.port,
          useSsl: s.useSsl,
          verifyCert: s.verifyCert,
          username: s.username,
          password: newPassword,
          currency: s.currency,
          dnsName: _dnsName.text.trim().isEmpty ? s.dnsName : _dnsName.text.trim(),
        ));
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hotspot installé'),
          content: Text(
            'Le hotspot est actif sur ${_lan ?? ''}.\n\n'
            'Les profils créés sont prêts : générez maintenant vos premiers tickets.\n'
            '${backup.isEmpty ? '' : '\nSauvegarde du routeur : $backup (Winbox > Files).\n'}'
            '${newPassword.isEmpty ? '' : '\nLe mot de passe de ${widget.session.username} a changé et a été enregistré dans l\'application. Notez-le : $newPassword\n'}'
            '\nTestez la page de connexion avec un téléphone avant de vendre.',
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      if (!mounted) return;
      if (newPassword.isNotEmpty) {
        // La connexion en cours doit être rouverte avec le nouveau mot de passe.
        Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
        return;
      }
      await reload();
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
      await reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo(Future<void> Function() reload) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler l\'installation ?'),
        content: const Text('Le hotspot, ses réglages et les profils créés par l\'assistant seront '
            'retirés. Les tickets déjà générés ne sont pas supprimés. Les services désactivés et '
            'le mot de passe ne sont pas rétablis.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Annuler l\'installation')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.service.undoInstall();
      await reload();
      if (mounted) showMessage(context, 'Installation annulée.');
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AsyncBody<RouterFacts>(
      load: () async {
        final f = await widget.service.routerFacts();
        return f;
      },
      builder: (context, f, reload) {
        _prepare(f);
        final existing = f.hotspots.isEmpty ? null : f.hotspots.first;
        return ContentWidth(
          maxWidth: 760,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (existing != null) ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                    title: Text('Un hotspot est déjà actif (${existing['name'] ?? ''})'),
                    subtitle: Text('Interface ${existing['interface'] ?? ''}. L\'assistant sert à '
                        'équiper un routeur qui n\'a pas encore de hotspot.'),
                  ),
                ),
                if (f.hasInstallLog) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _undo(reload),
                    icon: const Icon(Icons.undo),
                    label: const Text('Annuler l\'installation faite par l\'application'),
                  ),
                ],
              ] else ...[
                Text('Nouveau hotspot', style: t.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Pour un routeur MikroTik neuf ou remis à zéro, relié à votre appareil. L\'assistant '
                  'garde l\'adresse actuelle du routeur pour ne pas couper la connexion.',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _lan,
                  decoration: const InputDecoration(
                    labelText: 'Réseau des clients (wifi et prises)',
                    helperText: 'Souvent « bridge » sur la configuration d\'usine',
                    border: OutlineInputBorder(),
                  ),
                  items: [for (final n in f.interfaces) DropdownMenuItem(value: n, child: Text(n))],
                  onChanged: _busy ? null : (v) => setState(() => _lan = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _wan,
                  decoration: InputDecoration(
                    labelText: 'Connexion Internet (Starlink, fibre…)',
                    helperText: f.hasMasquerade
                        ? 'Le partage de connexion existe déjà : facultatif'
                        : 'Obligatoire : le routeur ne partage pas encore Internet',
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('— inchangé —')),
                    for (final n in f.interfaces) DropdownMenuItem<String?>(value: n, child: Text(n)),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _wan = v),
                ),
                const SizedBox(height: 12),
                if (!f.addresses.any((a) => a['interface'] == _lan))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _address,
                      enabled: !_busy,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Adresse du routeur sur ce réseau',
                        helperText: 'Cette interface n\'a pas encore d\'adresse',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Adresse actuelle conservée : '
                      '${f.addresses.firstWhere((a) => a['interface'] == _lan)['address']}',
                      style: t.bodySmall,
                    ),
                  ),
                TextField(
                  controller: _dnsName,
                  enabled: !_busy,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Adresse de la page de connexion (facultatif)',
                    helperText: 'Ex. wifi.local',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _dnsServers,
                  enabled: !_busy,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Serveurs DNS',
                    helperText: 'Par défaut Google et Cloudflare',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Profils à créer', style: t.titleMedium),
                for (final p in _profiles)
                  Row(
                    children: [
                      Checkbox(value: p.on, onChanged: _busy ? null : (v) => setState(() => p.on = v ?? false)),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: p.name,
                          enabled: !_busy && p.on,
                          decoration: const InputDecoration(labelText: 'Nom', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: p.price,
                          enabled: !_busy && p.on,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: 'Prix (${widget.session.currency})', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: p.uptime,
                          enabled: !_busy && p.on,
                          decoration: const InputDecoration(labelText: 'Durée', isDense: true),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
                Text('Sécurité', style: t.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Sur la configuration d\'usine, le compte administrateur n\'a pas de mot de passe et '
                  'les clients du wifi pourraient s\'y connecter. Choisissez un mot de passe solide.',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _password,
                  enabled: !_busy,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Nouveau mot de passe de ${widget.session.username}',
                    helperText: '8 caractères au moins. Vide : inchangé',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: 'Générer',
                      icon: const Icon(Icons.casino_outlined),
                      onPressed: _busy ? null : () => setState(() => _password.text = _generatePassword()),
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Désactiver telnet, ftp et l\'interface web'),
                  subtitle: const Text('Services rarement utiles, souvent attaqués'),
                  value: _closeServices,
                  onChanged: _busy ? null : (v) => setState(() => _closeServices = v),
                ),
                const SizedBox(height: 16),
                if (_busy) ...[
                  LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
                  const SizedBox(height: 8),
                  Text('Installation : $_done / $_total', textAlign: TextAlign.center),
                ] else
                  FilledButton.icon(
                    onPressed: () => _install(f, reload),
                    icon: const Icon(Icons.rocket_launch_outlined),
                    label: const Text('Voir le plan et installer'),
                  ),
                if (f.hasInstallLog) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _busy ? null : () => _undo(reload),
                    icon: const Icon(Icons.undo),
                    label: const Text('Annuler une installation précédente'),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}
