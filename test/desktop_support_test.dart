import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/models.dart';
import 'package:mtandao_ticket/services/file_delivery.dart';
import 'package:mtandao_ticket/services/session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('dossier d\'enregistrement sur ordinateur', () {
    expect(desktopExportDir({'USERPROFILE': r'C:\\Users\\chad'}, windows: true),
        r'C:\\Users\\chad\\Documents\\Mtandao Ticket');
    expect(desktopExportDir({'HOME': '/Users/chad'}, windows: false),
        '/Users/chad/Documents/Mtandao Ticket');
  });

  test('connexions enregistrées même sans stockage sécurisé', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SessionStore();
    final s = Session(id: 'a1', name: 'Wifi zone', host: '192.168.88.1', username: 'admin', password: 'secret');
    await store.save(s);
    final back = await store.load();
    expect(back.single.name, 'Wifi zone');
    expect(back.single.password, 'secret');
    await store.delete('a1');
    expect(await store.load(), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pw_a1'), isNull);
  });
}
