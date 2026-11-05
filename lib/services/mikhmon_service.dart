import 'dart:math';

import '../models.dart';
import '../routeros/api_client.dart';
import '../util.dart';
import 'hotspot_setup.dart';
import 'profile_backup.dart';
import 'speed.dart';

enum CodeCharset { digits, lower, mixed }

/// Paramètres de génération d'un lot de tickets.
class GenerateRequest {
  const GenerateRequest({
    required this.profile,
    required this.count,
    this.prefix = '',
    this.length = 6,
    this.separate = false,
    this.charset = CodeCharset.digits,
    this.timeLimit,
    this.dataLimit,
  });

  final HotspotProfile profile;
  final int count;
  final String prefix;
  final int length;

  /// Vrai : identifiant et mot de passe différents. Faux : un seul code.
  final bool separate;
  final CodeCharset charset;

  /// Limite de temps des tickets (ex. `1h`, `1d`), qui démarre à la première
  /// connexion. Null : celle du profil. Vide : illimitée.
  final String? timeLimit;

  /// Limite de données par ticket (ex. `500M`, `1G`), envoyées + reçues.
  /// Null : celle du profil. Vide : illimitée.
  final String? dataLimit;

  String get effectiveDataLimit => (dataLimit ?? profile.dataLimit).trim();

  int? get dataLimitBytes => parseDataSize(effectiveDataLimit);

  String get effectiveTimeLimit => (timeLimit ?? profile.uptime).trim().toLowerCase();
}

/// La génération s'est arrêtée en cours de route (réseau coupé, routeur
/// éteint…). Les tickets déjà créés existent sur le routeur.
class GenerationInterrupted extends RouterOsException {
  GenerationInterrupted(this.created, this.requested, String cause)
      : super('${created.length} ticket(s) sur $requested créés avant l\'arrêt : '
            'retrouvez-les dans l\'onglet Lots. $cause');

  final List<Voucher> created;
  final int requested;
}

/// Lot de tickets non utilisés (même date de génération et même profil).
class VoucherBatch {
  VoucherBatch({required this.comment, required this.profile, required this.vouchers});
  final String comment;
  final String profile;
  final List<Voucher> vouchers;

  /// Libellé lisible : `vc-021126-1432` → `02/11/26 14:32`.
  String get label {
    final m = RegExp(r'^(?:vc|up)-(\d{2})(\d{2})(\d{2})-(\d{2})(\d{2})').firstMatch(comment);
    if (m == null) return comment;
    return '${m.group(1)}/${m.group(2)}/${m.group(3)} ${m.group(4)}:${m.group(5)}';
  }
}

/// Opérations de haut niveau sur le hotspot (équivalent des écrans de Mikhmon).
class MikhmonService {
  MikhmonService(this.client, this.session, {Random? random})
      : _random = random ?? Random.secure();

  final RouterOsClient client;
  final Session session;

  final Random _random;

  // ---- Profils -----------------------------------------------------------

  Future<List<HotspotProfile>> profiles() async {
    final rows = await client.run(['/ip/hotspot/user/profile/print']);
    return rows.map(HotspotProfile.fromRow).toList();
  }

  Future<void> saveProfile(HotspotProfile p) async {
    if (!safeNamePattern.hasMatch(p.name)) {
      throw RouterOsException(
          'Nom de profil invalide : utilisez lettres, chiffres, espace, point, tiret ou _.');
    }
    if (p.uptime.isNotEmpty && !uptimePattern.hasMatch(p.uptime)) {
      throw RouterOsException('Durée invalide. Exemples : 30m, 1h, 24h, 7d.');
    }
    if (p.dataLimit.isNotEmpty && parseDataSize(p.dataLimit) == null) {
      throw RouterOsException('Limite de données invalide. Exemples : 500M, 1G, 2G.');
    }
    // Un nouveau profil rejoint l'enveloppe commune de bande passante, si elle existe.
    var parent = p.parentQueue;
    if (p.id.isEmpty && parent.isEmpty && await sharedBandwidth() != null) {
      parent = sharedQueueName;
    }
    final words = [
      if (p.id.isEmpty) '/ip/hotspot/user/profile/add' else '/ip/hotspot/user/profile/set',
      if (p.id.isNotEmpty) '=.id=${p.id}',
      '=name=${p.name}',
      '=rate-limit=${p.rateLimit}',
      '=shared-users=${p.sharedUsers}',
      '=parent-queue=${parent.isEmpty ? 'none' : parent}',
      '=on-login=${p.buildOnLogin()}',
    ];
    await client.run(words);
  }

