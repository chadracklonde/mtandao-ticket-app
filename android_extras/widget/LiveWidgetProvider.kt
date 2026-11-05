package cd.xsoftdesign.mtandao_ticket

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews

/** Widget d'accueil : affiche le texte écrit par le service de notification (voir live_widget.dart). */
class LiveWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val title = prefs.getString("w_title", null) ?: "Mtandao Ticket"
        val body = prefs.getString("w_body", null)
            ?: "Activez la notification permanente dans l'application (Plus > Sécurité et alertes)."
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.mtandao_widget)
            views.setTextViewText(R.id.w_title, title)
            views.setTextViewText(R.id.w_body, body)
            if (launch != null) {
                val pi = PendingIntent.getActivity(
                    context, 0, launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.w_root, pi)
            }
            manager.updateAppWidget(id, views)
        }
    }
}
