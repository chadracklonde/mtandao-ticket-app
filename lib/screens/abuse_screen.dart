import 'package:flutter/material.dart';

import '../models.dart';
import '../services/insights.dart';
import '../services/mikhmon_service.dart';
import '../util.dart';
import '../widgets/async_body.dart';
import '../widgets/desktop.dart';

class _AbuseData {
  _AbuseData(this.active, this.blocked);
  final List<ActiveUser> active;
  final List<BlockedDevice> blocked;
}

/// Tickets partagés, gros consommateurs et appareils bloqués.
class AbuseScreen extends StatelessWidget {
  const AbuseScreen({super.key, required this.service});

  final MikhmonService service;

  Future<_AbuseData> _load() async {
    final active = await service.activeUsers();
    final blocked = await service.blockedDevices();
    return _AbuseData(active, blocked);
  }

  Future<void> _run(BuildContext context, Future<void> Function() action, Future<void> Function() reload,
      String done) async {
    try {
      await action();
      await reload();
      if (context.mounted) showMessage(context, done);
    } catch (e) {
      if (context.mounted) showMessage(context, describeError(e));
    }
  }

  Future<void> _askMac(BuildContext context, Future<void> Function() reload) async {
    final c = TextEditingController();
    final key = GlobalKey<FormState>();
    final mac = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bloquer un appareil'),
        content: Form(
          key: key,
          child: TextFormField(
            controller: c,
            autofocus: true,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Adresse MAC',
              hintText: 'AA:BB:CC:11:22:33',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                macPattern.hasMatch((v ?? '').trim().toUpperCase()) ? null : 'Adresse MAC invalide',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) Navigator.pop(ctx, c.text.trim());
            },
            child: const Text('Bloquer'),
          ),
        ],
      ),
    );
    if (mac == null || !context.mounted) return;
    await _run(context, () => service.blockDevice(mac), reload, 'Appareil bloqué.');
  }

  Future<bool> _confirm(BuildContext context, String text, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AsyncBody<_AbuseData>(
      load: _load,
      builder: (context, data, reload) {
        final alerts = detectAbuse(data.active, format: formatBytes);
        return ContentWidth(
          maxWidth: 820,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text('À surveiller', style: t.titleMedium),
              const SizedBox(height: 8),
              if (alerts.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.check_circle_outline, color: Colors.green),
                    title: Text('Rien d\'anormal'),
                    subtitle: Text('Aucun ticket partagé ni gros consommateur parmi les connectés.'),
                  ),
                ),
              for (final a in alerts)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(a.kind == AbuseKind.sharedTicket ? Icons.people_alt_outlined : Icons.speed,
                              color: Colors.orange.shade800),
                          const SizedBox(width: 8),
                          Expanded(child: Text(a.user, style: t.titleSmall)),
                        ]),
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 4),
                          child: Text(a.detail),
                        ),
                        for (final s in a.sessions)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(s.mac.isEmpty ? s.address : '${s.mac} · ${s.address}'),
                            subtitle: Text('${s.uptime} · ${formatBytes(s.bytesIn + s.bytesOut)}'),
                            trailing: Wrap(
                              children: [
                                IconButton(
                                  tooltip: 'Déconnecter',
                                  icon: const Icon(Icons.link_off),
                                  onPressed: () => _run(context, () => service.disconnect(s.id), reload,
                                      'Session coupée.'),
                                ),
                                if (s.mac.isNotEmpty)
                                  IconButton(
                                    tooltip: 'Bloquer cet appareil',
                                    icon: const Icon(Icons.block),
                                    onPressed: () async {
                                      if (await _confirm(context,
                                          'Bloquer l\'appareil ${s.mac} ? Il ne pourra plus se connecter au hotspot.',
                                          'Bloquer')) {
                                        if (context.mounted) {
                                          await _run(context, () => service.blockDevice(s.mac, note: a.user),
                                              reload, 'Appareil bloqué.');
                                        }
                                      }
                                    },
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: Text('Appareils bloqués', style: t.titleMedium)),
                  TextButton.icon(
                    onPressed: () => _askMac(context, reload),
                    icon: const Icon(Icons.add),
                    label: const Text('Bloquer une adresse'),
                  ),
                ],
              ),
              if (data.blocked.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Aucun appareil bloqué.'),
                ),
              for (final b in data.blocked)
                ListTile(
                  leading: const Icon(Icons.block),
                  title: Text(b.mac),
                  subtitle: b.comment.isEmpty ? null : Text(b.comment),
                  trailing: TextButton(
                    onPressed: () => _run(context, () => service.unblockDevice(b.id), reload, 'Appareil débloqué.'),
                    child: const Text('Débloquer'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
