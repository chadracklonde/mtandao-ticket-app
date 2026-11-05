import '../models.dart';

/// Débit d'un client connecté, calculé entre deux relevés.
class UserRate {
  const UserRate({
    required this.session,
    required this.downBps,
    required this.upBps,
  });

  final ActiveUser session;

  /// Octets par seconde reçus par le client (téléchargement) et envoyés (envoi).
  final double downBps;
  final double upBps;

  double get totalBps => downBps + upBps;
}

/// Compare deux relevés des utilisateurs actifs et classe les clients du plus
/// gourmand au moins gourmand. Un compteur qui recule (nouvelle session) donne 0.
List<UserRate> computeRates(List<ActiveUser> before, List<ActiveUser> now, Duration elapsed) {
  final secs = elapsed.inMilliseconds / 1000.0;
  final prev = {for (final a in before) a.id: a};
  final out = <UserRate>[];
  for (final a in now) {
    final p = prev[a.id];
    double down = 0, up = 0;
    if (p != null && secs > 0) {
      // Pour le routeur, « bytes-out » part vers le client : c'est son téléchargement.
      final d = a.bytesOut - p.bytesOut;
      final u = a.bytesIn - p.bytesIn;
      down = d > 0 ? d / secs : 0;
      up = u > 0 ? u / secs : 0;
    }
    out.add(UserRate(session: a, downBps: down, upBps: up));
  }
  out.sort((x, y) => y.totalBps.compareTo(x.totalBps));
  return out;
}

/// « 1,2 Mo/s », « 340 Ko/s », « 0 o/s ».
String formatSpeed(double bytesPerSecond) {
  const units = ['o/s', 'Ko/s', 'Mo/s', 'Go/s'];
  var v = bytesPerSecond;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final text = i == 0 ? v.round().toString() : v.toStringAsFixed(v >= 10 ? 0 : 1).replaceAll('.', ',');
  return '$text ${units[i]}';
}
