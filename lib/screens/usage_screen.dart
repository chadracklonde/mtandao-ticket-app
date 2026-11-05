import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/live_usage.dart';
import '../services/mikhmon_service.dart';
import '../util.dart';
import '../widgets/desktop.dart';

/// « Qui consomme le plus » : débit de chaque client connecté, mis à jour en
/// direct, avec de quoi ralentir, déconnecter ou bloquer celui qui sature la ligne.
class UsageScreen extends StatefulWidget {
  const UsageScreen({super.key, required this.service, this.interval = const Duration(seconds: 3)});

  final MikhmonService service;
  final Duration interval;

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  Timer? _timer;
  List<ActiveUser>? _prev;
  DateTime? _prevAt;
  List<UserRate> _rates = const [];
  Set<String> _slowed = {};
  String? _error;
  bool _loaded = false;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(widget.interval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final now = DateTime.now();
      final active = await widget.service.activeUsers();
      Set<String> slowed = _slowed;
      try {
        slowed = await widget.service.slowedAddresses();
      } catch (_) {}
      final prev = _prev;
      final prevAt = _prevAt;
      final rates = prev == null || prevAt == null ? computeRates(active, active, Duration.zero) : computeRates(prev, active, now.difference(prevAt));
      _prev = active;
      _prevAt = now;
      if (mounted) {
        setState(() {
          _rates = rates;
          _slowed = slowed;
          _error = null;
          _loaded = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      _polling = false;
    }
  }

  Future<void> _do(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) showMessage(context, done);
      await _poll();
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    }
  }

  Future<void> _block(ActiveUser a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bloquer cet appareil ?'),
        content: Text('L\'appareil ${a.mac} sera déconnecté et ne pourra plus se connecter. '
            'Vous pourrez le débloquer dans « Abus et appareils bloqués ».'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bloquer')),
        ],
      ),
    );
    if (ok == true) {
      await _do(() => widget.service.blockDevice(a.mac, note: a.user), 'Appareil bloqué');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (!_loaded) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)),
      );
    }
    final totalDown = _rates.fold<double>(0, (s, r) => s + r.downBps);
    final totalUp = _rates.fold<double>(0, (s, r) => s + r.upBps);
    final top = _rates.isEmpty ? 0.0 : _rates.first.totalBps;
    return ContentWidth(
      maxWidth: 820,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Téléchargement', style: t.bodySmall),
                      Text(formatSpeed(totalDown), style: t.titleLarge),
                    ]),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Envoi', style: t.bodySmall),
                      Text(formatSpeed(totalUp), style: t.titleLarge),
                    ]),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Connectés', style: t.bodySmall),
                      Text('${_rates.length}', style: t.titleLarge),
                    ]),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Routeur injoignable : $_error', style: t.bodySmall?.copyWith(color: Colors.orange.shade800)),
            ),
          const SizedBox(height: 8),
          Text('Du plus gourmand au moins gourmand · mise à jour toutes les ${widget.interval.inSeconds} s',
              style: t.bodySmall),
          const SizedBox(height: 8),
          if (_rates.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Aucun client connecté.'))),
          for (final r in _rates) _row(context, r, top),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, UserRate r, double top) {
    final t = Theme.of(context).textTheme;
    final a = r.session;
    final slow = _slowed.contains(a.address);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(a.user, style: t.titleMedium?.copyWith(fontFamily: 'monospace')),
              ),
              if (slow)
                const Chip(label: Text('Ralenti'), visualDensity: VisualDensity.compact),
              const SizedBox(width: 8),
              Text(formatSpeed(r.totalBps), style: t.titleMedium),
            ]),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: top <= 0 ? 0 : (r.totalBps / top).clamp(0.0, 1.0)),
            const SizedBox(height: 6),
            Text(
              '↓ ${formatSpeed(r.downBps)} · ↑ ${formatSpeed(r.upBps)} · ${a.address} · ${a.mac}\n'
              'Depuis ${a.uptime} · ${formatBytes(a.bytesIn + a.bytesOut)} échangés',
              style: t.bodySmall,
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, children: [
              if (slow)
                OutlinedButton(
                  onPressed: () => _do(() => widget.service.unslowDevice(a.address), 'Vitesse rétablie'),
                  child: const Text('Rétablir'),
                )
              else
                OutlinedButton(
                  onPressed: () => _do(() => widget.service.slowDevice(a.address), 'Appareil ralenti (256 kb/s)'),
                  child: const Text('Ralentir'),
                ),
              OutlinedButton(
                onPressed: () => _do(() => widget.service.disconnect(a.id), 'Client déconnecté'),
                child: const Text('Déconnecter'),
              ),
              TextButton.icon(
                onPressed: a.mac.isEmpty ? null : () => _block(a),
                icon: const Icon(Icons.block, size: 18),
                label: const Text('Bloquer'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
