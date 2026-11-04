import 'package:flutter/material.dart';

import '../models.dart';
import '../services/mikhmon_service.dart';
import '../widgets/desktop.dart';
import 'active_screen.dart';
import 'dashboard_screen.dart';
import 'generate_screen.dart';
import 'plus_screen.dart';
import 'sales_screen.dart';
import 'vouchers_screen.dart';

/// Écran principal d'une session.
/// Téléphone : navigation en bas. Ordinateur : barre latérale à gauche et
/// contenu large à droite (les écrans secondaires s'ouvrent dans le contenu).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.session, required this.service});

  final Session session;
  final MikhmonService service;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _titles = ['Accueil', 'Générer', 'Lots', 'Actifs', 'Ventes', 'Plus'];
  static const _icons = [
    Icons.dashboard_outlined,
    Icons.confirmation_number_outlined,
    Icons.inventory_2_outlined,
    Icons.wifi,
    Icons.bar_chart,
    Icons.more_horiz,
  ];
  final _index = ValueNotifier<int>(0);
  final Set<int> _visited = {0};
  final _paneNavigator = GlobalKey<NavigatorState>();

  @override
  void dispose() {
    _index.dispose();
    super.dispose();
  }

  Widget _page(int i) {
    switch (i) {
      case 0:
        return DashboardScreen(service: widget.service, session: widget.session);
      case 1:
        return GenerateScreen(service: widget.service, session: widget.session);
      case 2:
        return VouchersScreen(service: widget.service, session: widget.session);
      case 3:
        return ActiveScreen(service: widget.service);
      case 4:
        return SalesScreen(service: widget.service, session: widget.session);
      default:
        return PlusScreen(service: widget.service, session: widget.session);
    }
  }

  Widget _stack() => ValueListenableBuilder<int>(
        valueListenable: _index,
        builder: (context, index, _) => IndexedStack(
          index: index,
          children: [
            for (var i = 0; i < _titles.length; i++)
              _visited.contains(i) ? _page(i) : const SizedBox.shrink(),
          ],
        ),
      );

  void _select(int i) {
    _paneNavigator.currentState?.popUntil((r) => r.isFirst);
    _visited.add(i);
    _index.value = i;
  }

  @override
  Widget build(BuildContext context) =>
      isDesktopPlatform ? _desktop(context) : _phone(context);

  // ── Téléphone (inchangé) ────────────────────────────────────────────────
  Widget _phone(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _index,
      builder: (context, index, _) => Scaffold(
        appBar: AppBar(
          title: Text(widget.session.name),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(20),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _titles[index],
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).appBarTheme.foregroundColor,
                    ),
              ),
            ),
          ),
        ),
        body: _stack(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => setState(() => _select(i)),
          destinations: [
            for (var i = 0; i < _titles.length; i++)
              NavigationDestination(icon: Icon(_icons[i]), label: _titles[i]),
          ],
        ),
      ),
    );
  }

  // ── Ordinateur ──────────────────────────────────────────────────────────
  Widget _desktop(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Row(
        children: [
          ValueListenableBuilder<int>(
            valueListenable: _index,
            builder: (context, index, _) => SizedBox(
              width: 248,
              child: Material(
                color: scheme.surfaceContainerLow,
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 16, 16),
                    child: Row(
                      children: [
                        Image.asset('assets/brand/logo.png', width: 40, height: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.session.name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium),
                              Text(widget.session.host,
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (var i = 0; i < _titles.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: ListTile(
                              key: ValueKey('nav-${_titles[i]}'),
                              selected: i == index,
                              selectedTileColor: scheme.primaryContainer,
                              selectedColor: scheme.onPrimaryContainer,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              leading: Icon(_icons[i]),
                              title: Text(_titles[i]),
                              onTap: () => setState(() => _select(i)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      leading: const Icon(Icons.swap_horiz),
                      title: const Text('Changer de routeur'),
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ],
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Navigator(
              key: _paneNavigator,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => ValueListenableBuilder<int>(
                  valueListenable: _index,
                  builder: (context, index, _) => Scaffold(
                    appBar: AppBar(
                      automaticallyImplyLeading: false,
                      title: Text(_titles[index]),
                    ),
                    body: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: _stack(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
