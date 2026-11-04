import 'dart:convert';

import '../models.dart';
import '../routeros/api_client.dart';

/// Sauvegarde des profils au format JSON, pour les restaurer sur ce routeur ou
/// un autre.
String profilesToJson(List<HotspotProfile> profiles) {
  return const JsonEncoder.withIndent('  ').convert({
    'app': 'mtandao-ticket',
    'version': 1,
    'profiles': [
      for (final p in profiles)
        {
          'name': p.name,
          'rateLimit': p.rateLimit,
          'sharedUsers': p.sharedUsers,
          'price': p.price,
          'uptime': p.uptime,
          'dataLimit': p.dataLimit,
          'bindDevice': p.bindDevice,
        }
    ],
  });
}

/// Relit une sauvegarde de profils. Lève [RouterOsException] si le fichier n'en est pas une.
List<HotspotProfile> profilesFromJson(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    throw RouterOsException('Ce fichier n\'est pas une sauvegarde de profils.');
  }
  if (decoded is! Map || decoded['app'] != 'mtandao-ticket' || decoded['profiles'] is! List) {
    throw RouterOsException('Ce fichier n\'est pas une sauvegarde de profils Mtandao Ticket.');
  }
  final out = <HotspotProfile>[];
  for (final item in decoded['profiles'] as List) {
    if (item is! Map) continue;
    final name = (item['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) continue;
    out.add(HotspotProfile(
      name: name,
      rateLimit: (item['rateLimit'] as String?) ?? '',
      sharedUsers: (item['sharedUsers'] as num?)?.toInt() ?? 1,
      price: (item['price'] as num?)?.toInt() ?? 0,
      uptime: (item['uptime'] as String?) ?? '',
      dataLimit: (item['dataLimit'] as String?) ?? '',
      bindDevice: item['bindDevice'] == true,
    ));
  }
  return out;
}

/// Résultat d'une restauration de profils.
class RestoreResult {
  RestoreResult(this.created, this.updated, this.failed);
  final int created;
  final int updated;

  /// Profils refusés : nom -> raison.
  final Map<String, String> failed;
}
