// Modèles de données de l'application.

import 'services/speed.dart';
import 'util.dart';

final RegExp safeNamePattern = RegExp(r'^[A-Za-z0-9 _.\-]+$');
/// Taille de données saisie : `500M`, `1G`, `1.5G`, `100k`.
final RegExp dataPattern = RegExp(r'^[0-9]+(\.[0-9]+)?[kKmMgG]$');
final RegExp uptimePattern = RegExp(r'^([0-9]+[wdhms])+$');

/// Connexion enregistrée vers un routeur MikroTik.
class Session {
  Session({
    required this.id,
    required this.name,
    required this.host,
    this.port = 8728,
    this.useSsl = false,
    this.verifyCert = false,
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

  /// Vérifier le certificat SSL du routeur (refuse les certificats auto-signés).
  final bool verifyCert;
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
        'verifyCert': verifyCert,
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
        verifyCert: j['verifyCert'] as bool? ?? false,
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
    this.dataLimit = '',
    this.parentQueue = '',
    this.bindDevice = false,
  });

  final String id;
  final String name;

  /// Vitesse du profil, au format RouterOS : `envoi/réception`, éventuellement
  /// suivie de la rafale, du seuil, de la durée, de la priorité et du minimum
  /// garanti (voir `speed.dart`).
  final String rateLimit;
  final int sharedUsers;
  final int price;

  /// Limite de temps par défaut (ex. `1h`, `1d`, `7d`), proposée à la
  /// génération. Elle démarre à la première connexion du ticket.
  final String uptime;

  /// Limite de données par défaut (ex. `500M`, `1G`), proposée à la génération.
  /// Vide : illimitée.
  final String dataLimit;

  /// Vitesse maximale seule (sans rafale ni minimum), pour l'affichage.
  String get speedLabel => parseRateLimit(rateLimit).base;

  /// File parente (enveloppe de bande passante commune). Vide : aucune.
  final String parentQueue;

  /// Vrai : le ticket est lié au premier appareil qui s'y connecte (pas de
  /// partage possible ensuite).
  final bool bindDevice;

  static final RegExp _meta = RegExp(
      r'#mkm:price=(\d*);uptime=([0-9a-z]*)(?:;data=([0-9a-zA-Z.]*))?(?:;bind=(1))?');

  factory HotspotProfile.fromRow(Map<String, String> r) {
    final m = _meta.firstMatch(r['on-login'] ?? '');
    return HotspotProfile(
      id: r['.id'] ?? '',
      name: r['name'] ?? '',
      rateLimit: r['rate-limit'] ?? '',
      sharedUsers: int.tryParse(r['shared-users'] ?? '') ?? 1,
      price: int.tryParse(m?.group(1) ?? '') ?? 0,
      uptime: m?.group(2) ?? '',
      dataLimit: m?.group(3) ?? '',
      parentQueue: (r['parent-queue'] ?? '') == 'none' ? '' : (r['parent-queue'] ?? ''),
      bindDevice: m?.group(4) == '1',
    );
  }

  /// Script exécuté par le routeur à la première connexion d'un ticket :
  /// il enregistre la vente dans `/system script`, marque le ticket comme
  /// utilisé et programme son expiration.
  ///
  /// La limite de temps du ticket est lue sur le ticket lui-même
  /// (`limit-uptime`, choisie à la génération). Elle court à partir de la
  /// première connexion, même si l'utilisateur se déconnecte ensuite : un
  /// planificateur `mkm-e-<ticket>` démarre 2 secondes après la connexion,
  /// puis se répète à chaque durée. Son premier passage « arme » un marqueur
  /// (`mkm-a-<ticket>`), le second, une durée plus tard, supprime le ticket,
  /// sa session et le planificateur.
  String buildOnLogin() {
    assert(safeNamePattern.hasMatch(name));
    assert(uptime.isEmpty || uptimePattern.hasMatch(uptime));
    assert(dataLimit.isEmpty || dataPattern.hasMatch(dataLimit));
    final lines = <String>[
      '#mkm:price=$price;uptime=$uptime${dataLimit.isEmpty ? '' : ';data=$dataLimit'}'
          '${bindDevice ? ';bind=1' : ''}',
      r':local d [/system clock get date]',
      r':local t [/system clock get time]',
      r':local a [:tostr $address]',
      r':local m [:tostr $"mac-address"]',
      r':local c [/ip hotspot user get [find where name=$user] comment]',
      r':local lu [/ip hotspot user get [find where name=$user] limit-uptime]',
      r':if ([:len $c] > 3) do={',
      r':local p [:pick $c 0 3]',
      r':if ($p = "vc-" or $p = "up-") do={',
      r'/system script add name=([:tostr $d] . "-|-" . [:tostr $t] . "-|-" . $user . "-|-'
          '$price'
          r'-|-" . $a . "-|-" . $m . "-|-" . [:tostr $lu] . "-|-'
          '$name'
          r'-|-" . $c) owner="mkm" source=[:tostr $d] comment=mikhmon',
      r'/ip hotspot user set [find where name=$user] comment=("used-" . $c)',
      if (bindDevice)
        r':if ([:tostr [/ip hotspot user get [find where name=$user] mac-address]] = "00:00:00:00:00:00") do={/ip hotspot user set [find where name=$user] mac-address=$"mac-address"}',
      r':if ([:len $lu] > 0 and $lu > 00:00:00) do={',
      r':local ev (":if ([:len [/system script find where name=\"mkm-a-" . $user . "\"]] = 0) do={/system script add name=\"mkm-a-" . $user . "\" source=armed comment=mkm-a} else={/ip hotspot active remove [find where user=\"" . $user . "\"]; /ip hotspot user remove [find where name=\"" . $user . "\"]; /system script remove [find where name=\"mkm-a-" . $user . "\"]; /system scheduler remove [find where name=\"mkm-e-" . $user . "\"]}")',
      r':local st $t',
      r':do {:set st ([/system clock get time] + 00:00:02)} on-error={}',
      r':do {/system scheduler add name=("mkm-e-" . $user) interval=$lu start-date=$d start-time=$st on-event=$ev comment=mikhmon-exp} '
          r'on-error={/system scheduler add name=("mkm-e-" . $user) interval=$lu start-date=$d start-time=$t on-event=$ev comment=mikhmon-exp}',
      '}',
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
    this.dataLimit = '',
  });

