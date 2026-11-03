import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'models.dart';
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

/// Lit une durée RouterOS : `1w2d3h4m5s`, `90m`, `01:30:00` ou `1d02:00:00`.
Duration? parseRouterDuration(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final colon = RegExp(r'^(?:(\d+)d)?(\d+):(\d+):(\d+)$').firstMatch(t);
  if (colon != null) {
    return Duration(
      days: int.tryParse(colon.group(1) ?? '') ?? 0,
      hours: int.parse(colon.group(2)!),
      minutes: int.parse(colon.group(3)!),
      seconds: int.parse(colon.group(4)!),
    );
  }
  if (!RegExp(r'^([0-9]+[wdhms])+$').hasMatch(t)) return null;
  var total = Duration.zero;
  for (final m in RegExp(r'([0-9]+)([wdhms])').allMatches(t)) {
    final n = int.parse(m.group(1)!);
    switch (m.group(2)) {
      case 'w':
        total += Duration(days: 7 * n);
      case 'd':
        total += Duration(days: n);
      case 'h':
        total += Duration(hours: n);
      case 'm':
        total += Duration(minutes: n);
      default:
        total += Duration(seconds: n);
    }
  }
  return total;
}

/// Durée au format RouterOS : `1d2h30m`.
String toRouterDuration(Duration d) {
  var s = d.inSeconds;
  if (s <= 0) return '0s';
  final out = StringBuffer();
  for (final (unit, size) in [('d', 86400), ('h', 3600), ('m', 60), ('s', 1)]) {
    final n = s ~/ size;
    if (n > 0) out.write('$n$unit');
    s %= size;
  }
  return out.toString();
}

/// Durée lisible en français : `1 j 2 h`, `45 min`, `30 s`.
String formatDuration(Duration d) {
  if (d.inSeconds <= 0) return '0 s';
  final days = d.inDays;
  final hours = d.inHours % 24;
  final minutes = d.inMinutes % 60;
  if (days > 0) return hours > 0 ? '$days j $hours h' : '$days j';
  if (d.inHours > 0) return minutes > 0 ? '${d.inHours} h $minutes min' : '${d.inHours} h';
  if (d.inMinutes > 0) return '${d.inMinutes} min';
  return '${d.inSeconds} s';
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

/// Débit en bits par seconde : `850 kb/s`, `1.2 Mb/s`.
String formatRate(int bitsPerSecond) {
  if (bitsPerSecond >= 1000000) return '${(bitsPerSecond / 1000000).toStringAsFixed(1)} Mb/s';
  if (bitsPerSecond >= 1000) return '${(bitsPerSecond / 1000).toStringAsFixed(0)} kb/s';
  return '$bitsPerSecond b/s';
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
