import '../models.dart';

/// Total d'un profil sur la période.
class ProfileTotal {
  ProfileTotal(this.profile);
  final String profile;
  int count = 0;
  int total = 0;
}

/// Total d'une journée.
class DayTotal {
  DayTotal(this.day, this.sales);
  final DateTime day;
  final List<Sale> sales;
  int get total => sales.fold<int>(0, (a, s) => a + s.price);
}

/// Ventes d'une période (jour, mois ou dates choisies), du début au jour de
/// fin inclus.
class SalesSummary {
  SalesSummary._(this.start, this.end, this.sales, this.days, this.byProfile);

  final DateTime start;
  final DateTime end;
  final List<Sale> sales;

  /// Journées avec au moins une vente, de la plus récente à la plus ancienne.
  final List<DayTotal> days;

  /// Totaux par profil, du plus rentable au moins rentable.
  final List<ProfileTotal> byProfile;

  int get total => sales.fold<int>(0, (a, s) => a + s.price);
  int get count => sales.length;

  /// Dates en jours entiers (l'heure est ignorée).
  static DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  static SalesSummary of(List<Sale> all, DateTime start, DateTime end) {
    var from = dayOf(start);
    var to = dayOf(end);
    if (to.isBefore(from)) {
      final t = from;
      from = to;
      to = t;
    }
    final until = DateTime(to.year, to.month, to.day + 1);
    final inRange =
        all.where((s) => !s.time.isBefore(from) && s.time.isBefore(until)).toList()
          ..sort((a, b) => b.time.compareTo(a.time));

    final perDay = <DateTime, List<Sale>>{};
    final perProfile = <String, ProfileTotal>{};
    for (final s in inRange) {
      perDay.putIfAbsent(dayOf(s.time), () => []).add(s);
      final p = perProfile.putIfAbsent(s.profile, () => ProfileTotal(s.profile));
      p.count++;
      p.total += s.price;
    }
    final days = perDay.entries.map((e) => DayTotal(e.key, e.value)).toList()
      ..sort((a, b) => b.day.compareTo(a.day));
    final profiles = perProfile.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return SalesSummary._(from, to, inRange, days, profiles);
  }

  /// Montants par jour, du premier au dernier jour de la période (zéros compris).
  List<int> perDayTotals() {
    final out = <int>[];
    for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
      out.add(sales.where((s) => dayOf(s.time) == d).fold<int>(0, (a, s) => a + s.price));
    }
    return out;
  }

  /// Montants par heure (0 à 23), pour une journée.
  List<int> perHourTotals() {
    final out = List<int>.filled(24, 0);
    for (final s in sales) {
      out[s.time.hour] += s.price;
    }
    return out;
  }

  /// Variation en pourcentage par rapport à [previous] ; null si la période
  /// précédente n'a aucune vente.
  static double? changePercent(int current, int previous) =>
      previous <= 0 ? null : (current - previous) * 100 / previous;

  /// Premier et dernier jour du mois de [d].
  static (DateTime, DateTime) monthRange(DateTime d) =>
      (DateTime(d.year, d.month), DateTime(d.year, d.month + 1, 0));
}
