import '../models.dart';
import '../util.dart';

/// Chiffres affichés dans la notification permanente.
class LiveStats {
  const LiveStats({
    required this.salesToday,
    required this.amountToday,
    required this.connected,
    this.lowStock = const [],
    this.at,
  });

  final int salesToday;
  final int amountToday;
  final int connected;

  /// Profils dont le stock de tickets neufs est bas (nom -> restant).
  final List<MapEntry<String, int>> lowStock;
  final DateTime? at;
}

/// Calcule les chiffres du jour à partir des ventes et des appareils actifs.
LiveStats computeLiveStats(
  List<Sale> sales,
  int connected,
  DateTime now, {
  List<MapEntry<String, int>> lowStock = const [],
}) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  var count = 0;
  var amount = 0;
  for (final s in sales) {
    if (!s.time.isBefore(today) && s.time.isBefore(tomorrow)) {
      count++;
      amount += s.price;
    }
  }
  return LiveStats(salesToday: count, amountToday: amount, connected: connected, lowStock: lowStock, at: now);
}

/// Titre : l'essentiel, lisible sans déplier la notification.
String liveTitle(LiveStats s, String currency) {
  final n = s.salesToday;
  final sales = n == 0 ? 'Aucune vente' : '$n vente${n > 1 ? 's' : ''} · ${formatMoney(s.amountToday, currency)}';
  return "$sales aujourd'hui";
}

/// Corps : appareils connectés, alerte de stock et heure de mise à jour.
String liveBody(LiveStats s) {
  final c = s.connected;
  final parts = <String>[
    c == 0 ? 'Aucun appareil connecté' : '$c appareil${c > 1 ? 's' : ''} connecté${c > 1 ? 's' : ''}',
  ];
  if (s.lowStock.isNotEmpty) {
    parts.add('Stock bas : ${s.lowStock.take(3).map((e) => '${e.key} (${e.value})').join(', ')}');
  }
  if (s.at != null) parts.add('à ${formatTime(s.at!)}');
  return parts.join(' · ');
}
