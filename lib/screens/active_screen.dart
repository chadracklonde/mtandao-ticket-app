import 'package:flutter/material.dart';

import '../models.dart';
import '../services/mikhmon_service.dart';
import '../util.dart';
import '../widgets/async_body.dart';

/// Utilisateurs actuellement connectés.
class ActiveScreen extends StatefulWidget {
  const ActiveScreen({super.key, required this.service});

  final MikhmonService service;

  @override
  State<ActiveScreen> createState() => _ActiveScreenState();
}

class _ActiveScreenState extends State<ActiveScreen> {
  int _generation = 0;

  Future<void> _kick(BuildContext context, ActiveUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déconnecter cet utilisateur ?'),
        content: Text('${u.user} (${u.address}) sera déconnecté du hotspot.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Déconnecter')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.service.disconnect(u.id);
      if (mounted) setState(() => _generation++);
    } catch (e) {
      if (context.mounted) showMessage(context, describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<List<ActiveUser>>(
      key: ValueKey(_generation),
      load: widget.service.activeUsers,
      builder: (context, users, reload) {
        if (users.isEmpty) {
          return const EmptyList('Personne n\'est connecté pour le moment.\nTirez vers le bas pour actualiser.');
        }
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: users.length + 1,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text('${users.length} utilisateur(s) connecté(s)',
                    style: Theme.of(context).textTheme.titleMedium),
              );
            }
            final u = users[i - 1];
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(u.user),
              subtitle: Text(
                '${u.address} · ${u.mac}\n'
                'Durée ${u.uptime} · ↓ ${formatBytes(u.bytesOut)} ↑ ${formatBytes(u.bytesIn)}',
              ),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: 'Déconnecter',
                icon: const Icon(Icons.logout),
                onPressed: () => _kick(context, u),
              ),
            );
          },
        );
      },
    );
  }
}
