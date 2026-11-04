/// Vitesses au format RouterOS.
///
/// Une limite complète s'écrit :
/// `envoi/réception rafale-envoi/rafale-réception seuil durée priorité minimum`
/// (par exemple `1M/2M 2M/4M 750k/1500k 10s/10s 8 256k/512k`). Seul le premier
/// élément est obligatoire.

/// Lit `512k`, `2M`, `1G` ou un nombre de bits. Null si invalide.
int? parseRateBits(String token) {
  final m = RegExp(r'^(\d+)([kKmMgG]?)$').firstMatch(token.trim());
  if (m == null) return null;
  final n = int.parse(m.group(1)!);
  switch (m.group(2)!.toLowerCase()) {
    case 'k':
      return n * 1000;
    case 'm':
      return n * 1000000;
    case 'g':
      return n * 1000000000;
    default:
      return n;
  }
}

/// Écrit des bits par seconde : `2M`, `1500k`, ou le nombre brut.
String formatRateBits(int bits) {
  if (bits >= 1000000 && bits % 1000000 == 0) return '${bits ~/ 1000000}M';
  if (bits >= 1000 && bits % 1000 == 0) return '${bits ~/ 1000}k';
  return '$bits';
}

/// `2M` devient `2M/2M` (même vitesse dans les deux sens) ; `1M/5M` reste tel quel.
String normalizeRate(String text) {
  final t = text.trim();
  if (t.isEmpty || t.contains('/')) return t;
  return '$t/$t';
}

final RegExp _pair = RegExp(r'^[0-9]+[kKmMgG]?(/[0-9]+[kKmMgG]?)?$');

/// Vrai si [text] est une vitesse simple valable (`2M` ou `1M/5M`).
bool isValidRate(String text) => _pair.hasMatch(text.trim());

(int, int)? _split(String pair) {
  final n = normalizeRate(pair).split('/');
  if (n.length != 2) return null;
  final a = parseRateBits(n[0]);
  final b = parseRateBits(n[1]);
  return (a == null || b == null) ? null : (a, b);
}

/// Les éléments d'une limite de vitesse, pour le formulaire de profil.
class RateParts {
  const RateParts({this.base = '', this.burst = false, this.minimum = ''});

  /// Vitesse maximale (`envoi/réception`), vide : pleine vitesse.
  final String base;

  /// Départ rapide : vitesse doublée pendant les premières secondes.
  final bool burst;

  /// Débit minimum garanti (`envoi/réception`), vide : aucun.
  final String minimum;
}

/// Compose la limite RouterOS à partir des éléments du formulaire.
/// Départ rapide : le double de la vitesse, tant que la moyenne reste sous
/// 75 % de la vitesse, pendant 10 secondes.
String buildRateLimit(RateParts p) {
  final base = normalizeRate(p.base);
  if (base.isEmpty) return '';
  final b = _split(base);
  if (b == null) return base;
  if (!p.burst && p.minimum.trim().isEmpty) return base;
  String pair(int up, int down) => '${formatRateBits(up)}/${formatRateBits(down)}';
  final burst = pair(b.$1 * 2, b.$2 * 2);
  final threshold = pair(b.$1 * 3 ~/ 4, b.$2 * 3 ~/ 4);
  final parts = <String>[base];
  if (p.burst) {
    parts.addAll([burst, threshold, '10s/10s']);
  } else {
    // Sans départ rapide : la rafale est égale à la vitesse (aucun effet).
    parts.addAll([base, base, '1s/1s']);
  }
  final min = normalizeRate(p.minimum);
  if (min.isNotEmpty) parts.addAll(['8', min]);
  return parts.join(' ');
}

/// Relit une limite RouterOS (inverse de [buildRateLimit]).
RateParts parseRateLimit(String text) {
  final t = text.trim().split(RegExp(r'\s+'));
  if (t.isEmpty || t.first.isEmpty) return const RateParts();
  final base = t.first;
  final burst = t.length >= 4 && t[1] != base;
  final minimum = t.length >= 6 ? t[5] : '';
  return RateParts(base: base, burst: burst, minimum: minimum);
}
