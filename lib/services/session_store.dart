import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// Enregistre les connexions : paramètres dans les préférences, mot de passe
/// du routeur dans le stockage sécurisé du système (Android Keystore, trousseau
/// macOS, Windows). Si ce stockage est indisponible (ordinateur sans trousseau,
/// application non signée…), le mot de passe est gardé dans les préférences de
/// l'application, faute de mieux.
class SessionStore {
  static const _key = 'sessions';
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<String> _readPassword(String id) async {
    try {
      final v = await _secure.read(key: 'pw_$id');
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('pw_$id') ?? '';
  }

  Future<void> _writePassword(String id, String password) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await _secure.write(key: 'pw_$id', value: password);
      await prefs.remove('pw_$id');
    } catch (_) {
      await prefs.setString('pw_$id', password);
    }
  }

  Future<void> _deletePassword(String id) async {
    try {
      await _secure.delete(key: 'pw_$id');
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pw_$id');
  }

  Future<List<Session>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final out = <Session>[];
    for (final j in list) {
      final pw = await _readPassword(j['id'] as String);
      out.add(Session.fromJson(j, password: pw));
    }
    return out;
  }

  Future<void> _persist(List<Session> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(sessions.map((s) => s.toJson()).toList()));
  }

  Future<void> save(Session s) async {
    final all = await load();
    final i = all.indexWhere((e) => e.id == s.id);
    if (i >= 0) {
      all[i] = s;
    } else {
      all.add(s);
    }
    await _writePassword(s.id, s.password);
    await _persist(all);
  }

  Future<void> delete(String id) async {
    final all = await load();
    all.removeWhere((e) => e.id == id);
    await _deletePassword(id);
    await _persist(all);
  }
}
