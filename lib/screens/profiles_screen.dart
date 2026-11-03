import 'package:flutter/material.dart';

import '../models.dart';
import '../services/mikhmon_service.dart';
import '../util.dart';
import '../widgets/async_body.dart';
import 'profile_form_screen.dart';

/// Profils du hotspot : débit, appareils, prix et durée.
class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key, required this.service, required this.session});

  final MikhmonService service;
  final Session session;

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  int _generation = 0;

  Future<void> _edit([HotspotProfile? p]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProfileFormScreen(
          service: widget.service,
          session: widget.session,
          profile: p,
        ),
      ),
    );
    if (saved == true && mounted) setState(() => _generation++);
  }

  Future<void> _remove(HotspotProfile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce profil ?'),
        content: Text('Le profil « ${p.name} » sera supprimé du routeur.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.service.removeProfile(p.id);
      if (mounted) setState(() => _generation++);
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.session.currency;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau profil'),
      ),
      body: AsyncBody<List<HotspotProfile>>(
        key: ValueKey(_generation),
        load: widget.service.profiles,
        builder: (context, profiles, reload) {
          if (profiles.isEmpty) return const EmptyList('Aucun profil.');
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: profiles.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = profiles[i];
              return ListTile(
                title: Text(p.name),
                subtitle: Text([
                  if (p.uptime.isNotEmpty) 'Limite ${p.uptime}',
                  if (p.dataLimit.isNotEmpty) 'Données ${p.dataLimit}',
                  if (p.price > 0) formatMoney(p.price, currency),
                  if (p.rateLimit.isNotEmpty) 'Débit ${p.rateLimit}',
                  '${p.sharedUsers} appareil(s)',
                ].join(' · ')),
                onTap: () => _edit(p),
                trailing: IconButton(
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _remove(p),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
