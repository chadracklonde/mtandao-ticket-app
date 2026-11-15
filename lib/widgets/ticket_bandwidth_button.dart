import 'package:flutter/material.dart';

import '../models.dart';
import '../services/mikhmon_service.dart';
import '../services/ticket_bandwidth.dart';
import '../util.dart';

class TicketBandwidthButton extends StatefulWidget {
  const TicketBandwidthButton({super.key, required this.service, required this.user});
  final MikhmonService service;
  final HotspotUser user;

  @override
  State<TicketBandwidthButton> createState() => _TicketBandwidthButtonState();
}

class _TicketBandwidthButtonState extends State<TicketBandwidthButton> {
  bool _busy = false;
  String? _rate;

  Future<void> _edit() async {
    setState(() => _busy = true);
    try {
      final service = TicketBandwidth(widget.service);
      final current = await service.read(widget.user.id);
      if (!mounted) return;
      final selected = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text('Bande passante · ${widget.user.name}'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text('Limite actuelle : ${current ?? 'aucune limite propre au ticket'}.\n'
                  'Le débit est partagé entre tous les appareils de ce ticket, dans chaque sens. '
                  'Les connexions sont synchronisées toutes les 2 secondes. '
                  'Les limitations par appareil restent des réglages distincts.'),
            ),
            for (final rate in TicketBandwidth.rates)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, rate),
                child: Text(rate.endsWith('k')
                    ? '${rate.substring(0, rate.length - 1)} kb/s'
                    : '${rate.substring(0, rate.length - 1)} Mb/s'),
              ),
            if (current != null)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'remove'),
                child: const Text('Retirer la limite du ticket'),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx), child: const Text('Annuler'),
            ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      if (selected == 'remove') {
        await service.remove(widget.user.id);
      } else {
        await service.save(widget.user.id, selected);
      }
      if (!mounted) return;
      setState(() => _rate = selected == 'remove' ? null : selected);
      showMessage(context, selected == 'remove'
          ? 'Limite du ticket retirée. Les autres règles du routeur restent inchangées.'
          : 'Limite partagée $selected enregistrée. Synchronisation sous 2 secondes.');
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: _busy ? null : _edit,
        icon: const Icon(Icons.speed),
        label: Text(_busy ? 'Chargement…' : _rate == null ? 'Bande passante' : 'Bande passante · $_rate'),
      );
}
