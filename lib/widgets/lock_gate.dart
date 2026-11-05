import 'package:flutter/material.dart';

import '../services/app_lock.dart';
import '../services/biometric.dart';

/// Recouvre l'application d'un écran de code quand le verrouillage est actif :
/// au démarrage, et quand l'application est restée plus de [delay] en arrière-plan.
class LockGate extends StatefulWidget {
  const LockGate({
    super.key,
    required this.child,
    this.lock,
    this.biometrics = const DeviceBiometricAuth(),
    this.delay = const Duration(seconds: 30),
  });

  final Widget child;
  final AppLock? lock;
  final BiometricAuth biometrics;
  final Duration delay;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  late final AppLock _lock = widget.lock ?? AppLock();
  bool _ready = false;
  bool _locked = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lock.isEnabled().then((on) {
      if (mounted) {
        setState(() {
          _locked = on;
          _ready = true;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final at = _pausedAt;
      _pausedAt = null;
      if (at != null && DateTime.now().difference(at) >= widget.delay) {
        _lock.isEnabled().then((on) {
          if (mounted && on) setState(() => _locked = true);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const ColoredBox(color: Color(0xFF0E2A47));
    return Stack(
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            // Overlay propre : ce widget est au-dessus du Navigator de l'application.
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) => LockScreen(
                    lock: _lock,
                    biometrics: widget.biometrics,
                    onUnlock: () => setState(() => _locked = false),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.lock,
    required this.onUnlock,
    this.biometrics = const DeviceBiometricAuth(),
  });

  final AppLock lock;
  final BiometricAuth biometrics;
  final VoidCallback onUnlock;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pin = TextEditingController();
  String? _error;
  int _failures = 0;
  DateTime? _blockedUntil;
  bool _bio = false;
  bool _asking = false;
  BioKind _kind = BioKind.fingerprint;

  @override
  void initState() {
    super.initState();
    _startBiometric();
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  /// Propose l'empreinte dès l'affichage ; le code reste toujours possible.
  Future<void> _startBiometric() async {
    if (!await widget.lock.biometricEnabled() || !await widget.biometrics.isAvailable()) return;
    final kind = await widget.biometrics.kind();
    if (mounted) {
      setState(() {
        _bio = true;
        _kind = kind;
      });
    }
    await _askBiometric();
  }

  Future<void> _askBiometric() async {
    if (_asking) return;
    _asking = true;
    final ok = await widget.biometrics.authenticate('Déverrouiller Mtandao Ticket');
    _asking = false;
    if (ok && mounted) widget.onUnlock();
  }

  Future<void> _submit() async {
    final until = _blockedUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      setState(() => _error = 'Trop d\'essais. Patientez quelques secondes.');
      return;
    }
    if (await widget.lock.verify(_pin.text)) {
      widget.onUnlock();
      return;
    }
    _failures++;
    _pin.clear();
    setState(() {
      if (_failures >= 5) {
        _blockedUntil = DateTime.now().add(const Duration(seconds: 30));
        _failures = 0;
        _error = 'Code incorrect. Nouvel essai possible dans 30 secondes.';
      } else {
        _error = 'Code incorrect.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0E2A47),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, color: Colors.white, size: 40),
                  const SizedBox(height: 12),
                  const Text('Mtandao Ticket',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('Entrez votre code', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _pin,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 8,
                    style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
                    decoration: InputDecoration(
                      counterText: '',
                      errorText: _error,
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: _submit, child: const Text('Déverrouiller')),
                  if (_bio) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _askBiometric,
                      icon: const Icon(Icons.fingerprint, color: Colors.white),
                      label: Text('Utiliser ${_kind.use}', style: const TextStyle(color: Colors.white)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
