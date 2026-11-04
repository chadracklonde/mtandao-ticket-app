import 'package:flutter/material.dart';

import '../models.dart';
import '../services/mikhmon_service.dart';
import '../util.dart';
import '../widgets/async_body.dart';
import '../widgets/extend_dialog.dart';

enum UserFilter { all, fresh, used, exhausted, disabled }

extension on UserFilter {
  String get label => switch (this) {
        UserFilter.all => 'Tous',
        UserFilter.fresh => 'Neufs',
        UserFilter.used => 'Utilisés',
        UserFilter.exhausted => 'Épuisés',
        UserFilter.disabled => 'Désactivés',
      };

  bool accepts(HotspotUser u) => switch (this) {
        UserFilter.all => true,
        UserFilter.fresh => u.isNew && !u.disabled,
        UserFilter.used => u.isUsed,
        UserFilter.exhausted => u.isExhausted,
        UserFilter.disabled => u.disabled,
      };
}

/// Tous les utilisateurs du hotspot : recherche, filtres, détail et actions.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key, required this.service, required this.session});

  final MikhmonService service;
  final Session session;

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  int _generation = 0;
  String _query = '';
  UserFilter _filter = UserFilter.all;

  void _reload() => setState(() => _generation++);

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    try {
      await action();
      if (!mounted) return;
      _reload();
      if (done != null) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    }
  }

  Future<void> _extend(HotspotUser u) async {
    final ask = await askExtension(context, u);
    if (ask == null) return;
    await _run(
      () => widget.service.extendUser(u, addTime: ask.time, addBytes: ask.bytes),
      done: 'Ticket prolongé',
    );
  }

  Future<void> _confirmDelete(HotspotUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce ticket ?'),
        content: Text('${u.name} sera supprimé du routeur.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok == true) await _run(() => widget.service.removeUser(u.id), done: 'Ticket supprimé');
  }

  void _detail(HotspotUser u) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _UserDetail(
        user: u,
        onToggle: () {
          Navigator.pop(ctx);
          _run(() => widget.service.setUserDisabled(u.id, !u.disabled),
              done: u.disabled ? 'Ticket réactivé' : 'Ticket désactivé');
        },
        onReset: () {
          Navigator.pop(ctx);
          _run(() => widget.service.resetUserCounters(u.id), done: 'Compteurs remis à zéro');
        },
        onExtend: () {
          Navigator.pop(ctx);
          _extend(u);
        },
        onDelete: () {
          Navigator.pop(ctx);
          _confirmDelete(u);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<List<HotspotUser>>(
      key: ValueKey(_generation),
      load: widget.service.hotspotUsers,
      builder: (context, users, reload) {
        final q = _query.trim().toLowerCase();
        final shown = users
            .where((u) =>
                _filter.accepts(u) &&
                (q.isEmpty ||
                    u.name.toLowerCase().contains(q) ||
                    u.profile.toLowerCase().contains(q) ||
                    u.comment.toLowerCase().contains(q)))
            .toList();
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                autocorrect: false,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Rechercher un ticket, un profil, un lot',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final f in UserFilter.values)
                    ChoiceChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('${shown.length} sur ${users.length} utilisateur(s)',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Aucun utilisateur ne correspond.')),
              ),
            for (final u in shown)
              ListTile(
                title: Text(u.name,
                    style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                subtitle: Text(_summary(u)),
                trailing: _statusChip(context, u),
                onTap: () => _detail(u),
              ),
          ],
        );
      },
    );
  }

  static String _summary(HotspotUser u) => [
        u.profile,
        if (u.limitUptime != null) 'reste ${formatDuration(u.timeLeft!)}',
        if (u.limitBytes > 0) 'reste ${dataLimitLabel(u.bytesLeft!)}',
      ].join(' · ');

  static Widget _statusChip(BuildContext context, HotspotUser u) {
    final (text, color) = u.disabled
        ? ('Désactivé', Colors.grey)
        : u.isExhausted
            ? ('Épuisé', const Color(0xFFC63D2F))
            : u.isNew
                ? ('Neuf', const Color(0xFF0F5FD0))
                : u.isUsed
                    ? ('Utilisé', const Color(0xFF17784E))
                    : ('—', Colors.grey);
    return Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600));
  }
}

class _UserDetail extends StatelessWidget {
  const _UserDetail({
    required this.user,
    required this.onToggle,
    required this.onReset,
    required this.onExtend,
    required this.onDelete,
  });

  final HotspotUser user;
  final VoidCallback onToggle;
  final VoidCallback onReset;
  final VoidCallback onExtend;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(u.name, style: t.headlineSmall?.copyWith(fontFamily: 'monospace')),
            const SizedBox(height: 4),
            Text([
              u.profile,
              if (u.password.isNotEmpty && u.password != u.name) 'mot de passe ${u.password}',
              if (u.comment.isNotEmpty) u.comment,
            ].join(' · ')),
            const SizedBox(height: 16),
            Text('Temps', style: t.titleSmall),
            const SizedBox(height: 4),
            if (u.limitUptime == null)
              Text('Utilisé ${formatDuration(u.uptime)} · illimité')
            else ...[
              LinearProgressIndicator(
                value: (u.uptime.inSeconds / u.limitUptime!.inSeconds).clamp(0.0, 1.0),
              ),
              const SizedBox(height: 4),
              Text('Utilisé ${formatDuration(u.uptime)} sur ${formatDuration(u.limitUptime!)} '
                  '· reste ${formatDuration(u.timeLeft!)}'),
            ],
            const SizedBox(height: 16),
            Text('Données', style: t.titleSmall),
            const SizedBox(height: 4),
            if (u.limitBytes <= 0)
              Text('Utilisées ${formatBytes(u.bytesTotal)} · illimitées')
            else ...[
              LinearProgressIndicator(value: (u.bytesTotal / u.limitBytes).clamp(0.0, 1.0)),
              const SizedBox(height: 4),
              Text('Utilisées ${formatBytes(u.bytesTotal)} sur ${dataLimitLabel(u.limitBytes)} '
                  '· reste ${dataLimitLabel(u.bytesLeft!)}'),
            ],
            const SizedBox(height: 4),
            Text('Reçues ${formatBytes(u.bytesIn)} · envoyées ${formatBytes(u.bytesOut)}',
                style: t.bodySmall),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onExtend,
                  icon: const Icon(Icons.more_time),
                  label: const Text('Prolonger'),
                ),
                OutlinedButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Remettre à zéro'),
                ),
                OutlinedButton.icon(
                  onPressed: onToggle,
                  icon: Icon(u.disabled ? Icons.check_circle_outline : Icons.block),
                  label: Text(u.disabled ? 'Réactiver' : 'Désactiver'),
                ),
                OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Supprimer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
