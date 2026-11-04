import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mtandao_ticket/routeros/api_client.dart';

/// Faux routeur MikroTik pour les tests : il parle le protocole API sur une
/// vraie connexion TCP locale et garde en mémoire les profils, tickets,
/// utilisateurs actifs et scripts de vente.
///
/// Il ne peut PAS exécuter le script « on-login » d'un profil : la méthode
/// [simulateFirstLogin] reproduit seulement ce que ce script doit produire.
/// Le vrai script reste à valider sur un vrai routeur.
class FakeRouter {
  FakeRouter._(this._server, this.md5Login, this.users);

  final ServerSocket _server;

  /// Vrai : identification par défi MD5 (RouterOS avant 6.43).
  final bool md5Login;

  /// Comptes autorisés : identifiant -> mot de passe.
  final Map<String, String> users;

  final List<Socket> _connections = [];
  int _nextId = 1;
  int connectionCount = 0;
  int commandCount = 0;

  final List<Map<String, String>> profiles = [];
  final List<Map<String, String>> hotspotUsers = [];
  final List<Map<String, String>> active = [];
  final List<Map<String, String>> scripts = [];
  final List<Map<String, String>> logLines = [];
  final List<String> savedFiles = [];
  final List<Map<String, String>> leases = [];
  final List<Map<String, String>> bindings = [];
  final List<Map<String, String>> queues = [];
  final List<Map<String, String>> firewall = [];
  final List<Map<String, String>> hotspots = [];
  final List<Map<String, String>> addresses = [];
  Map<String, String> resource = {
    'cpu-load': '7',
    'free-memory': '60000000',
    'total-memory': '128000000',
    'uptime': '3d4h',
    'version': '7.15 (stable)',
    'board-name': 'hAP ac2',
  };
  final List<Map<String, String>> interfaces = [
    {'name': 'ether1', 'running': 'true', 'disabled': 'false'},
    {'name': 'wlan1', 'running': 'true', 'disabled': 'false'},
    {'name': 'ether5', 'running': 'false', 'disabled': 'false'},
  ];

  /// Date renvoyée par `/system clock` pour [simulateFirstLogin].
  String clockDate = 'nov/03/2026';
  String clockTime = '08:30:00';

  int get port => _server.port;

