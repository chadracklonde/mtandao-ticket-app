import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/cloud_config.dart';
import 'sessions_screen.dart';

class CloudAccessScreen extends StatefulWidget {
  const CloudAccessScreen({super.key});

  @override
  State<CloudAccessScreen> createState() => _CloudAccessScreenState();
}

class _CloudAccessScreenState extends State<CloudAccessScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _creatingAccount = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    setState(() { _busy = true; _error = null; });
    try {
      final auth = CloudConfig.client.auth;
      if (_creatingAccount) {
        final result = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
        );
        if (result.session == null && mounted) {
          setState(() => _error = 'Compte créé. Vérifiez votre adresse e-mail pour confirmer votre inscription.');
        }
      } else {
        await auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Connexion impossible. Vérifiez votre réseau et réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compte Mtandao Cloud')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.cloud_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                _creatingAccount ? 'Créer votre compte' : 'Se connecter à Mtandao Cloud',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username, AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Adresse e-mail', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(labelText: 'Mot de passe', border: OutlineInputBorder()),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy || _email.text.trim().isEmpty || _password.text.length < 8
                    ? null : _authenticate,
                child: Text(_busy ? 'Veuillez patienter…' : (_creatingAccount ? 'Créer le compte' : 'Se connecter')),
              ),
              TextButton(
                onPressed: _busy ? null : () => setState(() { _creatingAccount = !_creatingAccount; _error = null; }),
                child: Text(_creatingAccount ? 'J’ai déjà un compte' : 'Créer un compte'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CloudSitesScreen extends StatefulWidget {
  const CloudSitesScreen({super.key});

  @override
  State<CloudSitesScreen> createState() => _CloudSitesScreenState();
}

class _CloudSitesScreenState extends State<CloudSitesScreen> {
  List<Map<String, dynamic>> _sites = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSites();
  }

  Future<void> _loadSites() async {
    setState(() { _loading = true; _error = null; });
    try {
      final session = CloudConfig.client.auth.currentSession;
      if (session == null) throw StateError('Session expirée. Reconnectez-vous.');
      final response = await http.get(
        CloudConfig.apiBaseUri.resolve('/v1/sites'),
        headers: {'authorization': 'Bearer ${session.accessToken}', 'accept': 'application/json'},
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode == 401) {
        await CloudConfig.client.auth.signOut();
        throw StateError('Votre session a expiré. Veuillez vous reconnecter.');
      }
      if (response.statusCode != 200) {
        throw StateError('Le Cloud a répondu avec le code ${response.statusCode}.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) throw const FormatException('Réponse de sites invalide.');
      final sites = decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (mounted) setState(() => _sites = sites);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectSite(Map<String, dynamic> site) async {
    final id = site['id'];
    if (id is! String || id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mtandao_active_cloud_site_id', id);
    await prefs.setString('mtandao_active_cloud_site_name', site['name']?.toString() ?? '');
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const SessionsScreen()));
  }

  Future<void> _signOut() async {
    await CloudConfig.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = CloudConfig.client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes sites Wi-Fi'),
        actions: [IconButton(tooltip: 'Déconnexion', onPressed: _signOut, icon: const Icon(Icons.logout))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _loadSites, child: const Text('Réessayer')),
                  ]),
                ))
              : _sites.isEmpty
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.wifi_off, size: 48),
                        const SizedBox(height: 12),
                        const Text('Aucun site ne vous est encore attribué.', textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text(user?.email ?? '', style: Theme.of(context).textTheme.bodySmall),
                        TextButton(onPressed: _loadSites, child: const Text('Actualiser')),
                      ]),
                    ))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(user?.email ?? '', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 12),
                        for (final site in _sites)
                          Card(
                            child: ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.wifi)),
                              title: Text(site['name']?.toString() ?? 'Site sans nom'),
                              subtitle: Text('${site['role'] ?? 'viewer'} · ${site['default_currency'] ?? 'CDF'} · ${site['timezone'] ?? ''}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _selectSite(site),
                            ),
                          ),
                      ],
                    ),
    );
  }
}
