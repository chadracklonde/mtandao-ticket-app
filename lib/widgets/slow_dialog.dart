import 'package:flutter/material.dart';

import '../services/speed.dart';

/// Demande à quelle vitesse limiter un appareil. Renvoie par exemple `256k`,
/// ou null si l'utilisateur annule.
Future<String?> askSlowRate(BuildContext context, {String who = ''}) {
  final c = TextEditingController(text: '256k');
  final key = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Réduire la vitesse'),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(who.isEmpty
                  ? 'Limite la vitesse de cet appareil, envoi et réception. Les autres clients ne sont pas touchés.'
                  : 'Limite la vitesse de $who, envoi et réception. Les autres clients ne sont pas touchés.'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final r in const ['128k', '256k', '512k', '1M', '2M'])
                    ChoiceChip(
                      label: Text(r),
                      selected: c.text.trim() == r,
                      onSelected: (_) => setState(() => c.text = r),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: c,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Vitesse maximale',
                  helperText: 'k = kilobits/s, M = mégabits/s (ex. 300k, 1M)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => isValidRate((v ?? '').trim()) ? null : 'Format invalide (ex. 256k, 1M)',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) Navigator.pop(ctx, c.text.trim());
            },
            child: const Text('Réduire'),
          ),
        ],
      ),
    ),
  );
}
