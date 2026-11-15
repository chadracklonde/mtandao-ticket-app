import '../routeros/api_client.dart';
import 'mikhmon_service.dart';
import 'speed.dart';

typedef TicketRouterRun = Future<List<Map<String, String>>> Function(List<String> words);

/// Une seule file par ticket, avec toutes ses adresses comme cibles.
/// Le scheduler fonctionne sur le routeur, même lorsque l'application est fermée.
class TicketBandwidth {
  TicketBandwidth(MikhmonService service) : _run = service.client.run;
  TicketBandwidth.withRunner(this._run);
  final TicketRouterRun _run;
  static const prefix = 'mkm-ticket:';
  static const schedulerName = 'mkm-ticket-sync';
  static const schedulerComment = 'mkm-ticket-sync-v1';
  static const rates = ['256k', '512k', '1M', '2M'];

  static String marker(String id) {
    if (!RegExp(r'^\*[0-9a-fA-F]+$').hasMatch(id)) {
      throw RouterOsException('Identifiant de ticket invalide.');
    }
    return '$prefix$id';
  }

  Future<List<Map<String, String>>> _queues(String id) => _run([
        '/queue/simple/print', '?comment=${marker(id)}',
        '=.proplist=.id,name,max-limit,disabled',
      ]);

  Future<String?> read(String id) async {
    final rows = await _queues(id);
    if (rows.isEmpty) return null;
    return rows.first['max-limit'];
  }

  Future<void> save(String id, String rate) async {
    marker(id);
    if (!rates.contains(rate)) throw RouterOsException('Choisissez 256k, 512k, 1M ou 2M.');
    final users = await _run(['/ip/hotspot/user/print', '?.id=$id', '=.proplist=.id']);
    if (users.isEmpty) throw RouterOsException('Ce ticket n’existe plus sur le routeur.');
    final fasttrack = await _run([
      '/ip/firewall/filter/print', '?action=fasttrack-connection', '=.proplist=disabled',
    ]);
    if (fasttrack.any((r) => r['disabled'] != 'true' && r['disabled'] != 'yes')) {
      throw RouterOsException('FastTrack est actif : faites exclure le trafic hotspot de FastTrack avant d’utiliser cette limitation. Le pare-feu n’a pas été modifié.');
    }
    await _ensureScheduler();
    final rows = await _queues(id);
    final common = await _run([
      '/queue/simple/print', '?name=${MikhmonService.sharedQueueName}', '=.proplist=.id',
    ]);
    await _run([
      rows.isEmpty ? '/queue/simple/add' : '/queue/simple/set',
      if (rows.isNotEmpty) '=.id=${rows.first['.id']}',
      if (rows.isEmpty) '=name=mkm-ticket-${id.substring(1)}',
      '=comment=${marker(id)}',
      '=max-limit=${normalizeRate(rate)}',
      '=parent=${common.isEmpty ? 'none' : MikhmonService.sharedQueueName}',
      '=queue=default-small/default-small',
      if (rows.isEmpty) '=target=127.0.0.1/32',
      if (rows.isEmpty) '=disabled=yes',
    ]);
  }

  Future<void> remove(String id) async {
    for (final q in await _queues(id)) {
      await _run(['/queue/simple/remove', '=.id=${q['.id']}']);
    }
  }

  Future<void> _ensureScheduler() async {
    final rows = await _run([
      '/system/scheduler/print', '?name=$schedulerName', '=.proplist=.id,comment',
    ]);
    if (rows.any((r) => r['comment'] != schedulerComment)) {
      throw RouterOsException('Le nom mkm-ticket-sync est déjà utilisé par une autre tâche.');
    }
    await _run([
      rows.isEmpty ? '/system/scheduler/add' : '/system/scheduler/set',
      if (rows.isNotEmpty) '=.id=${rows.first['.id']}',
      '=name=$schedulerName', '=comment=$schedulerComment',
      '=interval=2s', '=start-time=00:00:00', '=disabled=no',
      '=policy=read,write,test', '=on-event=$syncScript',
    ]);
  }

  /// Ne contient ni code utilisateur interpolé, ni commande modifiant les profils.
  /// Les files orphelines sont retirées ; une file sans session est désactivée.
  static const syncScript = r'''
:local parent "none";
:if ([:len [/queue simple find where name="mkm-total"]] > 0) do={ :set parent "mkm-total"; };
:foreach q in=[/queue simple find where comment~"^mkm-ticket:"] do={
  :local uid [:pick [/queue simple get $q comment] 11 255];
  :local username "";
  :do { :set username [/ip hotspot user get $uid name]; } on-error={ :set username ""; };
  :if ([:len $username] = 0) do={
    /queue simple remove $q;
  } else={
    :local targets [:toarray ""];
    :foreach a in=[/ip hotspot active find where user=$username] do={
      :local ip [/ip hotspot active get $a address];
      :if ([:len $ip] > 0) do={ :set targets ($targets,($ip . "/32")); };
    };
    :if ([:len $targets] = 0) do={
      /queue simple set $q disabled=yes;
    } else={
      :if ([:tostr [/queue simple get $q target]] != [:tostr $targets]) do={
        /queue simple set $q target=$targets;
      };
      :if ([/queue simple get $q parent] != $parent) do={ /queue simple set $q parent=$parent; };
      :local first [:pick [/queue simple find where parent=$parent] 0];
      :if (([:len $first] > 0) && ($first != $q)) do={ /queue simple move $q destination=$first; };
      /queue simple set $q disabled=no;
    };
  };
};
''';
}
