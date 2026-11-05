import '../models.dart';
import '../util.dart';

/// Ce que l'on peut proposer pour réparer un ticket.
enum DiagAction { reactivate, extend, resetCounters, unbind, unblock, disconnect, replace }

/// Une constatation : [problem] vrai si elle peut expliquer l'échec du client.
class DiagFinding {
  const DiagFinding(this.text, {this.problem = false});
  final String text;
  final bool problem;
}

class Diagnosis {
  const Diagnosis({
    required this.code,
    required this.verdict,
    required this.findings,
    required this.actions,
    this.user,
    this.sales = const [],
    this.sessions = const [],
    this.blocked = const [],
    this.similar = const [],
  });

  final String code;
  final String verdict;
  final List<DiagFinding> findings;
  final Set<DiagAction> actions;
  final HotspotUser? user;
  final List<Sale> sales;
  final List<ActiveUser> sessions;

  /// Appareils bloqués liés à ce ticket.
  final List<BlockedDevice> blocked;

  /// Codes proches (faute de frappe possible).
  final List<String> similar;

  bool get hasProblem => findings.any((f) => f.problem);

  /// Profil à utiliser pour un ticket de remplacement.
  String get profile => user?.profile ?? (sales.isEmpty ? '' : sales.first.profile);
}

/// Vrai si [a] et [b] diffèrent d'une seule lettre, ou de deux lettres échangées.
bool _almostSame(String a, String b) {
  if (a == b) return false;
  if (a.length != b.length) return false;
  final diff = <int>[for (var i = 0; i < a.length; i++) if (a[i] != b[i]) i];
  if (diff.length == 1) return true;
  return diff.length == 2 && diff[1] == diff[0] + 1 && a[diff[0]] == b[diff[1]] && a[diff[1]] == b[diff[0]];
}

