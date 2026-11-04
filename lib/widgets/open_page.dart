import 'package:flutter/material.dart';

/// Ouvre un écran secondaire avec une barre de titre (sur ordinateur, dans la
/// zone de contenu à droite de la barre latérale).
Future<T?> openPage<T>(BuildContext context, String title, Widget body) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute(
      builder: (_) => Scaffold(appBar: AppBar(title: Text(title)), body: body),
    ),
  );
}
