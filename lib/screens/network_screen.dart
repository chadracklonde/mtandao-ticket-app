import 'package:flutter/material.dart';

import '../models.dart';
import '../services/mikhmon_service.dart';
import '../util.dart';
import '../widgets/async_body.dart';
import '../widgets/desktop.dart';

class _NetData {
  _NetData(this.shared, this.network, this.connLimit);
  final SharedBandwidth? shared;
  final String? network;
  final int? connLimit;
}

/// Vitesse et équité : enveloppe de bande passante commune et limite de
/// connexions par appareil.
class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key, required this.service});

  final MikhmonService service;

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  final _down = TextEditingController();
  final _up = TextEditingController();
  final _target = TextEditingController();
  final _conn = TextEditingController(text: '300');
  bool _filled = false;
  bool _busy = false;

  @override
  void dispose() {
    _down.dispose();
    _up.dispose();
    _target.dispose();
    _conn.dispose();
    super.dispose();
  }

  Future<_NetData> _load() async {
    final shared = await widget.service.sharedBandwidth();
    String? network;
    try {
      network = await widget.service.detectHotspotNetwork();
    } catch (_) {}
    final conn = await widget.service.connectionLimit();
    _filled = false;
    return _NetData(shared, network, conn);
  }

  Future<void> _run(Future<void> Function() action, Future<void> Function() reload, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      await reload();
      if (mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AsyncBody<_NetData>(
      load: _load,
      builder: (context, d, reload) {
        if (!_filled) {
          _filled = true;
          _down.text = d.shared == null ? '' : '${d.shared!.downBits ~/ 1000000}';
          _up.text = d.shared == null ? '' : '${d.shared!.upBits ~/ 1000000}';
          _target.text = d.shared?.target ?? d.network ?? '';
          if (d.connLimit != null) _conn.text = '${d.connLimit}';
        }
        return ContentWidth(
          maxWidth: 760,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text('Bande passante partagée', style: t.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Indiquez la vitesse réelle de votre connexion (Starlink, fibre…). Tous les profils '
                'se partagent alors cette enveloppe : un gros téléchargement ne peut plus écraser '
                'les autres clients, surtout avec un débit minimum garanti dans les profils.',
                style: t.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _down,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Réception totale (Mb/s)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _up,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Envoi total (Mb/s)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _target,
                enabled: !_busy,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Réseau des clients',
                  helperText: d.network == null
                      ? 'Ex. 10.5.50.0/24'
                      : 'Détecté sur le routeur : ${d.network}',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(
                              () => widget.service.enableSharedBandwidth(
                                downMbps: int.tryParse(_down.text.trim()) ?? 0,
                                upMbps: int.tryParse(_up.text.trim()) ?? 0,
                                target: _target.text,
                              ),
                              reload,
                              'Enveloppe appliquée à tous les profils.',
                            ),
                    icon: const Icon(Icons.speed),
                    label: Text(d.shared == null ? 'Activer' : 'Mettre à jour'),
                  ),
                  if (d.shared != null)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _run(widget.service.disableSharedBandwidth, reload, 'Enveloppe retirée.'),
                      child: const Text('Désactiver'),
                    ),
                ],
              ),
              if (d.shared != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Actif : ${d.shared!.downBits ~/ 1000000} Mb/s en réception, '
                    '${d.shared!.upBits ~/ 1000000} Mb/s en envoi.',
                    style: t.bodySmall,
                  ),
                ),
              const Divider(height: 40),
              Text('Connexions par appareil', style: t.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Limite le nombre de connexions simultanées d\'un même appareil. Les logiciels de '
                'téléchargement par torrent en ouvrent des centaines et ralentissent tout le monde ; '
                'la navigation normale en utilise bien moins.',
                style: t.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _conn,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Connexions maximales par appareil',
                  helperText: 'Entre 20 et 5000. 300 convient à la plupart des usages.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(
                              () => widget.service.setConnectionLimit(int.tryParse(_conn.text.trim()) ?? 0),
                              reload,
                              'Limite appliquée.',
                            ),
                    icon: const Icon(Icons.lan_outlined),
                    label: Text(d.connLimit == null ? 'Activer' : 'Mettre à jour'),
                  ),
                  if (d.connLimit != null)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() => widget.service.setConnectionLimit(null), reload, 'Limite retirée.'),
                      child: const Text('Désactiver'),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Réglages par profil (Plus > Profils) : vitesse maximale, départ rapide, débit '
                'minimum garanti, et liaison du ticket au premier appareil.',
                style: t.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}
