import 'package:flutter/material.dart';

import '../models.dart';
import '../services/mikhmon_service.dart';
import '../widgets/desktop.dart';
import 'backup_screen.dart';
import 'monitor_screen.dart';
import 'profiles_screen.dart';
import 'security_screen.dart';
import 'ticket_layout_screen.dart';
import 'users_screen.dart';

/// Onglet « Plus » : tout ce qui n'est pas dans la barre du bas.
class PlusScreen extends StatelessWidget {
  const PlusScreen({super.key, required this.service, required this.session});

  final MikhmonService service;
  final Session session;

  void _open(BuildContext context, String title, Widget body) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(appBar: AppBar(title: Text(title)), body: body),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, String title, String subtitle, String screenTitle, Widget Function() body) =>
        ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, screenTitle, body()),
        );

    final items = <(IconData, String, String, String, Widget Function())>[
      (Icons.tune, 'Profils', 'Prix, limites de temps et de données, vitesse', 'Profils',
          () => ProfilesScreen(service: service, session: session)),
      (Icons.people_outline, 'Utilisateurs', 'Tous les tickets : consommation, prolonger, désactiver',
          'Utilisateurs', () => UsersScreen(service: service, session: session)),
      (Icons.print_outlined, 'Mise en page du ticket', 'Colonnes, logo, rouleau 58/80 mm, aperçu',
          'Mise en page du ticket', () => TicketLayoutScreen(session: session)),
      (Icons.monitor_heart_outlined, 'Surveillance', 'Processeur, mémoire, trafic en direct',
          'Surveillance', () => MonitorScreen(service: service)),
      (Icons.devices_outlined, 'Appareils (DHCP)', 'Les appareils connus du routeur', 'Appareils',
          () => LeasesScreen(service: service)),
      (Icons.receipt_long_outlined, 'Journal', 'Événements du routeur', 'Journal',
          () => LogScreen(service: service)),
      (Icons.backup_outlined, 'Sauvegarde', 'Profils et sauvegarde du routeur', 'Sauvegarde',
          () => BackupScreen(service: service, session: session)),
      (Icons.lock_outline, 'Sécurité et alertes', 'Code de verrouillage, stock bas', 'Sécurité et alertes',
          () => const SecurityScreen()),
    ];

    if (isDesktopPlatform) {
      // Ordinateur : cartes en grille.
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final it in items)
              SizedBox(
                width: 340,
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _open(context, it.$4, it.$5()),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(it.$1, size: 32),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(it.$2, style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 4),
                                Text(it.$3, style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Téléphone : liste (inchangée).
    return ListView(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i == 3 || i == 6) const Divider(),
          tile(items[i].$1, items[i].$2, items[i].$3, items[i].$4, items[i].$5),
        ],
      ],
    );
  }
}
