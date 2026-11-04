import 'package:flutter/material.dart';

import '../models.dart';
import '../util.dart';

/// Demande le temps et/ou les données à ajouter à un ticket.
/// Renvoie null si l'utilisateur annule.
Future<({Duration? time, int? bytes})?> askExtension(BuildContext context, HotspotUser u) async {
    final time = TextEditingController();
    final data = TextEditingController();
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Prolonger ${u.name}'),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (u.limitUptime != null)
                TextFormField(
                  controller: time,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Temps à ajouter',
                    helperText: 'Ex. 1h, 1d',
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim().toLowerCase();
                    return (t.isNotEmpty && !uptimePattern.hasMatch(t)) ? 'Format invalide' : null;
                  },
                ),
              if (u.limitBytes > 0)
                TextFormField(
                  controller: data,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Données à ajouter',
                    helperText: 'Ex. 500M, 1G',
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    return (t.isNotEmpty && parseDataSize(t) == null) ? 'Format invalide' : null;
                  },
                ),
              if (u.limitUptime == null && u.limitBytes <= 0)
                const Text('Ce ticket est illimité : il n\'y a rien à prolonger.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Prolonger'),
          ),
        ],
      ),
    );
    if (ok != true) return null;
    return (time: parseRouterDuration(time.text.trim().toLowerCase()), bytes: parseDataSize(data.text));
}
