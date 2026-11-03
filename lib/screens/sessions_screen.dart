import 'package:flutter/material.dart';

import '../models.dart';
import '../routeros/api_client.dart';
import '../services/mikhmon_service.dart';
import '../services/session_store.dart';
import '../util.dart';
import 'home_shell.dart';
import 'session_form.dart';

/// Liste des routeurs enregistrés (équivalent de la page « Sessions » de Mikhmon).
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  final SessionStore _store = SessionStore();
  List<Session> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _store.load();
    if (!mounted) return;
    setState(() {
      _sessions = list;
      _loading = false;
    });
  }

  Future<void> _edit([Session? s]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SessionForm(store: _store, session: s)),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Session s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la connexion ?'),
        content: Text('« ${s.name} » sera retirée de ce téléphone. Le routeur n\'est pas modifié.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok == true) {
      await _store.delete(s.id);
      _load();
    }
  }

  Future<void> _connect(Session s) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    RouterOsClient? client;
    try {
      final c = RouterOsClient(
        host: s.host,
        port: s.port,
        useSsl: s.useSsl,
        verifyCertificate: s.verifyCert,
        username: s.username,
        password: s.password,
      );
      client = c;
      await c.connect();
      if (!mounted) return;
      Navigator.of(context).pop(); // ferme l'indicateur de chargement
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => HomeShell(session: s, service: MikhmonService(c, s))),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        showMessage(context, describeError(e));
      }
    } finally {
      client?.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mtandao Ticket')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau routeur'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Aucun routeur enregistré.\nAjoutez votre MikroTik avec le bouton ci-dessous.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: _sessions.length,
                  itemBuilder: (context, i) {
                    final s = _sessions[i];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.router)),
                      title: Text(s.name),
                      subtitle: Text('${s.host}:${s.port}${s.useSsl ? ' (SSL)' : ''} · ${s.username}'),
                      onTap: () => _connect(s),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) => v == 'edit' ? _edit(s) : _delete(s),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Modifier')),
                          PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
