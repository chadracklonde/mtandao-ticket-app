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