  final String id;
  final String name;
  final String password;
  final String profile;
  final String comment;
  final int price;
  final String uptime;

  /// Libellé de la limite de données (ex. `1 Go`). Vide : illimitée.
  final String dataLimit;

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

/// Utilisateur (ticket) du hotspot, avec sa consommation.
class HotspotUser {
  const HotspotUser({
    required this.id,
    required this.name,
    required this.password,
    required this.profile,
    required this.comment,
    required this.disabled,
    required this.uptime,
    required this.limitUptime,
    required this.bytesIn,
    required this.bytesOut,
    required this.limitBytes,
    this.boundMac = '',
  });

  final String id;
  final String name;
  final String password;
  final String profile;
  final String comment;
  final bool disabled;

  /// Temps de connexion consommé et sa limite (null : illimité).
  final Duration uptime;
  final Duration? limitUptime;

  /// Données consommées (reçues + envoyées) et leur limite (0 : illimité).
  final int bytesIn;
  final int bytesOut;
  final int limitBytes;

  /// Appareil auquel le ticket est lié (vide : aucun).
  final String boundMac;

  factory HotspotUser.fromRow(Map<String, String> r) {
    final lu = parseRouterDuration(r['limit-uptime'] ?? '');
    return HotspotUser(
      id: r['.id'] ?? '',
      name: r['name'] ?? '',
      password: r['password'] ?? '',
      profile: r['profile'] ?? 'default',
      comment: r['comment'] ?? '',
      disabled: r['disabled'] == 'true' || r['disabled'] == 'yes',
      uptime: parseRouterDuration(r['uptime'] ?? '') ?? Duration.zero,
      limitUptime: (lu == null || lu == Duration.zero) ? null : lu,
      bytesIn: int.tryParse(r['bytes-in'] ?? '') ?? 0,
      bytesOut: int.tryParse(r['bytes-out'] ?? '') ?? 0,
      limitBytes: int.tryParse(r['limit-bytes-total'] ?? '') ?? 0,
      boundMac: (r['mac-address'] ?? '') == '00:00:00:00:00:00' ? '' : (r['mac-address'] ?? ''),
    );
  }

  int get bytesTotal => bytesIn + bytesOut;

  /// Ticket généré par l'application et jamais utilisé.
  bool get isNew =>
      (comment.startsWith('vc-') || comment.startsWith('up-')) &&
      uptime == Duration.zero &&
      bytesTotal == 0;

  /// Ticket déjà utilisé (première connexion faite, ou consommation non nulle).
  bool get isUsed => comment.startsWith('used-') || uptime > Duration.zero || bytesTotal > 0;

  /// Temps ou données épuisés.
  bool get isExhausted =>
      (limitUptime != null && uptime >= limitUptime!) ||
      (limitBytes > 0 && bytesTotal >= limitBytes);

  Duration? get timeLeft => limitUptime == null
      ? null
      : (limitUptime! > uptime ? limitUptime! - uptime : Duration.zero);

  int? get bytesLeft =>
      limitBytes <= 0 ? null : (limitBytes > bytesTotal ? limitBytes - bytesTotal : 0);
}

/// Vente enregistrée par le script on-login du profil.
class Sale {
  const Sale({
    this.id = '',
    required this.time,
    required this.user,
    required this.price,
    required this.address,
    required this.mac,
    required this.uptime,
    required this.profile,
    required this.comment,
  });

