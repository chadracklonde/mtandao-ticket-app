import 'dart:math';

import '../models.dart';
import '../routeros/api_client.dart';
import '../util.dart';

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
    final words = [
      if (p.id.isEmpty) '/ip/hotspot/user/profile/add' else '/ip/hotspot/user/profile/set',
      if (p.id.isNotEmpty) '=.id=${p.id}',
      '=name=${p.name}',
      '=rate-limit=${p.rateLimit}',
      '=shared-users=${p.sharedUsers}',
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
      '=.proplist=.id,name,password,profile,comment,limit-uptime',
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
      '=.proplist=name',
    ]);
    final out = <Sale>[];
    for (final r in rows) {
      final s = Sale.tryParse(r['name'] ?? '');
      if (s != null) out.add(s);
    }
    out.sort((a, b) => b.time.compareTo(a.time));
    return out;
  }
}
