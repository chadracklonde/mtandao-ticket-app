import 'package:flutter/material.dart';

import '../models.dart';
import '../routeros/api_client.dart';
import '../services/session_store.dart';
import '../util.dart';

/// Ajout / modification d'un routeur.
class SessionForm extends StatefulWidget {
  const SessionForm({super.key, required this.store, this.session});

  final SessionStore store;
  final Session? session;

  @override
  State<SessionForm> createState() => _SessionFormState();
}

class _SessionFormState extends State<SessionForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _user;
  late final TextEditingController _password;
  late final TextEditingController _currency;
  late final TextEditingController _dns;
  late bool _ssl;
  bool _showPassword = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    _name = TextEditingController(text: s?.name ?? '');
    _host = TextEditingController(text: s?.host ?? '192.168.88.1');
    _port = TextEditingController(text: '${s?.port ?? 8728}');
    _user = TextEditingController(text: s?.username ?? 'admin');
    _password = TextEditingController(text: s?.password ?? '');
    _currency = TextEditingController(text: s?.currency ?? 'FC');
    _dns = TextEditingController(text: s?.dnsName ?? '');
    _ssl = s?.useSsl ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _password.dispose();
    _currency.dispose();
    _dns.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final s = Session(
      id: widget.session?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      host: _host.text.trim(),
      port: int.parse(_port.text.trim()),
      useSsl: _ssl,
      username: _user.text.trim(),
      password: _password.text,
      currency: _currency.text.trim().isEmpty ? 'FC' : _currency.text.trim(),
      dnsName: _dns.text.trim(),
    );
    await widget.store.save(s);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _test() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _testing = true);
    final client = RouterOsClient(
      host: _host.text.trim(),
      port: int.parse(_port.text.trim()),
      useSsl: _ssl,
      username: _user.text.trim(),
      password: _password.text,
      connectTimeout: const Duration(seconds: 6),
    );
    try {
      await client.connect();
      if (mounted) showMessage(context, 'Connexion réussie.');
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Champ obligatoire' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.session == null ? 'Nouveau routeur' : 'Modifier le routeur')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nom (affiché sur les tickets)',
                border: OutlineInputBorder(),
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _host,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Adresse IP ou nom du routeur',
                helperText: 'Adresse locale (ex. 192.168.88.1), ou celle joignable via le VPN',
                border: OutlineInputBorder(),
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Port API',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      return (n == null || n < 1 || n > 65535) ? 'Port invalide' : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('SSL'),
                    value: _ssl,
                    onChanged: (v) => setState(() {
                      _ssl = v;
                      if (v && _port.text.trim() == '8728') _port.text = '8729';
                      if (!v && _port.text.trim() == '8729') _port.text = '8728';
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _user,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Utilisateur du routeur',
                border: OutlineInputBorder(),
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _currency,
              decoration: const InputDecoration(
                labelText: 'Devise',
                helperText: 'Ex. FC, USD',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dns,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Adresse de la page de connexion du hotspot (facultatif)',
                helperText: 'Ex. wifi.local ou 10.5.50.1 : sert au QR code des tickets',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering),
              label: const Text('Tester la connexion'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