  /// Identifiant du script de vente sur le routeur (pour l'effacer).
  final String id;
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
  static Sale? tryParse(String name, {String id = ''}) {
    final p = name.split(separator);
    if (p.length < 8) return null;
    final time = parseRouterDateTime(p[0], p[1]);
    if (time == null) return null;
    return Sale(
      id: id,
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

/// État du routeur (`/system/resource`).
class RouterResource {
  const RouterResource({
    required this.cpuLoad,
    required this.freeMemory,
    required this.totalMemory,
    required this.uptime,
    required this.version,
    required this.board,
  });

  final int cpuLoad;
  final int freeMemory;
  final int totalMemory;
  final String uptime;
  final String version;
  final String board;

  int get usedMemory => totalMemory - freeMemory;
  double get memoryRatio => totalMemory <= 0 ? 0 : usedMemory / totalMemory;

  factory RouterResource.fromRow(Map<String, String> r) => RouterResource(
        cpuLoad: int.tryParse(r['cpu-load'] ?? '') ?? 0,
        freeMemory: int.tryParse(r['free-memory'] ?? '') ?? 0,
        totalMemory: int.tryParse(r['total-memory'] ?? '') ?? 0,
        uptime: r['uptime'] ?? '',
        version: r['version'] ?? '',
        board: r['board-name'] ?? r['platform'] ?? '',
      );
}

/// Débit instantané d'une interface, en bits par seconde.
class TrafficSample {
  const TrafficSample(this.rx, this.tx);
  final int rx;
  final int tx;
}

/// Ligne du journal du routeur.
class LogEntry {
  const LogEntry({required this.time, required this.topics, required this.message});
  final String time;
  final String topics;
  final String message;

  bool get isError => topics.contains('error') || topics.contains('critical');
  bool get isHotspot => topics.contains('hotspot');

  factory LogEntry.fromRow(Map<String, String> r) =>
      LogEntry(time: r['time'] ?? '', topics: r['topics'] ?? '', message: r['message'] ?? '');
}

/// Bail DHCP : un appareil connu du routeur.
class DhcpLease {
  const DhcpLease({
    required this.address,
    required this.mac,
    required this.hostName,
    required this.status,
    required this.comment,
  });
  final String address;
  final String mac;
  final String hostName;
  final String status;
  final String comment;

  factory DhcpLease.fromRow(Map<String, String> r) => DhcpLease(
        address: r['address'] ?? '',
        mac: r['mac-address'] ?? '',
        hostName: r['host-name'] ?? '',
        status: r['status'] ?? '',
        comment: r['comment'] ?? '',
      );
}

/// Adresse MAC au format `AA:BB:CC:11:22:33`.
final RegExp macPattern = RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$');

/// Appareil bloqué sur le hotspot.
class BlockedDevice {
  const BlockedDevice({required this.id, required this.mac, required this.comment});
  final String id;
  final String mac;
  final String comment;

  factory BlockedDevice.fromRow(Map<String, String> r) => BlockedDevice(
        id: r['.id'] ?? '',
        mac: r['mac-address'] ?? '',
        comment: r['comment'] ?? '',
      );
}

/// Enveloppe de bande passante commune à tous les clients.
class SharedBandwidth {
  const SharedBandwidth({required this.id, required this.target, required this.upBits, required this.downBits});
  final String id;
  final String target;

  /// Vitesses totales en bits par seconde (envoi / réception des clients).
  final int upBits;
  final int downBits;

  factory SharedBandwidth.fromRow(Map<String, String> r) {
    final parts = (r['max-limit'] ?? '').split('/');
    return SharedBandwidth(
      id: r['.id'] ?? '',
      target: r['target'] ?? '',
      upBits: parts.isNotEmpty ? (parseRateBits(parts[0]) ?? 0) : 0,
      downBits: parts.length > 1 ? (parseRateBits(parts[1]) ?? 0) : 0,
    );
  }
}

/// Réseau d'une adresse `10.5.50.1/24` : `10.5.50.0/24`. Null si invalide.
String? networkOf(String cidr) {
  final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)\.(\d+)/(\d+)$').firstMatch(cidr.trim());
  if (m == null) return null;
  final o = [for (var i = 1; i <= 4; i++) int.parse(m.group(i)!)];
  final prefix = int.parse(m.group(5)!);
  if (o.any((x) => x > 255) || prefix > 32) return null;
  final ip = (o[0] << 24) | (o[1] << 16) | (o[2] << 8) | o[3];
  final mask = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  final n = ip & mask;
  return '${(n >> 24) & 255}.${(n >> 16) & 255}.${(n >> 8) & 255}.${n & 255}/$prefix';
}
