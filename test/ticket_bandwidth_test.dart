import 'package:flutter_test/flutter_test.dart';
import 'package:mtandao_ticket/routeros/api_client.dart';
import 'package:mtandao_ticket/services/ticket_bandwidth.dart';

void main() {
  test('identifiant strict et débits proposés', () {
    expect(TicketBandwidth.marker('*1A'), 'mkm-ticket:*1A');
    expect(() => TicketBandwidth.marker('x; /system reboot'), throwsA(isA<RouterOsException>()));
    expect(TicketBandwidth.rates, ['256k', '512k', '1M', '2M']);
  });

  test('création : une file agrégée et un scheduler persistant', () async {
    final calls = <List<String>>[];
    final service = TicketBandwidth.withRunner((words) async {
      calls.add(words);
      if (words.first == '/ip/hotspot/user/print') return [{'.id': '*1'}];
      return <Map<String, String>>[];
    });
    await service.save('*1', '512k');
    final queue = calls.singleWhere((w) => w.first == '/queue/simple/add');
    expect(queue, contains('=max-limit=512k/512k'));
    expect(queue, contains('=comment=mkm-ticket:*1'));
    expect(queue, contains('=disabled=yes'));
    expect(queue, contains('=target=127.0.0.1/32'));
    final scheduler = calls.singleWhere((w) => w.first == '/system/scheduler/add');
    expect(scheduler, contains('=interval=2s'));
    expect(scheduler, contains('=on-event=${TicketBandwidth.syncScript}'));
    expect(calls.any((w) => w.first.contains('/user/profile/')), isFalse);
  });

  test('mise à jour sans duplication et respect du parent commun', () async {
    final calls = <List<String>>[];
    final service = TicketBandwidth.withRunner((words) async {
      calls.add(words);
      if (words.first == '/ip/hotspot/user/print') return [{'.id': '*1'}];
      if (words.contains('?comment=mkm-ticket:*1')) return [{'.id': '*A', 'max-limit': '256k/256k'}];
      if (words.contains('?name=mkm-total')) return [{'.id': '*B'}];
      return <Map<String, String>>[];
    });
    await service.save('*1', '1M');
    expect(calls.any((w) => w.first == '/queue/simple/add'), isFalse);
    final update = calls.singleWhere((w) => w.first == '/queue/simple/set');
    expect(update, contains('=.id=*A'));
    expect(update, contains('=max-limit=1M/1M'));
    expect(update, contains('=parent=mkm-total'));
  });

  test('lecture et retrait limités au ticket demandé', () async {
    final calls = <List<String>>[];
    final service = TicketBandwidth.withRunner((words) async {
      calls.add(words);
      if (words.first.endsWith('/print')) return [{'.id': '*A', 'max-limit': '2M/2M'}];
      return <Map<String, String>>[];
    });
    expect(await service.read('*1'), '2M/2M');
    await service.remove('*1');
    expect(calls.last, ['/queue/simple/remove', '=.id=*A']);
    expect(calls.where((w) => w.first.endsWith('/print')).every((w) => w.contains('?comment=mkm-ticket:*1')), isTrue);
  });

  test('FastTrack et débit invalide : aucune écriture', () async {
    final calls = <List<String>>[];
    final service = TicketBandwidth.withRunner((words) async {
      calls.add(words);
      if (words.first == '/ip/hotspot/user/print') return [{'.id': '*1'}];
      if (words.first == '/ip/firewall/filter/print') return [{'disabled': 'false'}];
      return <Map<String, String>>[];
    });
    await expectLater(service.save('*1', '0'), throwsA(isA<RouterOsException>()));
    expect(calls, isEmpty);
    await expectLater(service.save('*1', '256k'), throwsA(isA<RouterOsException>()));
    expect(calls.every((w) => w.first.endsWith('/print')), isTrue);
  });

  test('script : agrégation, nettoyage et absence de modification des profils', () {
    final script = TicketBandwidth.syncScript;
    expect(script, contains(r'user=$username'));
    expect(script, contains(r':set targets ($targets,($ip . "/32"))'));
    expect(script, contains(r'target=$targets'));
    expect(script, contains('disabled=yes'));
    expect(script, contains(r'/queue simple remove $q'));
    expect(script, isNot(contains('/ip hotspot user profile set')));
  });
}
