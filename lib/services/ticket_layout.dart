import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

enum TicketPaper { a4, roll58, roll80 }

/// Mise en page des tickets imprimés.
class TicketLayout {
  const TicketLayout({
    this.paper = TicketPaper.a4,
    this.columns = 3,
    this.showLogo = false,
    this.showQr = true,
    this.header = '',
    this.footer = '',
  });

  final TicketPaper paper;

  /// Colonnes sur une page A4 (2, 3 ou 4). Ignoré pour les rouleaux.
  final int columns;
  final bool showLogo;
  final bool showQr;

  /// Texte en tête du ticket. Vide : le nom du routeur.
  final String header;

  /// Texte en bas du ticket (ex. un numéro à appeler).
  final String footer;

  TicketLayout copyWith({
    TicketPaper? paper,
    int? columns,
    bool? showLogo,
    bool? showQr,
    String? header,
    String? footer,
  }) =>
      TicketLayout(
        paper: paper ?? this.paper,
        columns: columns ?? this.columns,
        showLogo: showLogo ?? this.showLogo,
        showQr: showQr ?? this.showQr,
        header: header ?? this.header,
        footer: footer ?? this.footer,
      );

  Map<String, dynamic> toJson() => {
        'paper': paper.name,
        'columns': columns,
        'showLogo': showLogo,
        'showQr': showQr,
        'header': header,
        'footer': footer,
      };

  factory TicketLayout.fromJson(Map<String, dynamic> j) {
    final cols = (j['columns'] as num?)?.toInt() ?? 3;
    return TicketLayout(
      paper: TicketPaper.values.firstWhere(
        (p) => p.name == j['paper'],
        orElse: () => TicketPaper.a4,
      ),
      columns: (cols >= 2 && cols <= 4) ? cols : 3,
      showLogo: j['showLogo'] as bool? ?? false,
      showQr: j['showQr'] as bool? ?? true,
      header: j['header'] as String? ?? '',
      footer: j['footer'] as String? ?? '',
    );
  }
}

/// Enregistre la mise en page choisie (commune à tous les routeurs).
class TicketLayoutStore {
  static const _key = 'ticket_layout';

  Future<TicketLayout> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const TicketLayout();
      return TicketLayout.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const TicketLayout();
    }
  }

  Future<void> save(TicketLayout layout) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(layout.toJson()));
  }
}

/// Logo de l'application, pour l'imprimer sur les tickets.
Future<Uint8List?> loadTicketLogo() async {
  try {
    final data = await rootBundle.load('assets/brand/logo.png');
    return data.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
