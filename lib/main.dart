import 'package:flutter/material.dart';
import 'services/live_notification.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/sessions_screen.dart';
import 'widgets/desktop.dart';
import 'widgets/lock_gate.dart';

// Charte : voir docs/identite-visuelle.md
const _blueSignal = Color(0xFF0F5FD0);
const _ink = Color(0xFF0E2A47);

ThemeData _buildTheme(Brightness brightness) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorSchemeSeed: _blueSignal,
    fontFamily: 'Inter',
  );
  TextStyle? sora(TextStyle? s, FontWeight w) => s?.copyWith(fontFamily: 'Sora', fontWeight: w);
  final t = base.textTheme;
  final light = brightness == Brightness.light;
  return base.copyWith(
    scaffoldBackgroundColor: light ? const Color(0xFFF4F7FB) : null,
    textTheme: t.copyWith(
      headlineSmall: sora(t.headlineSmall, FontWeight.w800),
      titleLarge: sora(t.titleLarge, FontWeight.w800),
      titleMedium: sora(t.titleMedium, FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: light ? _ink : null,
      foregroundColor: light ? Colors.white : null,
      titleTextStyle: sora(t.titleLarge, FontWeight.w800)?.copyWith(
        color: light ? Colors.white : null,
      ),
    ),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LiveNotification.initPort();
  runApp(const MtandaoApp());
}

class MtandaoApp extends StatelessWidget {
  const MtandaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mtandao Ticket',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      // Téléphone : le contenu garde une largeur de téléphone large, centrée.
      // Ordinateur (Windows, macOS) : toute la fenêtre est utilisée, la mise en
      // page s'adapte (barre latérale, colonnes).
      builder: (context, child) => LockGate(
        child: isDesktopPlatform
            ? child!
            : ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: child,
                  ),
                ),
              ),
      ),
      home: const SessionsScreen(),
    );
  }
}
