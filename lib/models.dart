// Modèles de données de l'application.

final RegExp safeNamePattern = RegExp(r'^[A-Za-z0-9 _.\-]+$');
final RegExp uptimePattern = RegExp(r'^([0-9]+[wdhms])+$');

/// Connexion enregistrée vers un routeur MikroTik.
class Session {
  Session({
    required this.id,
    required this.name,
    required this.host,
    this.port = 8728,
    this.useSsl = false,
    required this.username,
    this.password = '',
    this.currency = 'FC',
    this.dnsName = '',
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final bool useSsl;
  final String username;
  final String password;
  final String currency;

  /// Nom DNS / adresse de la page de connexion du hotspot (pour le QR code).
  final String dnsName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'useSsl': useSsl,
        'username': username,
        'currency': currency,
        'dnsName': dnsName,
      };

  factory Session.fromJson(Map<String, dynamic> j, {String password = ''}) =>
      Session(
        id: j['id'] as String,
        name: j['name'] as String,
        host: j['host'] as String,
        port: (j['port'] as num?)?.toInt() ?? 8728,
        useSsl: j['useSsl'] as bool? ?? false,
        username: j['username'] as String? ?? 'admin',
        password: password,
        currency: j['currency'] as String? ?? 'FC',
        dnsName: j['dnsName'] as String? ?? '',
      );
}

/// Profil d'utilisateur hotspot (débit, utilisateurs simultanés, prix, durée).
///
/// Le prix et la durée sont mémorisés dans le script « on-login » du profil,
/// sur une ligne de commentaire `#mkm:price=...;uptime=...`.
class HotspotProfile {
  const HotspotProfile({
    this.id = '',
    required this.name,
    this.rateLimit = '',
    this.sharedUsers = 1,
    this.price = 0,
    this.uptime = '',
    this.validity = '',
  });

  final String id;
  final String name;
  final String rateLimit;
  final int sharedUsers;
  final int price;

  /// Durée de connexion au format RouterOS (ex. `1h`, `24h`, `7d`).
  final String uptime;

  /// Validité en temps calendaire à partir de la première connexion
  /// (ex. `7d`, `30d`). Vide : pas d'expiration calendaire.
  final String validity;

  static final RegExp _meta =
      RegExp(r'#mkm:price=(\d*);uptime=([0-9a-z]*)(?:;validity=([0-9a-z]*))?');

  factory HotspotProfile.fromRow(Map<String, String> r) {
    final m = _meta.firstMatch(r['on-login'] ?? '');
    return HotspotProfile(
      id: r['.id'] ?? '',
      name: r['name'] ?? '',
      rateLimit: r['rate-limit'] ?? '',
      sharedUsers: int.tryParse(r['shared-users'] ?? '') ?? 1,
      price: int.tryParse(m?.group(1) ?? '') ?? 0,
      uptime: m?.group(2) ?? '',
      validity: m?.group(3) ?? '',
    );
  }

  /// Script exécuté par le routeur à la première connexion d'un ticket :
  /// il enregistre la vente dans `/system script`, marque le ticket comme
  /// utilisé et, si le profil a une validité, programme son expiration.
  ///
  /// Expiration : un planificateur `mkm-e-<ticket>` démarre 2 secondes après
  /// la première connexion, puis se répète à chaque [validity]. Son premier
  /// passage « arme » un marqueur (`mkm-a-<ticket>`), le second, une validité
  /// plus tard, supprime le ticket, sa session et le planificateur.
  String buildOnLogin() {
    assert(safeNamePattern.hasMatch(name));
    assert(uptime.isEmpty || uptimePattern.hasMatch(uptime));
    assert(validity.isEmpty || uptimePattern.hasMatch(validity));
    final lines = <String>[
      '#mkm:price=$price;uptime=$uptime;validity=$validity',
      r':local d [/system clock get date]',
      r':local t [/system clock get time]',
      r':local a [:tostr $address]',
      r':local m [:tostr $"mac-address"]',
      r':local c [/ip hotspot user get [find where name=$user] comment]',
      r':if ([:len $c] > 3) do={',
      r':local p [:pick $c 0 3]',
      r':if ($p = "vc-" or $p = "up-") do={',
      r'/system script add name=([:tostr $d] . "-|-" . [:tostr $t] . "-|-" . $user . "-|-' +
          '$price' +
          r'-|-" . $a . "-|-" . $m . "-|-' +
          '$uptime-|-$name' +
          r'-|-" . $c) owner="mkm" source=[:tostr $d] comment=mikhmon',
      r'/ip hotspot user set [find where name=$user] comment=("used-" . $c)',
      if (validity.isNotEmpty) ...[
        r':local ev (":if ([:len [/system script find where name=\"mkm-a-" . $user . "\"]] = 0) do={/system script add name=\"mkm-a-" . $user . "\" source=armed comment=mkm-a} else={/ip hotspot active remove [find where user=\"" . $user . "\"]; /ip hotspot user remove [find where name=\"" . $user . "\"]; /system script remove [find where name=\"mkm-a-" . $user . "\"]; /system scheduler remove [find where name=\"mkm-e-" . $user . "\"]}")',
        r':local st $t',
        r':do {:set st ([/system clock get time] + 00:00:02)} on-error={}',
        ':do {/system scheduler add name=("mkm-e-" . \$user) interval=$validity start-date=\$d start-time=\$st on-event=\$ev comment=mikhmon-exp} '
            'on-error={/system scheduler add name=("mkm-e-" . \$user) interval=$validity start-date=\$d start-time=\$t on-event=\$ev comment=mikhmon-exp}',
      ],
      '}',
      '}',
    ];
    return '${lines.join('\n')}\n';
  }
}

/// Ticket (utilisateur hotspot) généré.
class Voucher {
  const Voucher({
    this.id = '',
    required this.name,
    required this.password,
    required this.profile,
    this.comment = '',
    this.price = 0,
    this.uptime = '',
    this.validity = '',
  });

