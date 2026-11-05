import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../routeros/api_client.dart';
import 'live_stats.dart';
import 'live_widget.dart';
import 'mikhmon_service.dart';
import 'session_store.dart';
import 'stock_alert.dart';

/// Notification permanente (Android) : ventes du jour, appareils connectés,
/// stock bas. Un service de premier plan garde sa propre connexion au routeur
/// et met la notification à jour toutes les 60 secondes, application fermée.
class LiveNotification {
  static const _prefKey = 'live_notification_session';
  static const _dataKey = 'sessionId';
  static const _serviceId = 4210;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// À appeler une fois au démarrage (main).
  static void initPort() {
    if (!supported) return;
    try {
      FlutterForegroundTask.initCommunicationPort();
    } catch (_) {}
  }

  static void _init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'mtandao_live',
        channelName: 'Activité du hotspot',
        channelDescription: 'Ventes du jour et appareils connectés',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Identifiant de la session pour laquelle la notification est activée.
  static Future<String?> enabledFor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_prefKey);
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isRunning() async {
    if (!supported) return false;
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }

  /// Active la notification pour [session]. Renvoie un message d'erreur, ou null.
  static Future<String?> enable(Session session) async {
    if (!supported) return 'Disponible seulement sur Android.';
    try {
      var perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        perm = await FlutterForegroundTask.requestNotificationPermission();
      }
      if (perm != NotificationPermission.granted) {
        return 'Autorisez les notifications pour Mtandao Ticket dans les réglages du téléphone.';
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, session.id);
      return await _start(session.id);
    } catch (e) {
      return 'Impossible d\'activer la notification : $e';
    }
  }

  static Future<String?> _start(String sessionId) async {
    _init();
    await FlutterForegroundTask.saveData(key: _dataKey, value: sessionId);
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
      return null;
    }
    final r = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      notificationTitle: 'Mtandao Ticket',
      notificationText: 'Lecture du routeur…',
      notificationIcon: const NotificationIcon(metaDataName: 'cd.xsoftdesign.mtandao_ticket.NOTIFICATION_ICON'),
      callback: liveNotificationCallback,
    );
    return r is ServiceRequestSuccess ? null : 'Le service n\'a pas pu démarrer.';
  }

  static Future<void> disable() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
    } catch (_) {}
    if (!supported) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
    await LiveWidget.clear();
  }

  /// À l'ouverture de l'application : relance le service s'il a été arrêté
  /// (redémarrage du téléphone, limite du système) et que l'option est active.
  static Future<void> resumeIfEnabled() async {
    if (!supported) return;
    try {
      final id = await enabledFor();
      if (id == null) return;
      if (await FlutterForegroundTask.isRunningService) return;
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) return;
      await _start(id);
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
void liveNotificationCallback() {
  FlutterForegroundTask.setTaskHandler(_LiveHandler());
}

class _LiveHandler extends TaskHandler {
  RouterOsClient? _client;
  Session? _session;

  Future<Session?> _loadSession() async {
    final id = await FlutterForegroundTask.getData<String>(key: LiveNotification._dataKey);
    if (id == null) return null;
    final all = await SessionStore().load();
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> _refresh() async {
    try {
      _session ??= await _loadSession();
      final s = _session;
      if (s == null) {
        FlutterForegroundTask.updateService(
            notificationTitle: 'Mtandao Ticket', notificationText: 'Routeur introuvable : rouvrez l\'application.');
        return;
      }
      final c = _client ??= RouterOsClient(
        host: s.host,
        port: s.port,
        useSsl: s.useSsl,
        verifyCertificate: s.verifyCert,
        username: s.username,
        password: s.password,
        connectTimeout: const Duration(seconds: 8),
        commandTimeout: const Duration(seconds: 15),
      );
      final service = MikhmonService(c, s);
      final sales = await service.sales();
      final active = await service.activeUsers();
      var low = const <MapEntry<String, int>>[];
      try {
        final threshold = await StockAlertStore().load();
        if (threshold > 0) {
          final profiles = await service.profiles();
          final batches = await service.unusedBatches();
          low = [for (final l in lowStock(profiles, batches, threshold)) MapEntry(l.profile, l.left)];
        }
      } catch (_) {}
      final stats = computeLiveStats(sales, active.length, DateTime.now(), lowStock: low);
      final title = liveTitle(stats, s.currency);
      final body = liveBody(stats);
      FlutterForegroundTask.updateService(notificationTitle: title, notificationText: body);
      await LiveWidget.push(title, body);
    } catch (_) {
      _client?.close();
      _client = null;
      FlutterForegroundTask.updateService(
        notificationTitle: 'Mtandao Ticket',
        notificationText: 'Routeur injoignable. Nouvel essai dans une minute.',
      );
    }
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _refresh();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _refresh();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _client?.close();
    _client = null;
  }
}
