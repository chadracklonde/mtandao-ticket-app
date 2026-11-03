import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'mikhmon_service.dart';

/// Seuil d'alerte « stock bas » : nombre de tickets neufs sous lequel un profil
/// est signalé. 0 : pas d'alerte.
class StockAlertStore {
  static const _key = 'stock_alert_threshold';
  static const defaultThreshold = 20;

  Future<int> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_key) ?? defaultThreshold;
    } catch (_) {
      return defaultThreshold;
    }
  }

  Future<void> save(int threshold) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, threshold);
  }
}

/// Profil dont le stock de tickets neufs est sous le seuil.
class LowStock {
  const LowStock(this.profile, this.left);
  final String profile;
  final int left;
}

/// Profils en vente (prix > 0) dont les tickets neufs sont sous [threshold].
List<LowStock> lowStock(List<HotspotProfile> profiles, List<VoucherBatch> batches, int threshold) {
  if (threshold <= 0) return const [];
  final left = <String, int>{};
  for (final b in batches) {
    left[b.profile] = (left[b.profile] ?? 0) + b.vouchers.length;
  }
  return [
    for (final p in profiles)
      if (p.price > 0 && (left[p.name] ?? 0) < threshold) LowStock(p.name, left[p.name] ?? 0)
  ];
}
