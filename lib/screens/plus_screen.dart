import 'package:flutter/material.dart';

import '../models.dart';
import '../services/mikhmon_service.dart';
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

    return ListView(
      children: [
        tile(Icons.tune, 'Profils', 'Prix, limites de temps et de données, vitesse', 'Profils',
            () => ProfilesScreen(service: service, session: session)),
        tile(Icons.people_outline, 'Utilisateurs', 'Tous les tickets : consommation, prolonger, désactiver',
            'Utilisateurs', () => UsersScreen(service: service, session: session)),
        tile(Icons.print_outlined, 'Mise en page du ticket', 'Colonnes, logo, rouleau 58/80 mm, aperçu',
            'Mise en page du ticket', () => TicketLayoutScreen(session: session)),
        const Divider(),
        tile(Icons.monitor_heart_outlined, 'Surveillance', 'Processeur, mémoire, trafic en direct',
            'Surveillance', () => MonitorScreen(service: service)),
        tile(Icons.devices_outlined, 'Appareils (DHCP)', 'Les appareils connus du routeur', 'Appareils',
            () => LeasesScreen(service: service)),
        tile(Icons.receipt_long_outlined, 'Journal', 'Événements du routeur', 'Journal',
            () => LogScreen(service: service)),
        const Divider(),
        tile(Icons.backup_outlined, 'Sauvegarde', 'Profils et sauvegarde du routeur', 'Sauvegarde',
            () => BackupScreen(service: service, session: session)),
        tile(Icons.lock_outline, 'Sécurité et alertes', 'Code de verrouillage, stock bas', 'Sécurité et alertes',
            () => const SecurityScreen()),
      ],
    );
  }
}
