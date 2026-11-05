import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/screens/security_screen.dart';
import 'package:mtandao_ticket/services/app_lock.dart';
import 'package:mtandao_ticket/services/biometric.dart';
import 'package:mtandao_ticket/widgets/lock_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeBio implements BiometricAuth {
  FakeBio({this.available = true, this.accepts = true});
  final bool available;
  bool accepts;
  int asked = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    asked++;
    return accepts;
  }
}

Future<void> settle(WidgetTester tester, [int rounds = 10]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('réglage empreinte enregistré, effacé avec le verrouillage', () async {
    final lock = AppLock();
    await lock.setPin('1234');
    expect(await lock.biometricEnabled(), isFalse);
    await lock.setBiometricEnabled(true);
    expect(await lock.biometricEnabled(), isTrue);
    await lock.disable();
    expect(await lock.biometricEnabled(), isFalse);
  });

  testWidgets('l\'empreinte déverrouille sans taper le code', (tester) async {
    final lock = AppLock();
    await lock.setPin('1234');
    await lock.setBiometricEnabled(true);
    final bio = FakeBio();
    await tester.pumpWidget(MaterialApp(home: LockGate(lock: lock, biometrics: bio, child: const Text('contenu'))));
    await settle(tester);
    expect(bio.asked, 1);
    expect(find.text('contenu'), findsOneWidget);
    expect(find.text('Entrez votre code'), findsNothing);
  });

  testWidgets('empreinte refusée : le code reste possible', (tester) async {
    final lock = AppLock();
    await lock.setPin('1234');
    await lock.setBiometricEnabled(true);
    final bio = FakeBio(accepts: false);
    await tester.pumpWidget(MaterialApp(home: LockGate(lock: lock, biometrics: bio, child: const Text('contenu'))));
    await settle(tester);
    expect(find.text('Entrez votre code'), findsOneWidget);
    expect(find.text('Utiliser l\'empreinte'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Déverrouiller'));
    await settle(tester);
    expect(find.text('contenu'), findsOneWidget);
  });

  testWidgets('sans capteur ou sans réglage, pas de bouton empreinte', (tester) async {
    final lock = AppLock();
    await lock.setPin('1234');
    await tester.pumpWidget(
        MaterialApp(home: LockGate(lock: lock, biometrics: FakeBio(), child: const Text('contenu'))));
    await settle(tester);
    expect(find.text('Utiliser l\'empreinte'), findsNothing);
  });

  testWidgets('réglages : activer l\'empreinte demande une confirmation', (tester) async {
    final lock = AppLock();
    await lock.setPin('1234');
    final bio = FakeBio(accepts: false);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SecurityScreen(biometrics: bio))));
    await settle(tester);
    await tester.tap(find.text('Déverrouiller par empreinte'));
    await settle(tester);
    expect(bio.asked, 1);
    expect(await lock.biometricEnabled(), isFalse);
    bio.accepts = true;
    await tester.tap(find.text('Déverrouiller par empreinte'));
    await settle(tester);
    expect(await lock.biometricEnabled(), isTrue);
  });
}