  Future<void> removeProfile(String id) =>
      client.run(['/ip/hotspot/user/profile/remove', '=.id=$id']);

  // ---- Tickets -----------------------------------------------------------

  static String _alphabet(CodeCharset c) {
    switch (c) {
      case CodeCharset.digits:
        return '0123456789';
      case CodeCharset.lower:
        return 'abcdefghjkmnpqrstuvwxyz';
      case CodeCharset.mixed:
        return '23456789abcdefghjkmnpqrstuvwxyz';
    }
  }

  static String _dataLabel(String? bytes) {
    final n = int.tryParse(bytes ?? '');
    return (n == null || n <= 0) ? '' : dataLimitLabel(n);
  }

  String _randomCode(String alphabet, int length) {
    final b = StringBuffer();
    for (var i = 0; i < length; i++) {
      b.write(alphabet[_random.nextInt(alphabet.length)]);
    }
    return b.toString();
  }

  Future<List<Voucher>> generate(
    GenerateRequest r, {
    void Function(int done, int total)? onProgress,
    int maxAttempts = 20,
  }) async {
    if (r.effectiveDataLimit.isNotEmpty && r.dataLimitBytes == null) {
      throw RouterOsException('Limite de données invalide. Exemples : 500M, 1G, 2G.');
    }
    final now = DateTime.now();
    final batch =
        '${two(now.day)}${two(now.month)}${two(now.year % 100)}-${two(now.hour)}${two(now.minute)}';
    final comment = '${r.separate ? 'up' : 'vc'}-$batch';
    final alphabet = _alphabet(r.charset);
    final used = <String>{};
    final out = <Voucher>[];

    try {
      await _generateInto(r, out, used, alphabet, comment, onProgress, maxAttempts);
    } catch (e) {
      if (out.isEmpty) rethrow;
      throw GenerationInterrupted(out, r.count, describeError(e));
    }
    return out;
  }

  Future<void> _generateInto(
    GenerateRequest r,
    List<Voucher> out,
    Set<String> used,
    String alphabet,
    String comment,
    void Function(int done, int total)? onProgress,
    int maxAttempts,
  ) async {
    for (var i = 0; i < r.count; i++) {
      var created = false;
      for (var attempt = 0; attempt < maxAttempts && !created; attempt++) {
        final name = r.prefix + _randomCode(alphabet, r.length);
        if (used.contains(name)) continue;
        final password = r.separate ? _randomCode(alphabet, r.length) : name;
        try {
          final reply = await client.exec([
            '/ip/hotspot/user/add',
            '=name=$name',
            '=password=$password',
            '=profile=${r.profile.name}',
            '=comment=$comment',
            if (r.effectiveTimeLimit.isNotEmpty) '=limit-uptime=${r.effectiveTimeLimit}',
            if (r.dataLimitBytes != null) '=limit-bytes-total=${r.dataLimitBytes}',
          ]);
          used.add(name);
          out.add(Voucher(
            id: reply.done['ret'] ?? '',
            name: name,
            password: password,
            profile: r.profile.name,
            comment: comment,
            price: r.profile.price,
            uptime: r.effectiveTimeLimit,
            dataLimit: r.dataLimitBytes == null ? '' : dataLimitLabel(r.dataLimitBytes!),
          ));
          created = true;
        } on RouterOsException catch (e) {
          // Code déjà pris sur le routeur : on retente avec un autre code.
          if (!e.message.toLowerCase().contains('already have')) rethrow;
        }
      }
      if (!created) {
        throw RouterOsException(
            'Impossible de trouver un code libre. Augmentez la longueur du code.');
      }
      onProgress?.call(i + 1, r.count);
    }
  }