/// Cherche pourquoi un ticket ne fonctionne pas, à partir de ce que le routeur sait.
Diagnosis diagnoseTicket(
  String rawCode, {
  required List<HotspotUser> users,
  required List<Sale> sales,
  required List<ActiveUser> active,
  required List<BlockedDevice> blocked,
}) {
  final code = rawCode.trim();
  final findings = <DiagFinding>[];
  final actions = <DiagAction>{};

  HotspotUser? user;
  for (final u in users) {
    if (u.name == code) {
      user = u;
      break;
    }
  }
  final mySales = sales.where((s) => s.user == code).toList()..sort((a, b) => b.time.compareTo(a.time));
  final sessions = active.where((a) => a.user == code).toList();

  if (code.isEmpty) {
    return const Diagnosis(code: '', verdict: 'Tapez le code du ticket.', findings: [], actions: {});
  }

  if (user == null) {
    // Même code avec d'autres majuscules ?
    final lower = code.toLowerCase();
    final sameLetters = users.where((u) => u.name.toLowerCase() == lower).toList();
    if (sameLetters.isNotEmpty) {
      return Diagnosis(
        code: code,
        verdict: 'Majuscules ou minuscules différentes.',
        findings: [
          DiagFinding('Le code exact est « ${sameLetters.first.name} ». Le routeur distingue les majuscules '
              'des minuscules.', problem: true),
        ],
        actions: const {},
        similar: [sameLetters.first.name],
      );
    }
    final similar = [for (final u in users) if (_almostSame(code, u.name)) u.name].take(4).toList();
    if (mySales.isNotEmpty) {
      final s = mySales.first;
      findings.add(DiagFinding(
          'Vendu le ${formatDate(s.time)} à ${formatTime(s.time)} (${s.profile}, ${s.price}), puis supprimé du '
          'routeur : sa durée est terminée.',
          problem: true));
      actions.add(DiagAction.replace);
      return Diagnosis(
        code: code,
        verdict: 'Ticket expiré.',
        findings: findings,
        actions: actions,
        sales: mySales,
        similar: similar,
      );
    }
    findings.add(const DiagFinding('Ce code n\'existe pas sur le routeur et aucune vente ne le mentionne.',
        problem: true));
    if (similar.isNotEmpty) {
      findings.add(DiagFinding('Faute de frappe possible. Codes proches : ${similar.join(', ')}.'));
    }
    return Diagnosis(
      code: code,
      verdict: similar.isEmpty ? 'Code introuvable.' : 'Code introuvable, mais des codes proches existent.',
      findings: findings,
      actions: const {},
      similar: similar,
    );
  }

  final u = user;

  // Appareils concernés par ce ticket.
  final macs = <String>{
    if (u.boundMac.isNotEmpty && u.boundMac != '00:00:00:00:00:00') u.boundMac.toUpperCase(),
    for (final s in sessions) if (s.mac.isNotEmpty) s.mac.toUpperCase(),
    for (final s in mySales) if (s.mac.isNotEmpty) s.mac.toUpperCase(),
  };
  final blockedHere = [for (final b in blocked) if (macs.contains(b.mac.toUpperCase())) b];
  if (blockedHere.isNotEmpty) {
    findings.add(DiagFinding(
        'L\'appareil ${blockedHere.map((b) => b.mac).join(', ')} est bloqué : il ne peut plus se connecter.',
        problem: true));
    actions.add(DiagAction.unblock);
  }

  if (u.disabled) {
    findings.add(const DiagFinding('Le ticket est désactivé.', problem: true));
    actions.add(DiagAction.reactivate);
  }

  final timeOut = u.limitUptime != null && u.uptime >= u.limitUptime!;
  final dataOut = u.limitBytes > 0 && u.bytesTotal >= u.limitBytes;
  if (timeOut) {
    findings.add(DiagFinding('Le temps est épuisé (${formatDuration(u.uptime)} utilisés).', problem: true));
  }
  if (dataOut) {
    findings.add(DiagFinding('Les données sont épuisées (${formatBytes(u.bytesTotal)} utilisés).', problem: true));
  }
  if (timeOut || dataOut) {
    actions.addAll({DiagAction.extend, DiagAction.resetCounters, DiagAction.replace});
  }

  if (u.boundMac.isNotEmpty && u.boundMac != '00:00:00:00:00:00') {
    final onOther = sessions.isEmpty;
    findings.add(DiagFinding(
        'Le ticket est lié à l\'appareil ${u.boundMac} : il ne marche que sur celui-ci. '
        '${onOther ? 'Si le client a changé de téléphone, libérez l\'appareil.' : ''}'.trim(),
        problem: onOther));
    actions.add(DiagAction.unbind);
  }

  if (u.password.isNotEmpty && u.password != u.name) {
    findings.add(DiagFinding('Le mot de passe est différent du code : « ${u.password} ».'));
  }

  if (sessions.isNotEmpty) {
    findings.add(DiagFinding('Connecté en ce moment : '
        '${sessions.map((s) => '${s.address} (${s.mac})').join(', ')}.'));
    actions.add(DiagAction.disconnect);
  }

  if (u.isNew) {
    findings.add(const DiagFinding('Neuf : jamais utilisé.'));
  } else if (!timeOut && !dataOut) {
    final left = <String>[
      if (u.timeLeft != null) 'temps restant ${formatDuration(u.timeLeft!)}',
      if (u.bytesLeft != null) 'données restantes ${formatBytes(u.bytesLeft!)}',
    ];
    if (left.isNotEmpty) findings.add(DiagFinding('Valide : ${left.join(', ')}.'));
  }
  if (mySales.isNotEmpty) {
    final s = mySales.first;
    findings.add(DiagFinding('Vendu le ${formatDate(s.time)} à ${formatTime(s.time)}.'));
  }

  actions.add(DiagAction.replace);
  final problems = findings.where((f) => f.problem).length;
  return Diagnosis(
    code: code,
    verdict: problems == 0
        ? 'Le ticket est valide.'
        : problems == 1
            ? 'Un problème trouvé.'
            : '$problems problèmes trouvés.',
    findings: findings,
    actions: actions,
    user: u,
    sales: mySales,
    sessions: sessions,
    blocked: blockedHere,
    similar: const [],
  );
}

/// Conseils quand le ticket est valide mais que le client n'arrive pas à se connecter.
const List<String> validTicketTips = [
  'Vérifier que le téléphone est bien sur le wifi de la zone, pas sur les données mobiles.',
  'Ouvrir une page en http (ex. neverssl.com) pour faire apparaître la page de connexion.',
  'Désactiver « DNS privé » et le VPN sur le téléphone.',
  'Retaper le code sans espace ni confusion entre 0 et O, 1 et l.',
];
