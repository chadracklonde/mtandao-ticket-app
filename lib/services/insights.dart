import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'mikhmon_service.dart';
import 'sales_report.dart';

// ── Prévision de stock ────────────────────────────────────────────────────

/// Stock d'un profil et rythme de vente.
class StockForecast {
  const StockForecast({
    required this.profile,
    required this.left,
    required this.perDay,
    required this.daysLeft,
    required this.suggested,
  });

  final String profile;

  /// Tickets neufs restants.
  final int left;

  /// Tickets vendus par jour (moyenne sur la fenêtre observée).
  final double perDay;

  /// Jours avant rupture au rythme actuel ; null si le profil ne se vend pas.
  final double? daysLeft;

  /// Nombre de tickets à générer pour couvrir la période visée (0 : rien à faire).
  final int suggested;

  /// Stock critique : moins de 2 jours de ventes.
  bool get critical => daysLeft != null && daysLeft! < 2;
  bool get soon => daysLeft != null && daysLeft! < 4;
}

/// Prévision par profil, du plus urgent au moins urgent.
/// [window] jours d'historique ; [targetDays] jours de ventes à couvrir.
List<StockForecast> forecastStock(
  List<HotspotProfile> profiles,
  List<VoucherBatch> batches,
  List<Sale> sales,
  DateTime now, {
  int window = 14,
  int targetDays = 7,
}) {
  final left = <String, int>{};
  for (final b in batches) {
    left[b.profile] = (left[b.profile] ?? 0) + b.vouchers.length;
  }
  final today = DateTime(now.year, now.month, now.day);
  final from = DateTime(today.year, today.month, today.day - window + 1);
  final inWindow = sales.where((s) => !s.time.isBefore(from)).toList();
  // Jours réellement observés : depuis la première vente de la fenêtre (au moins 3).
  var observed = window;
  if (inWindow.isNotEmpty) {
    final first = inWindow.map((s) => s.time).reduce((a, b) => a.isBefore(b) ? a : b);
    final d = today.difference(DateTime(first.year, first.month, first.day)).inDays + 1;
    observed = d.clamp(3, window);
  }
  final sold = <String, int>{};
  for (final s in inWindow) {
    sold[s.profile] = (sold[s.profile] ?? 0) + 1;
  }
  final out = <StockForecast>[];
  for (final p in profiles) {
    if (p.price <= 0 && !sold.containsKey(p.name)) continue;
    final l = left[p.name] ?? 0;
    final perDay = (sold[p.name] ?? 0) / observed;
    final daysLeft = perDay > 0 ? l / perDay : null;
    var need = (perDay * targetDays).ceil() - l;
    if (need < 0) need = 0;
    if (need > 0) need = ((need + 4) ~/ 5) * 5; // arrondi aux 5 tickets
    out.add(StockForecast(
      profile: p.name,
      left: l,
      perDay: perDay,
      daysLeft: daysLeft,
      suggested: need,
    ));
  }
  out.sort((a, b) {
    final ad = a.daysLeft ?? double.infinity;
    final bd = b.daysLeft ?? double.infinity;
    return ad.compareTo(bd);
  });
  return out;
}

// ── Rapprochement de caisse ───────────────────────────────────────────────

/// Tickets déjà utilisés (payants) pour lesquels aucune vente n'est enregistrée :
/// vente effacée, ticket offert, ou ticket utilisé sans passer par le script.
List<HotspotUser> usedWithoutSale(
  List<HotspotUser> users,
  List<Sale> sales,
  List<HotspotProfile> profiles,
) {
  final price = {for (final p in profiles) p.name: p.price};
  final sold = {for (final s in sales) s.user};
  return [
    for (final u in users)
      if (u.isUsed && (price[u.profile] ?? 0) > 0 && !sold.contains(u.name)) u
  ];
}

/// Manque à gagner estimé pour ces tickets.
int missingRevenue(List<HotspotUser> users, List<HotspotProfile> profiles) {
  final price = {for (final p in profiles) p.name: p.price};
  return users.fold<int>(0, (a, u) => a + (price[u.profile] ?? 0));
}

/// Clôture de caisse d'une journée.
class CashClosing {
  const CashClosing({required this.day, required this.expected, required this.counted, required this.savedAt});

  /// `aaaa-mm-jj`.
  final String day;
  final int expected;
  final int counted;
  final DateTime savedAt;

  int get difference => counted - expected;

  Map<String, Object> toJson() => {
        'day': day,
        'expected': expected,
        'counted': counted,
        'savedAt': savedAt.toIso8601String(),
      };

  static CashClosing? fromJson(Object? j) {
    if (j is! Map) return null;
    final day = j['day'];
    final expected = j['expected'];
    final counted = j['counted'];
    final at = DateTime.tryParse('${j['savedAt']}');
    if (day is! String || expected is! int || counted is! int || at == null) return null;
    return CashClosing(day: day, expected: expected, counted: counted, savedAt: at);
  }
}

String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Historique des clôtures de caisse (sur l'appareil, par routeur).
class CashStore {
  CashStore(this.sessionId);
  final String sessionId;
  String get _key => 'cash_$sessionId';

  Future<List<CashClosing>> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return [];
      final list = (jsonDecode(raw) as List).map(CashClosing.fromJson).whereType<CashClosing>().toList();
      list.sort((a, b) => b.day.compareTo(a.day));
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Enregistre (ou remplace) la clôture du jour ; garde les 120 dernières.
  Future<List<CashClosing>> save(CashClosing c) async {
    final all = await load();
    all.removeWhere((x) => x.day == c.day);
    all.add(c);
    all.sort((a, b) => b.day.compareTo(a.day));
    final kept = all.take(120).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final k in kept) k.toJson()]));
    return kept;
  }
}

