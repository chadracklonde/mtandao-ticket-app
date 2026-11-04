import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Vrai sur Windows, macOS et Linux. Android (et le web) gardent l'affichage téléphone.
bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Sur ordinateur, centre le contenu et limite sa largeur (formulaires lisibles
/// sur grand écran). Sur téléphone, ne change rien.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 720});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}
