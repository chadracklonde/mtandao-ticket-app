import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'routeros/api_client.dart';

/// Message d'erreur lisible pour l'utilisateur.
String describeError(Object e) {
  if (e is RouterOsException) return e.message;
  if (e is TimeoutException) {
    return 'Délai dépassé : le routeur ne répond pas.';
  }
  if (e is HandshakeException || e is TlsException) {
    return 'Échec de la connexion sécurisée (SSL). Vérifiez le port 8729 et le certificat du service api-ssl.';
  }
  if (e is SocketException) {
    final detail = e.osError?.message ?? e.message;
    return 'Impossible de joindre le routeur ($detail). '
        'Connectez-vous au wifi du routeur, ou ouvrez Back to Home pour un accès à distance. '
        'Vérifiez aussi l\'adresse et le port.';
  }
  return e.toString();
}

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

String two(int n) => n.toString().padLeft(2, '0');

String formatDate(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year}';

String formatTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

String formatMoney(int value, String currency) {
  final s = value.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${value < 0 ? '-' : ''}$buf $currency';
}

/// Taille de données saisie par l'utilisateur : `500M`, `1G`, `1.5G`, `100k`.
final RegExp dataPattern = RegExp(r'^[0-9]+(\.[0-9]+)?[kKmMgG]$');

/// Convertit `500M` / `1G` en octets (base 1024, comme RouterOS). Null si invalide.
int? parseDataSize(String text) {
  final t = text.trim();
  if (!dataPattern.hasMatch(t)) return null;
  final n = double.parse(t.substring(0, t.length - 1));
  final unit = t[t.length - 1].toLowerCase();
  final mult = unit == 'g' ? 1073741824 : (unit == 'm' ? 1048576 : 1024);
  final bytes = (n * mult).round();
  return bytes > 0 ? bytes : null;
}

/// Libellé lisible d'une limite de données : `500 Mo`, `1 Go`, `1.5 Go`.
String dataLimitLabel(int bytes) {
  String fmt(double v, String u) =>
      '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} $u';
  if (bytes >= 1073741824) return fmt(bytes / 1073741824, 'Go');
  if (bytes >= 1048576) return fmt(bytes / 1048576, 'Mo');
  if (bytes >= 1024) return fmt(bytes / 1024, 'Ko');
  return '$bytes o';
}

String formatBytes(int bytes) {
  const units = ['o', 'Ko', 'Mo', 'Go', 'To'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
}

const List<String> monthNames = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];
