import 'package:flutter/material.dart';

import '../util.dart';

/// Charge des données, affiche chargement / erreur, et permet de tirer pour
/// actualiser. Le [builder] doit renvoyer un widget défilable (ListView).
class AsyncBody<T> extends StatefulWidget {
  const AsyncBody({super.key, required this.load, required this.builder});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<AsyncBody<T>> createState() => _AsyncBodyState<T>();
}

class _AsyncBodyState<T> extends State<AsyncBody<T>> {
  T? _data;
  bool _hasData = false;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _hasData = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
      if (_hasData) showMessage(context, describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasData) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: widget.builder(context, _data as T, _reload),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(describeError(_error ?? 'Erreur inconnue'), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Message centré affiché quand une liste est vide (défilable pour le pull-to-refresh).
class EmptyList extends StatelessWidget {
  const EmptyList(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(child: Text(text, textAlign: TextAlign.center)),
      ],
    );
  }
}
