import '../models.dart';

/// Un ticket trouvé : son état sur le routeur (absent s'il a expiré et a été
/// supprimé), ses ventes et ses sessions en cours.
class TicketHit {
  TicketHit(this.name, {this.user, this.sales = const [], this.sessions = const []});
  final String name;
  final HotspotUser? user;
  final List<Sale> sales;
  final List<ActiveUser> sessions;
}

/// Un appareil trouvé (par adresse MAC, IP ou nom).
class DeviceHit {
  DeviceHit({required this.mac, required this.address, required this.hostName, required this.tickets});
  final String mac;
  final String address;
  final String hostName;

  /// Tickets déjà vus sur cet appareil (ventes ou sessions).
  final List<String> tickets;
}

class SearchResult {
  const SearchResult(this.tickets, this.devices);
  final List<TicketHit> tickets;
  final List<DeviceHit> devices;
  bool get isEmpty => tickets.isEmpty && devices.isEmpty;
  static const empty = SearchResult([], []);
}

final RegExp _timeToken = RegExp(r'^(\d{1,2})(?:h|:)(\d{0,2})$');

/// Recherche dans tout ce que l'application connaît.
///
/// Chaque mot de la requête doit être trouvé (code, profil, lot, appareil,
/// adresse, montant). Un mot comme `14h` ou `14:30` cherche les ventes faites
/// vers cette heure, aujourd'hui ou ces deux derniers jours.
SearchResult search(
  String query, {
  required List<HotspotUser> users,
  required List<Sale> sales,
  required List<ActiveUser> active,
  required List<DhcpLease> leases,
  required DateTime now,
  int limit = 30,
}) {
  final tokens = query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return SearchResult.empty;

  final timeTokens = <(int, int?)>[];
  final words = <String>[];
  for (final t in tokens) {
    final m = _timeToken.firstMatch(t);
    if (m != null && int.parse(m.group(1)!) < 24) {
      timeTokens.add((int.parse(m.group(1)!), m.group(2)!.isEmpty ? null : int.parse(m.group(2)!)));
    } else {
      words.add(t);
    }
  }

  bool wordsMatch(List<String> fields, {int? price}) => words.every(
        (w) => fields.any((f) => f.toLowerCase().contains(w)) || (price != null && '$price' == w),
      );

  final today = DateTime(now.year, now.month, now.day);
  bool timeMatches(Sale s) {
    if (timeTokens.isEmpty) return true;
    if (s.time.isBefore(DateTime(today.year, today.month, today.day - 2))) return false;
    final minutes = s.time.hour * 60 + s.time.minute;
    return timeTokens.any((t) {
      final center = t.$1 * 60 + (t.$2 ?? 30);
      return (minutes - center).abs() <= (t.$2 == null ? 45 : 30);
    });
  }

  bool saleMatches(Sale s) =>
      timeMatches(s) && wordsMatch([s.user, s.mac, s.address, s.profile, s.comment], price: s.price);

  final matchedSales = sales.where(saleMatches).toList();
  final names = <String>{};
  final order = <String>[];
  void add(String n) {
    if (n.isNotEmpty && names.add(n)) order.add(n);
  }

  if (timeTokens.isEmpty) {
    for (final u in users) {
      if (wordsMatch([u.name, u.profile, u.comment, u.boundMac])) add(u.name);
    }
    for (final a in active) {
      if (wordsMatch([a.user, a.mac, a.address])) add(a.user);
    }
  }
  for (final s in matchedSales) {
    add(s.user);
  }

  final userByName = {for (final u in users) u.name: u};
  final tickets = <TicketHit>[];
  for (final n in order.take(limit)) {
    tickets.add(TicketHit(
      n,
      user: userByName[n],
      sales: sales.where((s) => s.user == n).toList(),
      sessions: active.where((a) => a.user == n).toList(),
    ));
  }

  final devices = <DeviceHit>[];
  if (timeTokens.isEmpty && words.isNotEmpty) {
    for (final l in leases) {
      if (!wordsMatch([l.mac, l.address, l.hostName, l.comment])) continue;
      final seen = <String>{
        for (final s in sales)
          if (s.mac.isNotEmpty && s.mac.toLowerCase() == l.mac.toLowerCase()) s.user,
        for (final a in active)
          if (a.mac.isNotEmpty && a.mac.toLowerCase() == l.mac.toLowerCase()) a.user,
      };
      devices.add(DeviceHit(mac: l.mac, address: l.address, hostName: l.hostName, tickets: seen.toList()));
      if (devices.length >= limit) break;
    }
  }
  return SearchResult(tickets, devices);
}
