import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/announcement.dart';
import '../services/mikhmon_service.dart';
import '../util.dart';
import '../widgets/async_body.dart';
import '../widgets/desktop.dart';

/// Annonce du jour : une ligne affichée en haut de la page de connexion du hotspot
/// (coupure prévue, promotion…), modifiable depuis l'application.
class AnnouncementScreen extends StatefulWidget {
  const AnnouncementScreen({super.key, required this.service});

  final MikhmonService service;

  @override
  State<AnnouncementScreen> createState() => _AnnouncementScreenState();
}

class _AnnouncementScreenState extends State<AnnouncementScreen> {
  final _text = TextEditingController();
  AnnounceKind _kind = AnnounceKind.info;
  AnnounceDuration _duration = AnnounceDuration.tonight;
  bool _busy = false;
  bool _filled = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  (Color, Color) _colors(AnnounceKind k) => switch (k) {
        AnnounceKind.info => (const Color(0xFFE3F2FD), const Color(0xFF0D47A1)),
        AnnounceKind.warning => (const Color(0xFFFFF3E0), const Color(0xFFBF360C)),
        AnnounceKind.promo => (const Color(0xFFE8F5E9), const Color(0xFF1B5E20)),
      };

  Future<void> _run(Future<void> Function() action, Future<void> Function() reload, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      await reload();
      if (mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepare(Future<void> Function() reload) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Préparer la page de connexion ?'),
        content: const Text(
          'L\'application ajoute une seule ligne dans la page de connexion du hotspot (login.html) '
          'et garde une copie de l\'original sous le nom login.html.avant-annonce, sur le routeur. '
          'Vous pourrez tout retirer ensuite avec « Retirer l\'espace d\'annonce ».',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Préparer')),
        ],
      ),
    );
    if (ok == true) await _run(widget.service.installAnnouncement, reload, 'Page de connexion préparée.');
  }

  Widget _banner(BuildContext context, String text, AnnounceKind kind) {
    final (bg, fg) = _colors(kind);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: bg, border: Border(bottom: BorderSide(color: fg, width: 2))),
      child: Text(text.isEmpty ? 'Votre annonce apparaîtra ici' : text,
          textAlign: TextAlign.center,
          style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 15)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AsyncBody<AnnounceState>(
      load: widget.service.announcementState,
      builder: (context, st, reload) {
        if (!_filled) {
          _filled = true;
          final c = st.current;
          if (c != null && !c.isEmpty) {
            _text.text = c.text;
            _kind = c.kind;
          }
        }
        final now = DateTime.now();
        final cur = st.current;
        final live = cur != null && !cur.isEmpty && !cur.expiredAt(now);
        return ContentWidth(
          maxWidth: 760,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text('Annonce du jour', style: t.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Une ligne en haut de la page que voient vos clients avant de se connecter : '
                'coupure prévue, promotion, nouveau tarif.',
                style: t.bodySmall,
              ),
              const SizedBox(height: 16),
              if (!st.loginFound)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.error_outline),
                    title: Text('Page de connexion introuvable'),
                    subtitle: Text('Le fichier login.html du hotspot n\'existe pas sur ce routeur.'),
                  ),
                )
              else if (!st.installed) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Première utilisation', style: t.titleMedium),
                        const SizedBox(height: 4),
                        const Text('La page de connexion doit d\'abord être préparée, une seule fois. '
                            'Une copie de l\'original est gardée sur le routeur.'),
                        if (!st.readable) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Le routeur ne laisse pas lire cette page (trop grande) : l\'application ne peut pas la '
                            'préparer seule. Copiez la ligne ci-dessous et collez-la juste après <body> dans '
                            'login.html avec Winbox (Files).',
                            style: t.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(const ClipboardData(text: announceLoader));
                              if (context.mounted) showMessage(context, 'Ligne copiée.');
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('Copier la ligne à ajouter'),
                          ),
                        ] else ...[
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _busy ? null : () => _prepare(reload),
                            child: const Text('Préparer la page de connexion'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ] else ...[
                if (live) ...[
                  Text('En ligne actuellement', style: t.titleSmall),
                  const SizedBox(height: 6),
                  _banner(context, cur.text, cur.kind),
                  if (cur.expires != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Jusqu\'au ${formatDate(cur.expires!)} à ${formatTime(cur.expires!)}',
                          style: t.bodySmall),
                    ),
                  const SizedBox(height: 16),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('Aucune annonce en ligne.', style: t.bodyMedium),
                  ),
                TextField(
                  controller: _text,
                  enabled: !_busy,
                  maxLength: announceMaxLength,
                  maxLines: 3,
                  minLines: 2,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Texte de l\'annonce',
                    hintText: 'Ex. Coupure de courant prévue de 14 h à 15 h',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  for (final k in AnnounceKind.values)
                    ChoiceChip(
                      label: Text(k.label),
                      selected: _kind == k,
                      onSelected: _busy ? null : (_) => setState(() => _kind = k),
                    ),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  for (final d in AnnounceDuration.values)
                    ChoiceChip(
                      label: Text(d.label),
                      selected: _duration == d,
                      onSelected: _busy ? null : (_) => setState(() => _duration = d),
                    ),
                ]),
                const SizedBox(height: 16),
                Text('Aperçu', style: t.titleSmall),
                const SizedBox(height: 6),
                _banner(context, _text.text.trim(), _kind),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy || _text.text.trim().isEmpty
                      ? null
                      : () => _run(
                            () => widget.service.setAnnouncement(Announcement(
                              text: _text.text.trim(),
                              kind: _kind,
                              expires: _duration.from(DateTime.now()),
                            )),
                            reload,
                            'Annonce publiée.',
                          ),
                  icon: const Icon(Icons.campaign_outlined),
                  label: const Text('Publier l\'annonce'),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  if (live)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _run(
                                () => widget.service
                                    .setAnnouncement(const Announcement(text: '', kind: AnnounceKind.info)),
                                reload,
                                'Annonce retirée.',
                              ),
                      child: const Text('Retirer l\'annonce'),
                    ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(widget.service.uninstallAnnouncement, reload,
                            'Page de connexion remise comme avant.'),
                    child: const Text('Retirer l\'espace d\'annonce'),
                  ),
                ]),
                const SizedBox(height: 12),
                Text(
                  'Les clients voient la nouvelle annonce en moins d\'une minute. Après une annonce limitée '
                  'dans le temps, la page l\'efface d\'elle-même à l\'heure prévue.',
                  style: t.bodySmall,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
