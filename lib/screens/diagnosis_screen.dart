import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../services/diagnosis.dart';
import '../services/insights.dart';
import '../services/mikhmon_service.dart';
import '../util.dart';
import '../widgets/desktop.dart';
import '../widgets/extend_dialog.dart';

/// « Ce ticket ne marche pas » : le client donne son code, l'application dit
/// pourquoi et propose la réparation (réactiver, prolonger, libérer l'appareil,
/// débloquer, remplacer).
class DiagnosisScreen extends StatefulWidget {
  const DiagnosisScreen({super.key, required this.service, required this.session});

  final MikhmonService service;
  final Session session;

  @override
  State<DiagnosisScreen> createState() => _DiagnosisScreenState();
}

class _DiagnosisScreenState extends State<DiagnosisScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  Diagnosis? _result;
  Voucher? _replacement;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _check([String? code]) async {
    final c = (code ?? _code.text).trim();
    if (c.isEmpty) {
      showMessage(context, 'Tapez le code du ticket.');
      return;
    }
    _code.text = c;
    setState(() {
      _busy = true;
      _replacement = null;
    });
    try {
      final users = await widget.service.hotspotUsers();
      final sales = await widget.service.sales();
      final active = await widget.service.activeUsers();
      var blocked = <BlockedDevice>[];
      try {
        blocked = await widget.service.blockedDevices();
      } catch (_) {}
      final d = diagnoseTicket(c, users: users, sales: sales, active: active, blocked: blocked);
      if (mounted) setState(() => _result = d);
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) showMessage(context, done);
      await _check(_code.text);
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    }
  }

  Future<void> _replace(Diagnosis d) async {
    final profiles = await widget.service.profiles();
    HotspotProfile? p;
    for (final x in profiles) {
      if (x.name == d.profile) p = x;
    }
    if (p == null) {
      if (mounted) showMessage(context, 'Le profil « ${d.profile} » n\'existe plus : créez le ticket depuis « Vente rapide ».');
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remplacer le ticket ?'),
        content: Text('Un nouveau ticket ${p!.name} sera créé'
            '${d.user == null ? '' : ' et l\'ancien (${d.code}) sera désactivé'}. '
            'Faites-le seulement si le client a bien payé.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remplacer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final made = await widget.service.generate(GenerateRequest(profile: p, count: 1));
      if (d.user != null) await widget.service.setUserDisabled(d.user!.id, true);
      if (mounted) setState(() => _replacement = made.first);
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    }
  }

  String _message(Voucher v) => ticketMessage(
        network: widget.session.name,
        voucher: v,
        loginAddress: widget.session.dnsName,
        currency: widget.session.currency,
      );

  Future<void> _send(Voucher v) async {
    try {
      await Share.share(_message(v));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: _message(v)));
      if (mounted) showMessage(context, 'Message copié.');
    }
  }

  List<Widget> _actions(Diagnosis d) {
    final u = d.user;
    final s = widget.service;
    return [
      if (d.actions.contains(DiagAction.unblock))
        for (final b in d.blocked)
          FilledButton(
            onPressed: () => _act(() => s.unblockDevice(b.id), 'Appareil débloqué'),
            child: Text('Débloquer ${b.mac}'),
          ),
      if (u != null && d.actions.contains(DiagAction.reactivate))
        FilledButton(
            onPressed: () => _act(() => s.setUserDisabled(u.id, false), 'Ticket réactivé'),
            child: const Text('Réactiver')),
      if (u != null && d.actions.contains(DiagAction.unbind))
        OutlinedButton(
            onPressed: () => _act(() => s.unbindUser(u.id), 'Appareil libéré'),
            child: const Text('Libérer l\'appareil')),
      if (u != null && d.actions.contains(DiagAction.extend))
        OutlinedButton(
          onPressed: () async {
            final ask = await askExtension(context, u);
            if (ask == null) return;
            await _act(() => s.extendUser(u, addTime: ask.time, addBytes: ask.bytes), 'Ticket prolongé');
          },
          child: const Text('Prolonger'),
        ),
      if (u != null && d.actions.contains(DiagAction.resetCounters))
        OutlinedButton(
            onPressed: () => _act(() => s.resetUserCounters(u.id), 'Compteurs remis à zéro'),
            child: const Text('Remettre à zéro')),
      if (d.actions.contains(DiagAction.disconnect))
        for (final a in d.sessions)
          OutlinedButton(
              onPressed: () => _act(() => s.disconnect(a.id), 'Session coupée'),
              child: Text('Déconnecter ${a.address}')),
      if (d.actions.contains(DiagAction.replace) && d.profile.isNotEmpty)
        OutlinedButton.icon(
          onPressed: () => _replace(d),
          icon: const Icon(Icons.autorenew, size: 18),
          label: const Text('Remplacer par un nouveau'),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = _result;
    final rep = _replacement;
    return ContentWidth(
      maxWidth: 760,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Ce ticket ne marche pas', style: t.titleLarge),
          const SizedBox(height: 4),
          Text('Demandez le code au client : l\'application cherche la cause.', style: t.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _check(),
            decoration: InputDecoration(
              labelText: 'Code du ticket',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Vérifier',
                icon: const Icon(Icons.search),
                onPressed: _busy ? null : _check,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _check,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.health_and_safety_outlined),
            label: const Text('Vérifier le ticket'),
          ),
          if (d != null && d.code.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(d.hasProblem || d.user == null ? Icons.error_outline : Icons.check_circle_outline,
                          color: d.hasProblem || d.user == null ? Colors.orange.shade800 : Colors.green.shade700),
                      const SizedBox(width: 8),
                      Expanded(child: Text(d.verdict, style: t.titleMedium)),
                    ]),
                    const SizedBox(height: 8),
                    for (final f in d.findings)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(f.problem ? Icons.warning_amber : Icons.info_outline,
                                size: 18, color: f.problem ? Colors.orange.shade800 : null),
                            const SizedBox(width: 8),
                            Expanded(child: Text(f.text)),
                          ],
                        ),
                      ),
                    if (d.user == null && d.similar.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: [
                        for (final c in d.similar)
                          ActionChip(label: Text(c), onPressed: () => _check(c)),
                      ]),
                    ],
                    if (d.user != null && !d.hasProblem) ...[
                      const SizedBox(height: 8),
                      Text('Le ticket est bon : le souci vient sans doute du téléphone du client.', style: t.bodyMedium),
                      for (final tip in validTicketTips)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('• $tip', style: t.bodySmall),
                        ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 4, children: _actions(d)),
                  ],
                ),
              ),
            ),
          ],
          if (rep != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nouveau ticket', style: t.titleMedium),
                    SelectableText(rep.name, style: t.headlineSmall?.copyWith(fontFamily: 'monospace', letterSpacing: 2)),
                    if (rep.password.isNotEmpty && rep.password != rep.name)
                      SelectableText('Mot de passe : ${rep.password}'),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () => _send(rep),
                      icon: const Icon(Icons.send),
                      label: const Text('Envoyer au client'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
