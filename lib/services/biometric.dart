import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

/// Empreinte digitale ou visage du téléphone, en complément du code.
abstract class BiometricAuth {
  /// Le téléphone sait lire une empreinte ou un visage, et il y en a d'enregistrés.
  Future<bool> isAvailable();

  /// Demande l'empreinte. Faux si refusée, annulée ou indisponible.
  Future<bool> authenticate(String reason);
}

class DeviceBiometricAuth implements BiometricAuth {
  const DeviceBiometricAuth();

  static bool get _platformOk =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<bool> isAvailable() async {
    if (!_platformOk) return false;
    try {
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) return false;
      return (await auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    if (!_platformOk) return false;
    try {
      return await LocalAuthentication().authenticate(
        localizedReason: reason,
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Mtandao Ticket',
            biometricHint: '',
            cancelButton: 'Utiliser le code',
          ),
        ],
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }
}
