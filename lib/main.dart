import 'package:flutter/material.dart';

import 'screens/sessions_screen.dart';

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
        colorSchemeSeed: const Color(0xFF0B6E99),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF0B6E99),
      ),
      home: const SessionsScreen(),
    );
  }
}