  /// Tickets jamais utilisés, regroupés par lot.
  Future<List<VoucherBatch>> unusedBatches() async {
    final profileList = await profiles();
    final byName = {for (final p in profileList) p.name: p};
    final rows = await client.run([
      '/ip/hotspot/user/print',
      '=.proplist=.id,name,password,profile,comment,limit-uptime,limit-bytes-total',
    ]);
    final groups = <String, List<Voucher>>{};
    for (final r in rows) {
      final comment = r['comment'] ?? '';
      if (!(comment.startsWith('vc-') || comment.startsWith('up-'))) continue;
      final profileName = r['profile'] ?? 'default';
      final p = byName[profileName];
      final v = Voucher(
        id: r['.id'] ?? '',
        name: r['name'] ?? '',
        password: r['password'] ?? r['name'] ?? '',
        profile: profileName,
        comment: comment,
        price: p?.price ?? 0,
        uptime: r['limit-uptime'] ?? p?.uptime ?? '',
        dataLimit: _dataLabel(r['limit-bytes-total']),
      );
      groups.putIfAbsent('$comment|$profileName', () => []).add(v);
    }
    final batches = groups.entries.map((e) {
      final first = e.value.first;
      return VoucherBatch(comment: first.comment, profile: first.profile, vouchers: e.value);
    }).toList();
    batches.sort((a, b) => b.comment.compareTo(a.comment));
    return batches;
  }

  Future<void> removeVouchers(List<Voucher> vouchers) async {
    for (final v in vouchers) {
      if (v.id.isEmpty) continue;
      await client.run(['/ip/hotspot/user/remove', '=.id=${v.id}']);
    }
  }

  /// Efface des ventes du journal du routeur (rapport corrigé ou remis à zéro).
  /// Les tickets eux-mêmes ne sont pas touchés. Renvoie le nombre de ventes effacées.
  Future<int> deleteSales(List<Sale> sales) async {
    var n = 0;
    for (final s in sales) {
      if (s.id.isEmpty) continue;
      await client.run(['/system/script/remove', '=.id=${s.id}']);
      n++;
    }
    return n;
  }

  // ---- Sauvegarde ------------------------------------------------------------

  Future<String> exportProfiles() async => profilesToJson(await profiles());

  /// Recrée les profils d'une sauvegarde ; ceux qui existent déjà (même nom) sont mis à jour.
  Future<RestoreResult> restoreProfiles(List<HotspotProfile> wanted) async {
    final existing = {for (final p in await profiles()) p.name: p};
    var created = 0;
    var updated = 0;
    final failed = <String, String>{};
    for (final p in wanted) {
      final old = existing[p.name];
      try {
        await saveProfile(HotspotProfile(
          id: old?.id ?? '',
          name: p.name,
          rateLimit: p.rateLimit,
          sharedUsers: p.sharedUsers,
          price: p.price,
          uptime: p.uptime,
          dataLimit: p.dataLimit,
        ));
        old == null ? created++ : updated++;
      } catch (e) {
        failed[p.name] = describeError(e);
      }
    }
    return RestoreResult(created, updated, failed);
  }

  /// Crée sur le routeur une sauvegarde complète (.backup) et un export lisible (.rsc).
  /// Les fichiers restent sur le routeur (Winbox > Files). Renvoie le nom commun.
  Future<String> createRouterBackup() async {
    final now = DateTime.now();
    final name = 'mtandao-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}';
    await client.run(['/system/backup/save', '=name=$name']);
    await client.run(['/export', '=file=$name']);
    return name;
  }

  // ---- Surveillance du routeur ---------------------------------------------

  Future<RouterResource> resource() async {
    final rows = await client.run(['/system/resource/print']);
    if (rows.isEmpty) throw RouterOsException('Le routeur n\'a pas renvoyé son état.');
    return RouterResource.fromRow(rows.first);
  }

  /// Interfaces actives (câble, wifi, pont…), pour le trafic en direct.
  Future<List<String>> interfaces() async {
    final rows = await client.run(['/interface/print', '=.proplist=name,running,disabled']);
    return [
      for (final r in rows)
        if ((r['disabled'] ?? 'false') != 'true' && (r['running'] ?? 'true') != 'false' && r['name'] != null)
          r['name']!
    ];
  }

  Future<TrafficSample> traffic(String interfaceName) async {
    final rows = await client.run(['/interface/monitor-traffic', '=interface=$interfaceName', '=once=']);
    final r = rows.isEmpty ? const <String, String>{} : rows.first;
    return TrafficSample(
      int.tryParse(r['rx-bits-per-second'] ?? '') ?? 0,
      int.tryParse(r['tx-bits-per-second'] ?? '') ?? 0,
    );
  }

