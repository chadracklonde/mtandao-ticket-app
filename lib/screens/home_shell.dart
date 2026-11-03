import 'package:flutter/material.dart';

import '../models.dart';
import '../services/mikhmon_service.dart';
import 'active_screen.dart';
import 'generate_screen.dart';
import 'profiles_screen.dart';
import 'sales_screen.dart';
import 'vouchers_screen.dart';

/// Écran principal d'une session : navigation en bas.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.session, required this.service});

  final Session session;
  final MikhmonService service;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _titles = ['Générer', 'Lots', 'Actifs', 'Ventes', 'Profils'];
  int _index = 0;
  final Set<int> _visited = {0};

  Widget _page(int i) {
    switch (i) {
      case 0:
        return GenerateScreen(service: widget.service, session: widget.session);
      case 1:
        return VouchersScreen(service: widget.service, session: widget.session);
      case 2:
        return ActiveScreen(service: widget.service);
      case 3:
        return SalesScreen(service: widget.service, session: widget.session);
      default:
        return ProfilesScreen(service: widget.service, session: widget.session);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.session.name),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _titles[_index],
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).appBarTheme.foregroundColor,
                  ),
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < _titles.length; i++)
            _visited.contains(i) ? _page(i) : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _index = i;
          _visited.add(i);
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.confirmation_number_outlined), label: 'Générer'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Lots'),
          NavigationDestination(icon: Icon(Icons.wifi), label: 'Actifs'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Ventes'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Profils'),
        ],
      ),
    );
  }
}
