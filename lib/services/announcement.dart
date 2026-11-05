import 'dart:convert';

/// Style de l'annonce affichée en haut de la page de connexion du hotspot.
enum AnnounceKind {
  info('Information'),
  warning('Attention'),
  promo('Promotion');

  const AnnounceKind(this.label);
  final String label;
}

/// Annonce telle qu'elle est enregistrée sur le routeur.
class Announcement {
  const Announcement({required this.text, required this.kind, this.expires});
  final String text;
  final AnnounceKind kind;

  /// Après cette heure, la page n'affiche plus l'annonce (null : sans limite).
  final DateTime? expires;

  bool get isEmpty => text.trim().isEmpty;
  bool expiredAt(DateTime now) => expires != null && now.isAfter(expires!);
}

const String announceStart = '<!--mkm-annonce-->';
const String announceEnd = '<!--/mkm-annonce-->';

/// Fichier d'annonce, à côté de login.html dans le dossier du hotspot.
const String announceFileName = 'annonce.js';

/// Ligne ajoutée une seule fois dans login.html : elle charge /annonce.js
/// (avec une valeur qui change chaque minute pour éviter l'ancienne version en cache).
const String announceLoader =
    '$announceStart<script>document.write(\'<script src="/$announceFileName?\'+Math.floor(Date.now()/60000)+\'"><\\/script>\')</script>$announceEnd';

final RegExp _bodyTag = RegExp(r'<body[^>]*>', caseSensitive: false);
final RegExp _loaderBlock = RegExp('${RegExp.escape(announceStart)}[\\s\\S]*?${RegExp.escape(announceEnd)}\\n?');

bool hasAnnounceLoader(String html) => html.contains(announceStart);

/// Insère le chargeur juste après `<body…>`. Null si la page n'a pas de balise body.
String? insertAnnounceLoader(String html) {
  if (hasAnnounceLoader(html)) return html;
  final m = _bodyTag.firstMatch(html);
  if (m == null) return null;
  return '${html.substring(0, m.end)}\n$announceLoader\n${html.substring(m.end)}';
}

/// Retire le chargeur : la page redevient comme avant.
String removeAnnounceLoader(String html) => html.replaceAll(_loaderBlock, '');

String _jsString(String s) => jsonEncode(s)
    .replaceAll('</', '<\\/')
    .replaceAll(' ', '\\u2028')
    .replaceAll(' ', '\\u2029');

const Map<AnnounceKind, (String, String)> _colors = {
  AnnounceKind.info: ('#e3f2fd', '#0d47a1'),
  AnnounceKind.warning: ('#fff3e0', '#bf360c'),
  AnnounceKind.promo: ('#e8f5e9', '#1b5e20'),
};

/// Contenu de annonce.js. La première ligne garde l'annonce lisible par l'application ;
/// le texte est inséré avec textContent, jamais comme HTML.
String buildAnnounceScript(Announcement a) {
  final exp = a.expires?.millisecondsSinceEpoch ?? 0;
  final (bg, fg) = _colors[a.kind]!;
  final text = a.text.trim();
  final header = '//mkm|${a.kind.name}|$exp|${Uri.encodeComponent(text)}';
  if (text.isEmpty) return '$header\n';
  return '$header\n'
      '(function(){\n'
      'var exp=$exp;if(exp&&Date.now()>exp)return;\n'
      'var t=${_jsString(text)};\n'
      'function show(){var d=document.createElement("div");\n'
      'd.style.cssText="background:$bg;color:$fg;padding:12px 14px;margin:0 0 10px 0;'
      'font:600 15px/1.35 sans-serif;text-align:center;border-bottom:2px solid $fg";\n'
      'd.textContent=t;document.body.insertBefore(d,document.body.firstChild);}\n'
      'if(document.body){show();}else{window.addEventListener("load",show);}\n'
      '})();\n';
}

/// Relit l'annonce depuis la première ligne de annonce.js. Null si ce n'est pas la nôtre.
Announcement? parseAnnounceScript(String js) {
  final first = js.split(RegExp(r'\r?\n')).first;
  if (!first.startsWith('//mkm|')) return null;
  final p = first.split('|');
  if (p.length < 4) return null;
  final kind = AnnounceKind.values.where((k) => k.name == p[1]);
  final ms = int.tryParse(p[2]) ?? 0;
  String text;
  try {
    text = Uri.decodeComponent(p.sublist(3).join('|'));
  } catch (_) {
    return null;
  }
  return Announcement(
    text: text,
    kind: kind.isEmpty ? AnnounceKind.info : kind.first,
    expires: ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
  );
}

/// Durées proposées pour une annonce.
enum AnnounceDuration {
  tonight('Jusqu\'à ce soir'),
  day('24 heures'),
  none('Sans limite');

  const AnnounceDuration(this.label);
  final String label;

  DateTime? from(DateTime now) => switch (this) {
        AnnounceDuration.tonight => DateTime(now.year, now.month, now.day + 1),
        AnnounceDuration.day => now.add(const Duration(hours: 24)),
        AnnounceDuration.none => null,
      };
}

const int announceMaxLength = 160;
