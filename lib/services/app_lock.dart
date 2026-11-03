import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Verrouillage de l'application par un code (4 à 8 chiffres).
/// Le code n'est jamais enregistré : seulement son empreinte salée.
class AppLock {
  static const _hashKey = 'lock_hash';
  static const _saltKey = 'lock_salt';

  static bool validPin(String pin) => RegExp(r'^[0-9]{4,8}$').hasMatch(pin);

  static String _hash(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_hashKey) ?? '').isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    if (!validPin(pin)) throw ArgumentError('Le code doit avoir 4 à 8 chiffres.');
    final prefs = await SharedPreferences.getInstance();
    final rnd = Random.secure();
    final salt = base64Url.encode(List<int>.generate(12, (_) => rnd.nextInt(256)));
    await prefs.setString(_saltKey, salt);
    await prefs.setString(_hashKey, _hash(salt, pin));
  }

  Future<bool> verify(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(_saltKey) ?? '';
    final hash = prefs.getString(_hashKey) ?? '';
    if (hash.isEmpty) return true;
    return _hash(salt, pin) == hash;
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hashKey);
    await prefs.remove(_saltKey);
  }
}
