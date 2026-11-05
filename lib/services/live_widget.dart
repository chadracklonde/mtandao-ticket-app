import 'package:home_widget/home_widget.dart';

import 'live_notification.dart';

/// Widget d'accueil Android : montre le même texte que la notification permanente.
/// Le service de notification l'alimente ; sans lui, le widget invite à l'activer.
class LiveWidget {
  static const _provider = 'cd.xsoftdesign.mtandao_ticket.LiveWidgetProvider';

  static Future<void> push(String title, String body) async {
    if (!LiveNotification.supported) return;
    try {
      await HomeWidget.saveWidgetData<String>('w_title', title);
      await HomeWidget.saveWidgetData<String>('w_body', body);
      await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
    } catch (_) {
      // Pas de widget posé, ou plugin indisponible : sans importance.
    }
  }

  static Future<void> clear() => push(
        'Mtandao Ticket',
        'Activez la notification permanente dans l\'application (Plus > Sécurité et alertes).',
      );
}
