import '../models.dart';
import '../routeros/api_client.dart';
import 'speed.dart';

/// État du routeur utile avant d'installer un hotspot.
class RouterFacts {
  const RouterFacts({
    this.interfaces = const [],
    this.hotspots = const [],
    this.addresses = const [],
    this.dhcpServers = const [],
    this.hasMasquerade = false,
    this.services = const [],
    this.users = const [],
    this.hasInstallLog = false,
  });

  /// Noms des interfaces (`ether1`, `wlan1`, `bridge`…).
  final List<String> interfaces;

  /// Hotspots existants : `name`, `interface`.
  final List<Map<String, String>> hotspots;

  /// Adresses IP : `address` (`192.168.88.1/24`), `interface`.
  final List<Map<String, String>> addresses;

  /// Serveurs DHCP : `name`, `interface`, `address-pool`.
  final List<Map<String, String>> dhcpServers;

  /// Une règle de partage de connexion (masquerade) existe déjà.
  final bool hasMasquerade;

  /// Services du routeur : `.id`, `name`, `disabled`.
  final List<Map<String, String>> services;

  /// Comptes du routeur : `name`.
  final List<Map<String, String>> users;

  /// Une installation précédente de l'application peut être annulée.
  final bool hasInstallLog;
}

/// Un profil de vente à créer avec le hotspot.
class SetupProfile {
  const SetupProfile({required this.name, required this.price, required this.uptime});
  final String name;
  final int price;
  final String uptime;
}

/// Choix de l'utilisateur pour un nouveau hotspot.
class HotspotSetup {
  const HotspotSetup({
    required this.lanInterface,
    this.wanInterface = '',
    this.lanAddress = '10.5.50.1/24',
    this.dnsName = '',
    this.dnsServers = '8.8.8.8,1.1.1.1',
    this.adminUser = 'admin',
    this.adminPassword = '',
    this.closeInsecureServices = true,
    this.profiles = const [],
  });

  /// Interface du réseau des clients (wifi + prises, souvent `bridge`).
  final String lanInterface;

  /// Interface qui reçoit Internet (Starlink…), pour le partage de connexion.
  final String wanInterface;

  /// Adresse du routeur sur le réseau des clients, utilisée seulement si
  /// l'interface n'en a pas déjà une.
  final String lanAddress;
  final String dnsName;
  final String dnsServers;
  final String adminUser;

  /// Nouveau mot de passe du compte administrateur ; vide : inchangé.
  final String adminPassword;

  /// Désactive telnet, ftp et l'interface web, rarement utiles et risqués.
  final bool closeInsecureServices;
  final List<SetupProfile> profiles;
}

/// Une étape de l'installation : une commande du routeur ou un profil à créer.
class SetupStep {
  const SetupStep(
    this.title, {
    this.words = const [],
    this.profile,
    this.undoPath,
    this.secret = false,
  });

  final String title;
  final List<String> words;
  final HotspotProfile? profile;

  /// Commande qui supprime l'élément créé (`/ip/hotspot/remove`), si possible.
  final String? undoPath;

  /// L'étape contient un mot de passe : on ne l'affiche pas.
  final bool secret;
}

/// Plage d'adresses à distribuer dans [cidr] : du 10e au dernier hôte moins un.
/// Null si le réseau est trop petit.
String? poolRange(String cidr) {
  final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)\.(\d+)/(\d+)$').firstMatch(cidr.trim());
  if (m == null) return null;
  final prefix = int.parse(m.group(5)!);
  if (prefix < 8 || prefix > 29) return null;
  final o = [for (var i = 1; i <= 4; i++) int.parse(m.group(i)!)];
  if (o.any((x) => x > 255)) return null;
  final ip = (o[0] << 24) | (o[1] << 16) | (o[2] << 8) | o[3];
  final mask = (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  final net = ip & mask;
  final broadcast = net | (~mask & 0xFFFFFFFF);
  String s(int v) => '${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}';
  return '${s(net + 10)}-${s(broadcast - 1)}';
}

final RegExp _dnsNamePattern = RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9.\-]*[a-zA-Z0-9])?$');

