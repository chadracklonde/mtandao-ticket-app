import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/mikhmon_service.dart';
import '../util.dart';
import '../widgets/async_body.dart';

/// Surveillance du routeur : processeur, mémoire, trafic en direct.
class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key, required this.service});

  final MikhmonService service;

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  static const _points = 60;
  Timer? _timer;
  RouterResource? _resource;
  List<String> _interfaces = [];
  String? _interface;
  final List<TrafficSample> _samples = [];
  Object? _error;
  bool _busy = false;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final list = await widget.service.interfaces();
      if (!mounted) return;
      setState(() {
        _interfaces = list;
        _interface = list.contains('ether1') ? 'ether1' : (list.isEmpty ? null : list.first);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    await _poll();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  Future<void> _poll() async {
    if (_busy || !mounted) return;
    _busy = true;
    try {
      if (_tick % 3 == 0) {
        final r = await widget.service.resource();
        if (mounted) setState(() => _resource = r);
      }
      _tick++;
      final name = _interface;
      if (name != null) {
        final t = await widget.service.traffic(name);
        if (mounted) {
          setState(() {
            _samples.add(t);
            if (_samples.length > _points) _samples.removeAt(0);
            _error = null;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _resource;
    final t = Theme.of(context).textTheme;
    final last = _samples.isEmpty ? null : _samples.last;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(describeError(_error!), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (r == null && _error == null) const Center(child: CircularProgressIndicator()),
        if (r != null) ...[
          Text('${r.board} · RouterOS ${r.version}', style: t.titleMedium),
          const SizedBox(height: 4),
          Text('Allumé depuis ${r.uptime}', style: t.bodySmall),
          const SizedBox(height: 16),
          Text('Processeur : ${r.cpuLoad} %'),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: (r.cpuLoad / 100).clamp(0.0, 1.0)),
          const SizedBox(height: 12),
          Text('Mémoire : ${formatBytes(r.usedMemory)} sur ${formatBytes(r.totalMemory)}'),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: r.memoryRatio.clamp(0.0, 1.0)),
        ],
        const SizedBox(height: 24),
        Text('Trafic en direct', style: t.titleMedium),
        const SizedBox(height: 8),
        if (_interfaces.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: _interface,
            decoration: const InputDecoration(labelText: 'Interface', border: OutlineInputBorder(), isDense: true),
            items: [for (final i in _interfaces) DropdownMenuItem(value: i, child: Text(i))],
            onChanged: (v) => setState(() {
              _interface = v;
              _samples.clear();
            }),
          ),
        const SizedBox(height: 8),
        if (last != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Text('↓ ${formatRate(last.rx)}', style: t.titleSmall),
              Text('↑ ${formatRate(last.tx)}', style: t.titleSmall),
            ],
          ),
        const SizedBox(height: 8),
        SizedBox(
          height: 140,
          child: CustomPaint(
            painter: _TrafficPainter(
              _samples,
              rxColor: Theme.of(context).colorScheme.primary,
              txColor: const Color(0xFFF5B301),
              gridColor: Theme.of(context).dividerColor,
            ),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.circle, size: 10, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 4),
            const Text('Reçu (↓)'),
            const SizedBox(width: 16),
            const Icon(Icons.circle, size: 10, color: Color(0xFFF5B301)),
            const SizedBox(width: 4),
            const Text('Envoyé (↑)'),
          ],
        ),
      ],
    );
  }
}

class _TrafficPainter extends CustomPainter {
  _TrafficPainter(this.samples, {required this.rxColor, required this.txColor, required this.gridColor});

  final List<TrafficSample> samples;
  final Color rxColor;
  final Color txColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (samples.length < 2) return;
    var max = 1;
    for (final s in samples) {
      if (s.rx > max) max = s.rx;
      if (s.tx > max) max = s.tx;
    }
    Path path(int Function(TrafficSample) v) {
      final p = Path();
      for (var i = 0; i < samples.length; i++) {
        final x = size.width * i / (_MonitorScreenState._points - 1);
        final y = size.height - size.height * v(samples[i]) / max;
        i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
      }
      return p;
    }

    canvas.drawPath(
        path((s) => s.rx),
        Paint()
          ..color = rxColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    canvas.drawPath(
        path((s) => s.tx),
        Paint()
          ..color = txColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _TrafficPainter old) => true;
}

/// Journal du routeur, filtrable.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key, required this.service});
  final MikhmonService service;

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    return AsyncBody<List<LogEntry>>(
      load: () => widget.service.logs(),
      builder: (context, entries, reload) {
        final shown = entries
            .where((e) => switch (_filter) {
                  'hotspot' => e.isHotspot,
                  'error' => e.isError,
                  _ => true,
                })
            .toList();
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final (key, label) in const [('all', 'Tout'), ('hotspot', 'Hotspot'), ('error', 'Erreurs')])
                    ChoiceChip(
                      label: Text(label),
                      selected: _filter == key,
                      onSelected: (_) => setState(() => _filter = key),
                    ),
                ],
              ),
            ),
            if (shown.isEmpty)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Aucune ligne.'))),
            for (final e in shown)
              ListTile(
                dense: true,
                title: Text(e.message),
                subtitle: Text('${e.time} · ${e.topics}'),
                titleTextStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: e.isError ? Theme.of(context).colorScheme.error : null,
                    ),
              ),
          ],
        );
      },
    );
  }
}

/// Appareils connus du serveur DHCP (baux).
class LeasesScreen extends StatefulWidget {
  const LeasesScreen({super.key, required this.service});
  final MikhmonService service;

  @override
  State<LeasesScreen> createState() => _LeasesScreenState();
}

class _LeasesScreenState extends State<LeasesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return AsyncBody<List<DhcpLease>>(
      load: widget.service.dhcpLeases,
      builder: (context, leases, reload) {
        final q = _query.trim().toLowerCase();
        final shown = leases
            .where((l) =>
                q.isEmpty ||
                l.address.contains(q) ||
                l.mac.toLowerCase().contains(q) ||
                l.hostName.toLowerCase().contains(q) ||
                l.comment.toLowerCase().contains(q))
            .toList();
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                autocorrect: false,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Adresse, nom ou adresse MAC',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('${shown.length} appareil(s)', style: Theme.of(context).textTheme.bodySmall),
            ),
            for (final l in shown)
              ListTile(
                dense: true,
                title: Text(l.hostName.isEmpty ? l.address : '${l.hostName} · ${l.address}'),
                subtitle: Text([l.mac, if (l.comment.isNotEmpty) l.comment].join(' · ')),
                trailing: Text(l.status, style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        );
      },
    );
  }
}
