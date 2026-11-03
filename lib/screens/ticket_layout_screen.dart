import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models.dart';
import '../services/ticket_layout.dart';
import '../services/voucher_pdf.dart';

/// Réglage de la mise en page des tickets imprimés, avec aperçu.
class TicketLayoutScreen extends StatefulWidget {
  const TicketLayoutScreen({super.key, required this.session});

  final Session session;

  @override
  State<TicketLayoutScreen> createState() => _TicketLayoutScreenState();
}

class _TicketLayoutScreenState extends State<TicketLayoutScreen> {
  final _store = TicketLayoutStore();
  final _header = TextEditingController();
  final _footer = TextEditingController();
  TicketLayout _layout = const TicketLayout();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _store.load().then((l) {
      if (!mounted) return;
      setState(() {
        _layout = l;
        _header.text = l.header;
        _footer.text = l.footer;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _header.dispose();
    _footer.dispose();
    super.dispose();
  }

  void _update(TicketLayout l) {
    setState(() => _layout = l);
    _store.save(l);
  }

  List<Voucher> get _samples => [
        for (var i = 0; i < 9; i++)
          Voucher(
            name: '${482916 + i * 37}',
            password: '${482916 + i * 37}',
            profile: '24H',
            price: 500,
            uptime: '1d',
            dataLimit: '1 Go',
          ),
      ];

  Future<void> _preview() async {
    final logo = _layout.showLogo ? await loadTicketLogo() : null;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Aperçu des tickets')),
          body: PdfPreview(
            build: (_) => buildVouchersPdf(_samples, widget.session, layout: _layout, logo: logo),
            allowPrinting: false,
            allowSharing: false,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final a4 = _layout.paper == TicketPaper.a4;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Papier', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<TicketPaper>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: TicketPaper.a4, label: Text('Feuille A4')),
            ButtonSegment(value: TicketPaper.roll58, label: Text('Rouleau 58 mm')),
            ButtonSegment(value: TicketPaper.roll80, label: Text('Rouleau 80 mm')),
          ],
          selected: {_layout.paper},
          onSelectionChanged: (s) => _update(_layout.copyWith(paper: s.first)),
        ),
        const SizedBox(height: 4),
        Text(
          a4
              ? 'Plusieurs tickets par page, à découper.'
              : 'Un ticket par page, pour une imprimante à rouleau (thermique). '
                  'Choisissez l\'imprimante dans la fenêtre d\'impression.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (a4) ...[
          const SizedBox(height: 16),
          Text('Colonnes par page', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
              ButtonSegment(value: 4, label: Text('4')),
            ],
            selected: {_layout.columns},
            onSelectionChanged: (s) => _update(_layout.copyWith(columns: s.first)),
          ),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Logo sur le ticket'),
          value: _layout.showLogo,
          onChanged: (v) => _update(_layout.copyWith(showLogo: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('QR code de connexion'),
          subtitle: const Text('Se connecter en le scannant'),
          value: _layout.showQr,
          onChanged: (v) => _update(_layout.copyWith(showQr: v)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _header,
          decoration: const InputDecoration(
            labelText: 'Titre du ticket',
            helperText: 'Vide : nom du routeur',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => _update(_layout.copyWith(header: v)),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _footer,
          decoration: const InputDecoration(
            labelText: 'Texte en bas du ticket',
            helperText: 'Ex. un numéro à appeler, une consigne',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => _update(_layout.copyWith(footer: v)),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _preview,
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Voir un aperçu'),
        ),
      ],
    );
  }
}