// ── Détection d'abus ──────────────────────────────────────────────────────

enum AbuseKind { sharedTicket, heavyUser }

/// Comportement à surveiller sur une session active.
class AbuseAlert {
  const AbuseAlert({
    required this.kind,
    required this.user,
    required this.sessions,
    required this.detail,
  });

  final AbuseKind kind;
  final String user;

  /// Sessions concernées (pour déconnecter ou bloquer).
  final List<ActiveUser> sessions;
  final String detail;
}

/// Détecte les tickets partagés (même ticket sur plusieurs appareils) et les
/// gros consommateurs (au moins [heavyBytes] et trois fois plus que la moyenne
/// des autres).
List<AbuseAlert> detectAbuse(
  List<ActiveUser> active, {
  int heavyBytes = 1024 * 1024 * 1024,
  String Function(int bytes)? format,
}) {
  final fmt = format ?? (b) => '${(b / (1024 * 1024)).round()} Mo';
  final out = <AbuseAlert>[];

  final byUser = <String, List<ActiveUser>>{};
  for (final a in active) {
    byUser.putIfAbsent(a.user, () => []).add(a);
  }
  for (final e in byUser.entries) {
    final macs = {for (final s in e.value) if (s.mac.isNotEmpty) s.mac};
    if (macs.length > 1) {
      out.add(AbuseAlert(
        kind: AbuseKind.sharedTicket,
        user: e.key,
        sessions: e.value,
        detail: 'Ticket utilisé sur ${macs.length} appareils à la fois',
      ));
    }
  }

  for (final a in active) {
    final total = a.bytesIn + a.bytesOut;
    if (total < heavyBytes) continue;
    final others = active.where((x) => x.id != a.id).map((x) => x.bytesIn + x.bytesOut).toList();
    final avg = others.isEmpty ? 0 : others.reduce((x, y) => x + y) / others.length;
    if (others.isNotEmpty && total < 3 * avg) continue;
    out.add(AbuseAlert(
      kind: AbuseKind.heavyUser,
      user: a.user,
      sessions: [a],
      detail: 'A déjà consommé ${fmt(total)}',
    ));
  }
  return out;
}

// ── Bénéfice net ──────────────────────────────────────────────────────────

/// Un coût : mensuel (Starlink, électricité…) ou par ticket vendu (impression…).
class CostItem {
  const CostItem({required this.label, required this.amount, required this.perTicket});
  final String label;
  final int amount;
  final bool perTicket;

  Map<String, Object> toJson() => {'label': label, 'amount': amount, 'perTicket': perTicket};

  static CostItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final label = j['label'];
    final amount = j['amount'];
    if (label is! String || amount is! int) return null;
    return CostItem(label: label, amount: amount, perTicket: j['perTicket'] == true);
  }
}

/// Coûts enregistrés sur l'appareil, par routeur.
class CostStore {
  CostStore(this.sessionId);
  final String sessionId;
  String get _key => 'costs_$sessionId';

  Future<List<CostItem>> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List).map(CostItem.fromJson).whereType<CostItem>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<CostItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final i in items) i.toJson()]));
  }
}

/// Résultat d'un mois : encaissé − coûts mensuels − coûts par ticket.
class NetProfit {
  NetProfit({required this.revenue, required this.tickets, required List<CostItem> costs})
      : monthlyCosts = costs.where((c) => !c.perTicket).fold<int>(0, (a, c) => a + c.amount),
        perTicketCosts =
            costs.where((c) => c.perTicket).fold<int>(0, (a, c) => a + c.amount * tickets);

  final int revenue;
  final int tickets;
  final int monthlyCosts;
  final int perTicketCosts;

  int get totalCosts => monthlyCosts + perTicketCosts;
  int get net => revenue - totalCosts;

  /// Marge en % de l'encaissé ; null sans vente.
  double? get margin => revenue <= 0 ? null : net * 100 / revenue;

  static NetProfit forMonth(List<Sale> sales, DateTime month, List<CostItem> costs) {
    final (a, b) = SalesSummary.monthRange(month);
    final s = SalesSummary.of(sales, a, b);
    return NetProfit(revenue: s.total, tickets: s.count, costs: costs);
  }
}

// ── Vente rapide ──────────────────────────────────────────────────────────

/// Message à envoyer au client (WhatsApp, SMS…) pour un ticket.
String ticketMessage({
  required String network,
  required Voucher voucher,
  String loginAddress = '',
  String currency = 'FC',
}) {
  final b = StringBuffer('Wifi $network\n');
  b.writeln('Ticket ${voucher.profile}');
  if (voucher.separate) {
    b.writeln('Utilisateur : ${voucher.name}');
    b.writeln('Mot de passe : ${voucher.password}');
  } else {
    b.writeln('Code : ${voucher.name}');
  }
  if (voucher.uptime.isNotEmpty) b.writeln('Durée : ${voucher.uptime}');
  if (voucher.dataLimit.isNotEmpty) b.writeln('Données : ${voucher.dataLimit}');
  if (loginAddress.isNotEmpty) b.writeln('Connexion : http://$loginAddress');
  return b.toString().trimRight();
}
