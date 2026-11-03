import 'package:flutter/material.dart';

import 'screens/sessions_screen.dart';

// Charte : voir docs/identite-visuelle.md
const _blueSignal = Color(0xFF0F5FD0);
const _ink = Color(0xFF0E2A47);

void main() {
  runApp(const MtandaoApp());
}

class MtandaoApp extends StatelessWidget {
  const MtandaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mtandao Ticket',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _blueSignal,
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: _ink,
          foregroundColor: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: _blueSignal,
      ),
      home: const SessionsScreen(),
    );
  }
}