  /// Dernières lignes du journal (les plus récentes d'abord).
  Future<List<LogEntry>> logs({int limit = 200}) async {
    final rows = await client.run(['/log/print', '=.proplist=time,topics,message']);
    final all = rows.map(LogEntry.fromRow).toList();
    final tail = all.length > limit ? all.sublist(all.length - limit) : all;
    return tail.reversed.toList();
  }

  Future<List<DhcpLease>> dhcpLeases() async {
    final rows = await client.run(['/ip/dhcp-server/lease/print']);
    return rows.map(DhcpLease.fromRow).where((l) => l.address.isNotEmpty).toList();
  }

  // ---- Tous les utilisateurs du hotspot ------------------------------------

  Future<List<HotspotUser>> hotspotUsers() async {
    final rows = await client.run([
      '/ip/hotspot/user/print',
      '=.proplist=.id,name,password,profile,comment,disabled,uptime,limit-uptime,'
          'bytes-in,bytes-out,limit-bytes-total,mac-address',
    ]);
    final list = rows.map(HotspotUser.fromRow).where((u) => u.name.isNotEmpty).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<void> setUserDisabled(String id, bool disabled) async {
    await client.run(['/ip/hotspot/user/set', '=.id=$id', '=disabled=${disabled ? 'yes' : 'no'}']);
  }

  Future<void> resetUserCounters(String id) async {
    await client.run(['/ip/hotspot/user/reset-counters', '=.id=$id']);
  }

  Future<void> removeUser(String id) async {
    await client.run(['/ip/hotspot/user/remove', '=.id=$id']);
  }

  /// Prolonge un ticket : ajoute du temps et/ou des données à ses limites.
  /// Un ticket illimité sur un critère n'est pas modifié sur ce critère.
  Future<void> extendUser(HotspotUser u, {Duration? addTime, int? addBytes}) async {
    final words = <String>['/ip/hotspot/user/set', '=.id=${u.id}'];
    if (addTime != null && addTime > Duration.zero && u.limitUptime != null) {
      words.add('=limit-uptime=${toRouterDuration(u.limitUptime! + addTime)}');
    }
    if (addBytes != null && addBytes > 0 && u.limitBytes > 0) {
      words.add('=limit-bytes-total=${u.limitBytes + addBytes}');
    }
    if (words.length == 2) {
      throw RouterOsException(
          'Ce ticket n\'a pas de limite à prolonger (temps ou données illimités).');
    }
    await client.run(words);
  }

  // ---- Utilisateurs actifs -------------------------------------------------

  Future<List<ActiveUser>> activeUsers() async {
    final rows = await client.run(['/ip/hotspot/active/print']);
    return rows.map(ActiveUser.fromRow).toList();
  }

  Future<void> disconnect(String id) =>
      client.run(['/ip/hotspot/active/remove', '=.id=$id']);

  // ---- Ventes ----------------------------------------------------------------

  Future<List<Sale>> sales() async {
    final rows = await client.run([
      '/system/script/print',
      '?comment=mikhmon',
      '=.proplist=.id,name',
    ]);
    final out = <Sale>[];
    for (final r in rows) {
      final s = Sale.tryParse(r['name'] ?? '', id: r['.id'] ?? '');
      if (s != null) out.add(s);
    }
    out.sort((a, b) => b.time.compareTo(a.time));
    return out;
  }

  // ---- Appareils bloqués (liste noire) ------------------------------------

  /// Appareils bloqués du hotspot (liaisons IP de type « blocked »).
  Future<List<BlockedDevice>> blockedDevices() async {
    final rows = await client.run([
      '/ip/hotspot/ip-binding/print',
      '?type=blocked',
      '=.proplist=.id,mac-address,comment',
    ]);
    return rows.map(BlockedDevice.fromRow).where((d) => d.mac.isNotEmpty).toList();
  }

  /// Bloque un appareil par son adresse MAC et coupe ses sessions en cours.
  Future<void> blockDevice(String mac, {String note = ''}) async {
    final clean = mac.trim().toUpperCase();
    if (!macPattern.hasMatch(clean)) {
      throw RouterOsException('Adresse MAC invalide. Exemple : AA:BB:CC:11:22:33');
    }
    await client.run([
      '/ip/hotspot/ip-binding/add',
      '=mac-address=$clean',
      '=type=blocked',
      '=comment=mkm-bloque${note.isEmpty ? '' : ' $note'}',
    ]);
    for (final a in await activeUsers()) {
      if (a.mac.toUpperCase() == clean) await disconnect(a.id);
    }
  }

  Future<void> unblockDevice(String id) =>
      client.run(['/ip/hotspot/ip-binding/remove', '=.id=$id']);

  // ---- Vitesse et équité entre les clients ---------------------------------

  /// Nom de la file qui regroupe tous les clients (enveloppe commune).
  static const sharedQueueName = 'mkm-total';

  /// Enveloppe de bande passante commune, ou null si elle n'est pas activée.
  Future<SharedBandwidth?> sharedBandwidth() async {
    final rows = await client.run([
      '/queue/simple/print',
      '?name=$sharedQueueName',
      '=.proplist=.id,name,target,max-limit',
    ]);
    if (rows.isEmpty) return null;
    return SharedBandwidth.fromRow(rows.first);
  }

  /// Réseau des clients du hotspot (ex. `10.5.50.0/24`), si on peut le deviner.
  Future<String?> detectHotspotNetwork() async {
    final servers = await client.run(['/ip/hotspot/print', '=.proplist=interface']);
    if (servers.isEmpty) return null;
    final iface = servers.first['interface'] ?? '';
    if (iface.isEmpty) return null;
    final addrs = await client.run(['/ip/address/print', '?interface=$iface', '=.proplist=address']);
    if (addrs.isEmpty) return null;
    return networkOf(addrs.first['address'] ?? '');
  }

  /// Active (ou met à jour) l'enveloppe commune et y rattache tous les profils.
  Future<void> enableSharedBandwidth({
    required int downMbps,
    required int upMbps,
    required String target,
  }) async {
    if (downMbps < 1 || upMbps < 1) {
      throw RouterOsException('Indiquez la vitesse totale de la connexion (au moins 1 Mb/s).');
    }
    if (target.trim().isEmpty) {
      throw RouterOsException('Indiquez le réseau des clients (ex. 10.5.50.0/24).');
    }
    final limit = '${upMbps}M/${downMbps}M';
    final existing = await sharedBandwidth();
    if (existing == null) {
      await client.run([
        '/queue/simple/add',
        '=name=$sharedQueueName',
        '=target=${target.trim()}',
        '=max-limit=$limit',
        '=comment=mkm',
      ]);
    } else {
      await client.run([
        '/queue/simple/set',
        '=.id=${existing.id}',
        '=target=${target.trim()}',
        '=max-limit=$limit',
      ]);
    }
    for (final p in await profiles()) {
      if (p.parentQueue != sharedQueueName) {
        await client.run(['/ip/hotspot/user/profile/set', '=.id=${p.id}', '=parent-queue=$sharedQueueName']);
      }
    }
  }

  /// Retire l'enveloppe commune (les profils redeviennent indépendants).
  Future<void> disableSharedBandwidth() async {
    for (final p in await profiles()) {
      if (p.parentQueue == sharedQueueName) {
        await client.run(['/ip/hotspot/user/profile/set', '=.id=${p.id}', '=parent-queue=none']);
      }
    }
    final existing = await sharedBandwidth();
    if (existing != null) await client.run(['/queue/simple/remove', '=.id=${existing.id}']);
  }

  /// Nombre maximal de connexions simultanées par appareil, ou null si aucune limite.
  Future<int?> connectionLimit() async {
    final rows = await client.run([
      '/ip/firewall/filter/print',
      '?comment=mkm-connlimit',
      '=.proplist=.id,connection-limit',
    ]);
    if (rows.isEmpty) return null;
    return int.tryParse((rows.first['connection-limit'] ?? '').split(',').first);
  }

  /// Fixe (ou retire, avec null) la limite de connexions par appareil.
  /// La règle est placée avant toutes les autres pour être appliquée.
  Future<void> setConnectionLimit(int? limit) async {
    final rows = await client.run([
      '/ip/firewall/filter/print',
      '?comment=mkm-connlimit',
      '=.proplist=.id',
    ]);
    if (limit == null) {
      for (final r in rows) {
        await client.run(['/ip/firewall/filter/remove', '=.id=${r['.id']}']);
      }
      return;
    }
    if (limit < 20 || limit > 5000) {
      throw RouterOsException('Choisissez une limite entre 20 et 5000 connexions.');
    }
    if (rows.isNotEmpty) {
      await client.run([
        '/ip/firewall/filter/set',
        '=.id=${rows.first['.id']}',
        '=connection-limit=$limit,32',
      ]);
      return;
    }
    final first = await client.run(['/ip/firewall/filter/print', '=.proplist=.id']);
    await client.run([
      '/ip/firewall/filter/add',
      '=chain=forward',
      '=protocol=tcp',
      '=connection-limit=$limit,32',
      '=action=drop',
      '=comment=mkm-connlimit',
      if (first.isNotEmpty) '=place-before=${first.first['.id']}',
    ]);
  }

  /// Libère un ticket lié à un appareil (il pourra se lier à un autre).
  Future<void> unbindUser(String id) async {
    await client.run(['/ip/hotspot/user/set', '=.id=$id', '=mac-address=00:00:00:00:00:00']);
  }

  // ---- Installation d'un nouveau hotspot ----------------------------------------

  static const _installLog = 'mkm-install';

  /// Nom, version et interfaces du routeur, pour préparer l'installation.
  Future<RouterFacts> routerFacts() async {
    Future<List<Map<String, String>>> q(List<String> w) async {
      try {
        return await client.run(w);
      } on RouterOsException {
        return const [];
      }
    }

    final ifaces = await client.run(['/interface/print', '=.proplist=name']);
    final nat = await q(['/ip/firewall/nat/print', '?action=masquerade', '=.proplist=.id']);
    final log = await q(['/system/script/print', '?name=$_installLog', '=.proplist=.id']);
    return RouterFacts(
      interfaces: [for (final r in ifaces) if ((r['name'] ?? '').isNotEmpty) r['name']!],
      hotspots: await q(['/ip/hotspot/print', '=.proplist=name,interface']),
      addresses: await q(['/ip/address/print', '=.proplist=address,interface']),
      dhcpServers: await q(['/ip/dhcp-server/print', '=.proplist=name,interface,address-pool']),
      hasMasquerade: nat.isNotEmpty,
      services: await q(['/ip/service/print', '=.proplist=.id,name,disabled']),
      users: await q(['/user/print', '=.proplist=name']),
      hasInstallLog: log.isNotEmpty,
    );
  }

  /// Applique les étapes. En cas de refus du routeur, retire ce qui vient
  /// d'être créé et relance l'erreur. Les éléments créés sont notés dans un
  /// script du routeur pour pouvoir annuler l'installation plus tard.
  Future<void> runSetup(List<SetupStep> steps, {void Function(int done, int total)? onProgress}) async {
    final created = <String>[];
    var done = 0;
    try {
      for (final step in steps) {
        String? id;
        if (step.profile != null) {
          final before = (await profiles()).map((p) => p.name).toSet();
          await saveProfile(step.profile!);
          final p = (await profiles()).where((x) => x.name == step.profile!.name && !before.contains(x.name));
          id = p.isEmpty ? null : p.first.id;
        } else {
          final reply = await client.exec(step.words);
          id = reply.done['ret'];
        }
        if (step.undoPath != null && id != null && id.isNotEmpty) created.add('${step.undoPath}|$id');
        done++;
        onProgress?.call(done, steps.length);
      }
    } catch (e) {
      await _undo(created);
      throw RouterOsException(
          'L\'installation s\'est arrêtée à l\'étape ${done + 1} sur ${steps.length} : '
          '${describeError(e)} Ce qui avait été créé a été retiré.');
    }
    if (created.isNotEmpty) {
      await client.run([
        '/system/script/add',
        '=name=$_installLog',
        '=source=${created.join('\n')}',
        '=comment=mkm',
      ]);
    }
  }

  Future<void> _undo(List<String> created) async {
    for (final line in created.reversed) {
      final i = line.indexOf('|');
      if (i < 0) continue;
      try {
        await client.run([line.substring(0, i), '=.id=${line.substring(i + 1)}']);
      } on RouterOsException {
        // Déjà supprimé : on continue.
      }
    }
  }

  /// Annule la dernière installation faite par l'application.
  Future<void> undoInstall() async {
    final rows = await client.run(['/system/script/print', '?name=$_installLog', '=.proplist=.id,source']);
    if (rows.isEmpty) throw RouterOsException('Aucune installation à annuler sur ce routeur.');
    final lines = (rows.first['source'] ?? '').split('\n').where((l) => l.contains('|')).toList();
    await _undo(lines);
    await client.run(['/system/script/remove', '=.id=${rows.first['.id']}']);
  }

  // ---- Ralentir un appareil ---------------------------------------------------

  static const slowComment = 'mkm-ralenti';

  /// Adresses IP actuellement ralenties par l'application.
  Future<Set<String>> slowedAddresses() async {
    final rows = await client.run(['/queue/simple/print', '?comment=$slowComment', '=.proplist=.id,target']);
    return {for (final r in rows) (r['target'] ?? '').split('/').first};
  }

  /// Limite le débit d'un appareil (ex. `256k`). La règle est placée en tête pour
  /// passer avant les files dynamiques du hotspot.
  Future<void> slowDevice(String address, {String rate = '256k'}) async {
    if (!RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(address)) {
      throw RouterOsException('Adresse invalide : $address');
    }
    if (!isValidRate(rate)) throw RouterOsException('Débit invalide. Exemples : 256k, 512k, 1M.');
    if ((await slowedAddresses()).contains(address)) return;
    final first = await client.run(['/queue/simple/print', '=.proplist=.id']);
    await client.run([
      '/queue/simple/add',
      '=name=$slowComment-$address',
      '=target=$address/32',
      '=max-limit=${normalizeRate(rate)}',
      '=comment=$slowComment',
      if (first.isNotEmpty) '=place-before=${first.first['.id']}',
    ]);
  }

  Future<void> unslowDevice(String address) async {
    final rows = await client.run(['/queue/simple/print', '?comment=$slowComment', '=.proplist=.id,target']);
    for (final r in rows) {
      if ((r['target'] ?? '').split('/').first == address) {
        await client.run(['/queue/simple/remove', '=.id=${r['.id']}']);
      }
    }
  }

  // ---- Sauvegarde automatique (faite par le routeur lui-même) --------------

  static const autoBackupName = 'mkm-backup';
  static const autoBackupFile = 'mtandao-auto';

  /// Sauvegarde automatique du routeur : intervalle et date du dernier fichier.
  Future<AutoBackup> autoBackup() async {
    final sched = await client.run([
      '/system/scheduler/print',
      '?name=$autoBackupName',
      '=.proplist=.id,interval,disabled',
    ]);
    DateTime? last;
    try {
      final files = await client.run(['/file/print', '?name=$autoBackupFile.backup', '=.proplist=name,creation-time']);
      if (files.isNotEmpty) {
        final ct = (files.first['creation-time'] ?? '').trim().split(RegExp(r'\s+'));
        if (ct.length == 2) last = parseRouterDateTime(ct[0], ct[1]);
      }
    } on RouterOsException {
      // Liste des fichiers inaccessible : on ignore.
    }
    if (sched.isEmpty) return AutoBackup(enabled: false, interval: null, last: last);
    final disabled = sched.first['disabled'] == 'true' || sched.first['disabled'] == 'yes';
    return AutoBackup(
      enabled: !disabled,
      interval: parseRouterDuration(sched.first['interval'] ?? ''),
      last: last,
    );
  }

  /// Programme (ou reprogramme) la sauvegarde automatique toutes les [every].
  Future<void> enableAutoBackup(Duration every) async {
    if (every < const Duration(hours: 12)) throw RouterOsException('Intervalle trop court.');
    await disableAutoBackup();
    await client.run([
      '/system/scheduler/add',
      '=name=$autoBackupName',
      '=interval=${toRouterDuration(every)}',
      '=start-time=03:00:00',
      '=on-event=/system backup save name=$autoBackupFile; /export file=$autoBackupFile',
      '=comment=mkm',
    ]);
  }

  Future<void> disableAutoBackup() async {
    final rows = await client.run(['/system/scheduler/print', '?name=$autoBackupName', '=.proplist=.id']);
    for (final r in rows) {
      await client.run(['/system/scheduler/remove', '=.id=${r['.id']}']);
    }
  }
}

class AutoBackup {
  const AutoBackup({required this.enabled, required this.interval, required this.last});
  final bool enabled;
  final Duration? interval;
  final DateTime? last;

  /// Vrai si la sauvegarde est programmée mais ne s'est pas faite à temps.
  bool lateAt(DateTime now) {
    if (!enabled || interval == null) return false;
    final l = last;
    if (l == null) return false;
    return now.difference(l) > interval! * 2;
  }
}