  static Future<FakeRouter> start({
    bool md5Login = false,
    Map<String, String>? users,
  }) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final r = FakeRouter._(server, md5Login, users ?? {'admin': 'secret'});
    server.listen(r._serve);
    return r;
  }

  Future<void> stop() async {
    dropConnections();
    await _server.close();
  }

  /// Coupe toutes les connexions ouvertes (veille du téléphone, VPN coupé).
  void dropConnections() {
    for (final c in _connections) {
      c.destroy();
    }
    _connections.clear();
  }

  String _newId() => '*${(_nextId++).toRadixString(16).toUpperCase()}';

  Future<void> _serve(Socket socket) async {
    connectionCount++;
    _connections.add(socket);
    final queue = ByteQueue();
    final reader = ApiReader(queue);
    socket.listen(queue.add, onDone: queue.close, onError: queue.fail);
    final conn = _Conn();
    try {
      while (true) {
        final words = await reader.readSentence();
        if (words.isEmpty) continue;
        for (final sentence in _handle(words, conn)) {
          socket.add(encodeSentence(sentence));
        }
        await socket.flush();
      }
    } catch (_) {
      socket.destroy();
    }
  }

  List<List<String>> _trap(String message) => [
        ['!trap', '=message=$message'],
        ['!done'],
      ];

  List<List<String>> _rows(List<Map<String, String>> rows) => [
        for (final r in rows)
          ['!re', ...r.entries.map((e) => '=${e.key}=${e.value}')],
        ['!done'],
      ];

  List<List<String>> _handle(List<String> words, _Conn conn) {
    final cmd = words.first;
    final attrs = parseAttributes(words);
    if (cmd == '/login') return _login(attrs, conn);
    if (!conn.loggedIn) {
      return [
        ['!fatal', 'not logged in']
      ];
    }
    commandCount++;
    final queries = {
      for (final w in words.skip(1))
        if (w.startsWith('?') && w.contains('='))
          w.substring(1, w.indexOf('=')): w.substring(w.indexOf('=') + 1)
    };
    switch (cmd) {
      case '/ip/hotspot/user/profile/print':
        return _rows(profiles);
      case '/ip/hotspot/user/profile/add':
        if (profiles.any((p) => p['name'] == attrs['name'])) {
          return _trap('failure: profile with the same name already exists');
        }
        profiles.add({'.id': _newId(), ...attrs});
        return [
          ['!done', '=ret=${profiles.last['.id']}']
        ];
      case '/ip/hotspot/user/profile/set':
        return _update(profiles, attrs);
      case '/ip/hotspot/user/profile/remove':
        return _remove(profiles, attrs['.id']);
      case '/ip/hotspot/user/add':
        if (hotspotUsers.any((u) => u['name'] == attrs['name'])) {
          return _trap('failure: already have user with this name for this server');
        }
        hotspotUsers.add({'.id': _newId(), ...attrs});
        return [
          ['!done', '=ret=${hotspotUsers.last['.id']}']
        ];
      case '/ip/hotspot/user/print':
        return _rows(hotspotUsers);
      case '/ip/hotspot/user/set':
        return _update(hotspotUsers, attrs);
      case '/ip/hotspot/user/reset-counters':
        {
          final i = hotspotUsers.indexWhere((u) => u['.id'] == attrs['.id']);
          if (i < 0) return _trap('no such item (4)');
          hotspotUsers[i] = {...hotspotUsers[i], 'uptime': '0s', 'bytes-in': '0', 'bytes-out': '0'};
          return [
            ['!done']
          ];
        }
      case '/ip/hotspot/user/remove':
        return _remove(hotspotUsers, attrs['.id']);
      case '/ip/hotspot/active/print':
        return _rows(active);
      case '/ip/hotspot/active/remove':
        return _remove(active, attrs['.id']);
      case '/system/backup/save':
        savedFiles.add('${attrs['name']}.backup');
        return [
          ['!done']
        ];
      case '/export':
        savedFiles.add('${attrs['file']}.rsc');
        return [
          ['!done']
        ];
      case '/system/resource/print':
        return _rows([resource]);
      case '/interface/print':
        return _rows(interfaces);
      case '/interface/monitor-traffic':
        return _rows([
          {'name': attrs['interface'] ?? '', 'rx-bits-per-second': '1500000', 'tx-bits-per-second': '250000'}
        ]);
      case '/log/print':
        return _rows(logLines);
      case '/ip/dhcp-server/lease/print':
        return _rows(leases);
      case '/ip/hotspot/ip-binding/print':
        return _rows(bindings
            .where((b) => queries.entries.every((q) => b[q.key] == q.value))
            .toList());
      case '/ip/hotspot/ip-binding/add':
        bindings.add({'.id': _newId(), ...attrs});
        return [
          ['!done', '=ret=${bindings.last['.id']}']
        ];
      case '/ip/hotspot/ip-binding/remove':
        return _remove(bindings, attrs['.id']);
      case '/queue/simple/print':
        return _rows(queues
            .where((q) => queries.entries.every((e) => q[e.key] == e.value))
            .toList());
      case '/queue/simple/add':
        queues.add({'.id': _newId(), ...attrs});
        return [
          ['!done', '=ret=${queues.last['.id']}']
        ];
      case '/queue/simple/set':
        return _update(queues, attrs);
      case '/queue/simple/remove':
        return _remove(queues, attrs['.id']);
      case '/ip/firewall/filter/print':
        return _rows(firewall
            .where((q) => queries.entries.every((e) => q[e.key] == e.value))
            .toList());
      case '/ip/firewall/filter/add':
        {
          final before = attrs.remove('place-before');
          final row = {'.id': _newId(), ...attrs};
          final i = before == null ? -1 : firewall.indexWhere((r) => r['.id'] == before);
          if (i >= 0) {
            firewall.insert(i, row);
          } else {
            firewall.add(row);
          }
          return [
            ['!done', '=ret=${row['.id']}']
          ];
        }
      case '/ip/firewall/filter/set':
        return _update(firewall, attrs);
      case '/ip/firewall/filter/remove':
        return _remove(firewall, attrs['.id']);
      case '/ip/hotspot/print':
        return _rows(hotspots);
      case '/ip/address/print':
        return _rows(addresses
            .where((q) => queries.entries.every((e) => q[e.key] == e.value))
            .toList());
      case '/system/script/remove':
        return _remove(scripts, attrs['.id']);
      case '/system/script/print':
        return _rows(scripts
            .where((s) => queries.entries.every((q) => s[q.key] == q.value))
            .toList());
    }
    return _trap('no such command');
  }

  List<List<String>> _login(Map<String, String> attrs, _Conn conn) {
    final name = attrs['name'] ?? '';
    final password = users[name];
    if (md5Login) {
      final response = attrs['response'];
      if (response == null) {
        conn.challenge = List<int>.generate(16, (i) => (i * 17 + 3) & 0xFF);
        final hex =
            conn.challenge!.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        return [
          ['!done', '=ret=$hex']
        ];
      }
      if (password != null && conn.challenge != null) {
        final digest =
            md5.convert([0, ...utf8.encode(password), ...conn.challenge!]).toString();
        if (response == '00$digest') {
          conn.loggedIn = true;
          return [
            ['!done']
          ];
        }
      }
      return _trap('cannot log in');
    }
    if (password != null && password == attrs['password']) {
      conn.loggedIn = true;
      return [
        ['!done']
      ];
    }
    return _trap('invalid user name or password (6)');
  }

  List<List<String>> _update(
      List<Map<String, String>> table, Map<String, String> attrs) {
    final i = table.indexWhere((r) => r['.id'] == attrs['.id']);
    if (i < 0) return _trap('no such item (4)');
    table[i] = {
      ...table[i],
      for (final e in attrs.entries)
        if (e.key != '.id') e.key: e.value,
    };
    return [
      ['!done']
    ];
  }

  List<List<String>> _remove(List<Map<String, String>> table, String? id) {
    final i = table.indexWhere((r) => r['.id'] == id);
    if (i < 0) return _trap('no such item (4)');
    table.removeAt(i);
    return [
      ['!done']
    ];
  }

  /// Reproduit l'effet attendu du script « on-login » à la première
  /// connexion d'un ticket : une ligne de vente est ajoutée et le ticket est
  /// marqué utilisé. Pour un ticket déjà utilisé, rien ne se passe.
  void simulateFirstLogin(String userName, {String ip = '10.5.50.20'}) {
    final u = hotspotUsers.firstWhere((u) => u['name'] == userName);
    final comment = u['comment'] ?? '';
    final profile = profiles.firstWhere((p) => p['name'] == u['profile']);
    final meta = RegExp(r'#mkm:price=(\d*);uptime=([0-9a-z]*)')
        .firstMatch(profile['on-login'] ?? '');
    active.add({
      '.id': _newId(),
      'user': userName,
      'address': ip,
      'mac-address': 'AA:BB:CC:DD:EE:FF',
      'uptime': '0s',
      'bytes-in': '0',
      'bytes-out': '0',
    });
    if (!(comment.startsWith('vc-') || comment.startsWith('up-'))) return;
    scripts.add({
      '.id': _newId(),
      'comment': 'mikhmon',
      'name': [
        clockDate,
        clockTime,
        userName,
        meta?.group(1) ?? '0',
        ip,
        'AA:BB:CC:DD:EE:FF',
        u['limit-uptime'] ?? '',
        profile['name']!,
        comment,
      ].join('-|-'),
    });
    u['comment'] = 'used-$comment';
  }
}

class _Conn {
  bool loggedIn = false;
  List<int>? challenge;
}
