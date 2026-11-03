import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/file_delivery.dart';
import '../services/mikhmon_service.dart';
import '../services/profile_backup.dart';
import '../util.dart';

/// Sauvegarde et restauration des profils ; sauvegarde du routeur.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, required this.service, required this.session});

  final MikhmonService service;
  final Session session;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  Future<void> _guard(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportProfiles() => _guard(() async {
        final json = await widget.service.exportProfiles();
        final d = DateTime.now();
        final clean = widget.session.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
        final name = 'profils-$clean-${d.year}${two(d.month)}${two(d.day)}.json';
        final path = await deliverFile(Uint8List.fromList(utf8.encode(json)), name, mimeType: 'application/json');
        if (path != null && mounted) showMessage(context, 'Enregistré : $path');
      });

  Future<void> _restoreProfiles() => _guard(() async {
        const jsonType = XTypeGroup(
          label: 'Sauvegarde de profils',
          extensions: ['json'],
          mimeTypes: ['application/json'],
          uniformTypeIdentifiers: ['public.json'],
        );
        final picked = await openFile(acceptedTypeGroups: const [jsonType]);
        if (picked == null) return;
        final bytes = await picked.readAsBytes();
        final profiles = profilesFromJson(utf8.decode(bytes));
        if (profiles.isEmpty) {
          if (mounted) showMessage(context, 'Cette sauvegarde ne contient aucun profil.');
          return;
        }
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Restaurer les profils ?'),
            content: Text('${profiles.length} profil(s) : ${profiles.map((p) => p.name).join(', ')}.\n\n'
                'Ceux qui existent déjà sur ce routeur seront remplacés.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restaurer')),
            ],
          ),
        );
        if (ok != true) return;
        final r = await widget.service.restoreProfiles(profiles);
        if (!mounted) return;
        final failed = r.failed.isEmpty ? '' : '\n${r.failed.length} refusé(s) : ${r.failed.keys.join(', ')}';
        showMessage(context, '${r.created} créé(s), ${r.updated} mis à jour.$failed');
      });

  Future<void> _routerBackup() => _guard(() async {
        final name = await widget.service.createRouterBackup();
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Sauvegarde créée'),
            content: Text('Deux fichiers ont été créés sur le routeur :\n'
                '• $name.backup (sauvegarde complète)\n'
                '• $name.rsc (export lisible)\n\n'
                'Pour les copier sur votre ordinateur, ouvrez Winbox puis le menu Files.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Profils', style: t.titleMedium),
        const SizedBox(height: 4),
        Text('Un fichier avec vos profils (prix, limites, vitesse), à garder ou à restaurer sur un autre routeur.',
            style: t.bodySmall),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _exportProfiles,
          icon: const Icon(Icons.upload_file),
          label: const Text('Sauvegarder les profils'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _restoreProfiles,
          icon: const Icon(Icons.download),
          label: const Text('Restaurer des profils'),
        ),
        const SizedBox(height: 28),
        Text('Routeur', style: t.titleMedium),
        const SizedBox(height: 4),
        Text('Crée une sauvegarde complète du routeur, rangée sur le routeur lui-même.', style: t.bodySmall),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _routerBackup,
          icon: const Icon(Icons.router_outlined),
          label: const Text('Sauvegarder le routeur'),
        ),
        if (_busy) ...[
          const SizedBox(height: 20),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }
}
