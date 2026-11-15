import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'sync_outbox.dart';

typedef SyncSiteProvider = Future<String?> Function();
typedef SyncTokenProvider = Future<String?> Function();
typedef SyncResultHandler = void Function(SyncFlushResult result);
typedef SyncErrorHandler = void Function(Object error);

/// Triggers durable outbox delivery when a network becomes available and on a
/// bounded periodic retry. Authentication and active-site state are supplied
/// by the host app; this coordinator never stores credentials.
class SyncCoordinator {
  SyncCoordinator({
    required this.outbox,
    required this.apiBaseUri,
    required this.siteProvider,
    required this.accessTokenProvider,
    Connectivity? connectivity,
    this.retryInterval = const Duration(minutes: 1),
    this.onResult,
    this.onError,
  }) : _connectivity = connectivity ?? Connectivity();

  final SyncOutbox outbox;
  final Uri apiBaseUri;
  final SyncSiteProvider siteProvider;
  final SyncTokenProvider accessTokenProvider;
  final Connectivity _connectivity;
  final Duration retryInterval;
  final SyncResultHandler? onResult;
  final SyncErrorHandler? onError;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _retryTimer;
  bool _running = false;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        unawaited(_syncIfReady());
      }
    });
    _retryTimer = Timer.periodic(retryInterval, (_) {
      unawaited(_syncIfReady());
    });
    await _syncIfReady();
  }

  Future<void> _syncIfReady() async {
    if (_running) return;
    _running = true;
    try {
      final connectivity = await _connectivity.checkConnectivity();
      if (connectivity.every((result) => result == ConnectivityResult.none)) {
        return;
      }
      final siteId = await siteProvider();
      final accessToken = await accessTokenProvider();
      if (siteId == null || siteId.isEmpty ||
          accessToken == null || accessToken.isEmpty) {
        return;
      }

      while (true) {
        final result = await outbox.flush(
          apiBaseUri: apiBaseUri,
          siteId: siteId,
          accessToken: accessToken,
        );
        onResult?.call(result);
        if (result.sent < SyncOutbox.maxBatchSize ||
            result.acknowledged != result.sent ||
            result.pending == 0) {
          break;
        }
      }
    } catch (error) {
      onError?.call(error);
    } finally {
      _running = false;
    }
  }

  Future<void> dispose() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
  }
}
