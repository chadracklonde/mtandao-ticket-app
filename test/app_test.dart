import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('premier lancement : aucun routeur enregistré', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MtandaoApp());
    await tester.pumpAndSettle();
    expect(find.text('Mtandao Ticket'), findsWidgets);
    expect(find.textContaining('Aucun routeur enregistré'), findsOneWidget);
    expect(find.text('Nouveau routeur'), findsOneWidget);
  });

  testWidgets('le formulaire de routeur s\'ouvre avec les valeurs par défaut', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MtandaoApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nouveau routeur'));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau routeur'), findsWidgets);
    expect(find.text('192.168.88.1'), findsOneWidget);
    expect(find.text('8728'), findsOneWidget);
    expect(find.text('FC'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Tester la connexion'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Tester la connexion'), findsOneWidget);
  });
}