  final String id;
  final String name;
  final String password;
  final String profile;
  final String comment;
  final int price;
  final String uptime;
  final String validity;

  /// Vrai si le ticket a un identifiant ET un mot de passe distincts.
  bool get separate => password != name;
}

/// Utilisateur actuellement connecté au hotspot.
class ActiveUser {
  const ActiveUser({
    required this.id,
    required this.user,
    required this.address,
    required this.mac,
    required this.uptime,
    required this.bytesIn,
    required this.bytesOut,
  });

  final String id;
  final String user;
  final String address;
  final String mac;
  final String uptime;
  final int bytesIn;
  final int bytesOut;

  factory ActiveUser.fromRow(Map<String, String> r) => ActiveUser(
        id: r['.id'] ?? '',
        user: r['user'] ?? '',
        address: r['address'] ?? '',
        mac: r['mac-address'] ?? '',
        uptime: r['uptime'] ?? '',
        bytesIn: int.tryParse(r['bytes-in'] ?? '') ?? 0,
        bytesOut: int.tryParse(r['bytes-out'] ?? '') ?? 0,
      );
}

/// Vente enregistrée par le script on-login du profil.
class Sale {
  const Sale({
    required this.time,
    required this.user,
    required this.price,
    required this.address,
    required this.mac,
    required this.uptime,
    required this.profile,
    required this.comment,
  });

  final DateTime time;
  final String user;
  final int price;
  final String address;
  final String mac;
  final String uptime;
  final String profile;
  final String comment;

  static const String separator = '-|-';

  /// Analyse le nom d'un script de vente :
  /// `date-|-heure-|-user-|-prix-|-ip-|-mac-|-durée-|-profil-|-commentaire`.
  static Sale? tryParse(String name) {
    final p = name.split(separator);
    if (p.length < 8) return null;
    final time = parseRouterDateTime(p[0], p[1]);
    if (time == null) return null;
    return Sale(
      time: time,
      user: p[2],
      price: int.tryParse(p[3]) ?? 0,
      address: p[4],
      mac: p[5],
      uptime: p[6],
      profile: p[7],
      comment: p.length > 8 ? p.sublist(8).join(separator) : '',
    );
  }
}

const Map<String, int> _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// Lit la date/heure du routeur : `nov/02/2026` (RouterOS 6) ou
/// `2026-11-02` (RouterOS 7), avec l'heure `hh:mm:ss`.
DateTime? parseRouterDateTime(String date, String time) {
  int? y;
  int? mo;
  int? d;
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
  if (iso != null) {
    y = int.parse(iso.group(1)!);
    mo = int.parse(iso.group(2)!);
    d = int.parse(iso.group(3)!);
  } else {
    final parts = date.split('/');
    if (parts.length == 3) {
      mo = _months[parts[0].toLowerCase()];
      d = int.tryParse(parts[1]);
      y = int.tryParse(parts[2]);
    }
  }
  final t = time.split(':');
  if (y == null || mo == null || d == null || t.length < 2) return null;
  final h = int.tryParse(t[0]);
  final mi = int.tryParse(t[1]);
  final s = t.length > 2 ? int.tryParse(t[2]) ?? 0 : 0;
  if (h == null || mi == null) return null;
  return DateTime(y, mo, d, h, mi, s);
}