/// Prépare les étapes de l'installation. Lève [RouterOsException] avec un
/// message clair si le routeur ou les choix ne conviennent pas.
List<SetupStep> planHotspotSetup(HotspotSetup s, RouterFacts f) {
  if (!f.interfaces.contains(s.lanInterface)) {
    throw RouterOsException('L\'interface « ${s.lanInterface} » n\'existe pas sur ce routeur.');
  }
  if (f.hotspots.isNotEmpty) {
    final h = f.hotspots.first;
    throw RouterOsException(
        'Un hotspot existe déjà (${h['name'] ?? '?'} sur ${h['interface'] ?? '?'}). '
        'L\'assistant ne s\'applique qu\'à un routeur sans hotspot.');
  }
  if (s.wanInterface.isNotEmpty && s.wanInterface == s.lanInterface) {
    throw RouterOsException('L\'interface Internet et celle des clients doivent être différentes.');
  }
  if (!f.hasMasquerade && s.wanInterface.isEmpty) {
    throw RouterOsException(
        'Le routeur ne partage pas encore sa connexion Internet : choisissez l\'interface Internet.');
  }
  if (s.dnsName.isNotEmpty && !_dnsNamePattern.hasMatch(s.dnsName)) {
    throw RouterOsException('Adresse de connexion invalide. Exemple : wifi.local');
  }
  if (s.adminPassword.isNotEmpty && s.adminPassword.length < 8) {
    throw RouterOsException('Le mot de passe administrateur doit avoir au moins 8 caractères.');
  }
  for (final p in s.profiles) {
    if (!safeNamePattern.hasMatch(p.name)) {
      throw RouterOsException('Nom de profil invalide : ${p.name}');
    }
    if (p.uptime.isNotEmpty && !uptimePattern.hasMatch(p.uptime)) {
      throw RouterOsException('Durée invalide pour ${p.name}. Exemples : 1h, 1d, 7d.');
    }
  }

  final steps = <SetupStep>[];

  // Adresse du routeur sur le réseau des clients : on garde celle qui existe
  // (la changer couperait la connexion de l'application).
  Map<String, String>? existing;
  for (final a in f.addresses) {
    if (a['interface'] == s.lanInterface) {
      existing = a;
      break;
    }
  }
  final String cidr;
  if (existing != null) {
    cidr = existing['address'] ?? '';
  } else {
    if (networkOf(s.lanAddress) == null) {
      throw RouterOsException('Adresse du routeur invalide. Exemple : 10.5.50.1/24');
    }
    cidr = s.lanAddress;
    steps.add(SetupStep(
      'Donner l\'adresse $cidr au routeur sur ${s.lanInterface}',
      words: ['/ip/address/add', '=address=$cidr', '=interface=${s.lanInterface}'],
      undoPath: '/ip/address/remove',
    ));
  }
  final network = networkOf(cidr);
  if (network == null) {
    throw RouterOsException('L\'adresse du réseau des clients n\'est pas valable : $cidr');
  }
  final lanIp = cidr.split('/').first;

  // Distribution des adresses.
  String pool = '';
  for (final d in f.dhcpServers) {
    if (d['interface'] == s.lanInterface) {
      pool = d['address-pool'] ?? '';
      break;
    }
  }
  if (pool.isEmpty || pool == 'static-only') {
    final range = poolRange(cidr);
    if (range == null) throw RouterOsException('Le réseau $network est trop petit pour un hotspot.');
    pool = 'mkm-pool';
    steps.addAll([
      SetupStep('Créer la plage d\'adresses $range',
          words: ['/ip/pool/add', '=name=mkm-pool', '=ranges=$range'], undoPath: '/ip/pool/remove'),
      SetupStep('Distribuer ces adresses aux clients',
          words: [
            '/ip/dhcp-server/add',
            '=name=mkm-dhcp',
            '=interface=${s.lanInterface}',
            '=address-pool=mkm-pool',
            '=lease-time=1h',
          ],
          undoPath: '/ip/dhcp-server/remove'),
      SetupStep('Indiquer la passerelle et le DNS aux clients',
          words: [
            '/ip/dhcp-server/network/add',
            '=address=$network',
            '=gateway=$lanIp',
            '=dns-server=$lanIp',
          ],
          undoPath: '/ip/dhcp-server/network/remove'),
    ]);
  }

  steps.add(SetupStep('Régler le DNS du routeur (${s.dnsServers})', words: [
    '/ip/dns/set',
    '=servers=${s.dnsServers}',
    '=allow-remote-requests=yes',
  ]));

  if (!f.hasMasquerade) {
    steps.add(SetupStep(
      'Partager la connexion Internet de ${s.wanInterface} avec les clients',
      words: [
        '/ip/firewall/nat/add',
        '=chain=srcnat',
        '=action=masquerade',
        '=out-interface=${s.wanInterface}',
        '=comment=mkm',
      ],
      undoPath: '/ip/firewall/nat/remove',
    ));
  }

  steps.add(SetupStep(
    'Créer les réglages du hotspot',
    words: [
      '/ip/hotspot/profile/add',
      '=name=mkm-hsprof',
      '=hotspot-address=$lanIp',
      if (s.dnsName.isNotEmpty) '=dns-name=${s.dnsName}',
      '=login-by=cookie,http-chap',
    ],
    undoPath: '/ip/hotspot/profile/remove',
  ));
  steps.add(SetupStep(
    'Activer le hotspot sur ${s.lanInterface}',
    words: [
      '/ip/hotspot/add',
      '=name=mkm-hotspot',
      '=interface=${s.lanInterface}',
      '=address-pool=$pool',
      '=profile=mkm-hsprof',
    ],
    undoPath: '/ip/hotspot/remove',
  ));

  for (final p in s.profiles) {
    steps.add(SetupStep(
      'Créer le profil ${p.name} (${p.price} ${p.uptime.isEmpty ? '' : '· ${p.uptime}'})',
      profile: HotspotProfile(name: p.name, price: p.price, uptime: p.uptime),
      undoPath: '/ip/hotspot/user/profile/remove',
    ));
  }

  if (s.closeInsecureServices) {
    for (final name in const ['telnet', 'ftp', 'www']) {
      for (final svc in f.services) {
        if (svc['name'] == name && svc['disabled'] != 'true' && svc['disabled'] != 'yes') {
          steps.add(SetupStep('Désactiver le service $name',
              words: ['/ip/service/set', '=.id=${svc['.id']}', '=disabled=yes']));
        }
      }
    }
  }

  if (s.adminPassword.isNotEmpty) {
    if (!f.users.any((u) => u['name'] == s.adminUser)) {
      throw RouterOsException('Le compte « ${s.adminUser} » n\'existe pas sur ce routeur.');
    }
    steps.add(SetupStep(
      'Changer le mot de passe du compte ${s.adminUser}',
      words: ['/user/set', '=numbers=${s.adminUser}', '=password=${s.adminPassword}'],
      secret: true,
    ));
  }
  return steps;
}
