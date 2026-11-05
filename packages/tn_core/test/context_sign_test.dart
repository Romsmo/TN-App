import 'package:test/test.dart';
import 'package:tn_core/tn_core.dart';

import 'flow_test.dart' show FakeBackend;
import 'session_test.dart' show Harness;
import 'vec.dart';

ContextSign sign(
  String type, {
  String? id,
  double starts = -50,
  bool active = true,
  bool confirmed = true,
}) =>
    ContextSign(id: id ?? 'id-$type-$starts', signType: type, startsInM: starts, activeNow: active, confirmed: confirmed, confirmations: confirmed ? 3 : 1);

void main() {
  group('signColumnsFor', () {
    test('an empty answer gives empty columns', () {
      expect(signColumnsFor(const []).isEmpty, isTrue);
    });

    test('prohibitions go left, warnings right, as wire codes', () {
      final c = signColumnsFor([sign('DE:276'), sign('DE:142-10')]);
      expect(c.left, [27600]);
      expect(c.right, [14210]);
    });

    test('an unconfirmed, inactive or far-ahead sign is not shown', () {
      final c = signColumnsFor([
        sign('DE:276', confirmed: false),
        sign('DE:283', active: false),
        sign('DE:286', starts: 101),
      ]);
      expect(c.isEmpty, isTrue);
      expect(signColumnsFor([sign('DE:286', starts: 100)]).left, [28600]);
    });

    test('another country and a sign the display cannot draw are dropped', () {
      final c = signColumnsFor([sign('AT:276'), sign('DE:999'), sign('DE:274'), sign('nonsense'), sign('DE:123')]);
      expect(c.left, isEmpty);
      expect(c.right, [12300]);
    });

    test('a later sign replaces an earlier one of its family; the end sign ends the ban', () {
      // 276 began 400 m back, the end sign 10 m back: 280 is the newer one and takes 276 out
      final c = signColumnsFor([sign('DE:280', starts: -10), sign('DE:276', starts: -400)]);
      expect(c.left, [28000]);
    });

    test('the sign that began longest ago is the oldest and the cap keeps the newest three', () {
      final c = signColumnsFor([
        sign('DE:103-10', starts: -10),
        sign('DE:123', starts: -300),
        sign('DE:136-10', starts: -200),
        sign('DE:142-10', starts: -100),
      ]);
      // four warnings: the one that began longest ago (123) is pushed out
      expect(c.right, [13610, 14210, 10310]);
    });

    test('the result does not depend on the order the library listed the signs in', () {
      final list = [sign('DE:276', starts: -300), sign('DE:142-10', starts: -20), sign('DE:123', starts: -90)];
      expect(signColumnsFor(list.reversed), signColumnsFor(list));
    });

    test('names come from the display catalogue', () {
      expect(signNameOf('DE:276'), 'Überholverbot für Kraftfahrzeuge aller Art');
      expect(signNameOf('DE:274'), isNull);
      expect(vzNrOf('DE:142-10'), '142-10');
    });
  });

  group('library entries', () {
    test('ContextSign.fromJson reads an entry and leaves an unusable one out', () {
      final s = ContextSign.fromJson({
        'id': 'a',
        'signType': 'DE:253',
        'startsInM': -12.5,
        'endsInM': 300,
        'validUntil': '2026-10-14T15:00:00Z',
        'activeNow': true,
        'confirmed': true,
        'confirmations': 4,
        'value': 7.5,
        'unit': 't',
      })!;
      expect(s.signType, 'DE:253');
      expect(s.startsInM, -12.5);
      expect(s.endsInM, 300);
      expect(s.validUntil, DateTime.utc(2026, 10, 14, 15));
      expect(s.confirmations, 4);
      expect(s.value, 7.5);
      expect(s.unit, 't');
      expect(ContextSign.fromJson({'id': 'a', 'signType': 'DE:253'}), isNull);
      expect(ContextSign.fromJson('x'), isNull);
    });

    test('the expected answers of the library vectors are readable and give valid display codes', () {
      final v = vec('context-sign-vectors') as Map;
      final entries = {for (final e in (v['entries'] as List)) (e as Map)['id']: e};
      var read = 0;
      for (final c in (v['cases'] as List)) {
        final signs = <ContextSign>[];
        for (final x in ((c as Map)['expect'] as List)) {
          final entry = entries[(x as Map)['id']]!;
          // the library answers with the entry's own fields joined with the computed ones
          final parsed = ContextSign.fromJson({...entry, ...x});
          expect(parsed, isNotNull, reason: '${c['name']}');
          signs.add(parsed!);
          read++;
        }
        for (final code in [...signColumnsFor(signs).left, ...signColumnsFor(signs).right]) {
          expect(code, greaterThan(0));
        }
      }
      expect(read, greaterThan(20));
    });
  });

  group('service', () {
    test('getContextSigns asks for the position and heading, reads the signs and covered', () async {
      final b = FakeBackend((m, a) => {
            'covered': true,
            'entriesHeld': 1,
            'signs': [
              {'id': 'a', 'signType': 'DE:276', 'startsInM': -5, 'endsInM': 400, 'activeNow': true, 'confirmed': true, 'confirmations': 3},
              {'id': 'broken'},
            ],
          });
      final r = await TnService(b).getContextSigns(50, 10, heading: 90);
      expect(b.calls.single.$1, 'getContextSigns');
      expect(b.calls.single.$2, {'lat': 50.0, 'lng': 10.0, 'heading': 90.0, 'includeUnconfirmed': false});
      expect(r.covered, isTrue);
      expect(r.signs.map((s) => s.id), ['a']);
    });

    test('an answer without signs is empty and not covered', () async {
      final r = await TnService(FakeBackend((m, a) => <String, Object?>{})).getContextSigns(1, 2);
      expect(r.signs, isEmpty);
      expect(r.covered, isFalse);
    });

    test('voteContextSign and reportContextSign return the queue id', () async {
      final b = FakeBackend((m, a) => {'localId': 'q-$m'});
      final s = TnService(b);
      expect(await s.voteContextSign('a', true), 'q-voteContextSign');
      expect(b.calls.last.$2, {'id': 'a', 'agrees': true});
      expect(await s.reportContextSign({'signType': 'DE:276'}), 'q-reportContextSign');
    });
  });

  group('on the display', () {
    DisplayInput input(DriveSnapshot snap) {
      final cols = signColumnsFor(snap.contextSigns);
      return DisplayInput(snapshot: snap, caps: const DisplayCaps(), online: true, leftSigns: cols.left, rightSigns: cols.right);
    }

    test('a trip sends the columns, no trip sends none', () {
      final signs = [sign('DE:276'), sign('DE:142-10')];
      final trip = DisplayFeed().next(input(DriveSnapshot(active: true, contextSigns: signs)), 1000, epochS: 1)!;
      expect(trip.leftSigns, [27600]);
      expect(trip.rightSigns, [14210]);
      final idle = DisplayFeed().next(input(DriveSnapshot(contextSigns: signs)), 1000, epochS: 1)!;
      expect(idle.leftSigns, isEmpty);
      expect(idle.rightSigns, isEmpty);
    });

    test('a changed column is sent as a change, the same one only as keep-alive', () {
      final feed = DisplayFeed();
      final a = DriveSnapshot(active: true, contextSigns: [sign('DE:276')]);
      expect(feed.next(input(a), 0, epochS: 1), isNotNull);
      expect(feed.next(input(a), 1000, epochS: 1), isNull);
      final b = DriveSnapshot(active: true, contextSigns: [sign('DE:276'), sign('DE:123', starts: -10)]);
      expect(feed.next(input(b), 2000, epochS: 1)!.rightSigns, [12300]);
    });
  });

  group('drive session', () {
    test('the snapshot carries the signs of the position while the drive runs', () async {
      final h = Harness(signs: [sign('DE:276')]);
      h.session.start();
      await h.fix(0, 80, 0);
      expect(h.session.snapshot.contextSigns.map((s) => s.signType), ['DE:276']);
      h.session.stop();
    });

    test('a sign read that fails leaves no sign behind', () async {
      final h = Harness(signs: [sign('DE:276')]);
      h.session.start();
      await h.fix(0, 80, 0);
      expect(h.session.snapshot.contextSigns, isNotEmpty);
      h.data.failSigns = true;
      await h.fix(500, 80, 0);
      expect(h.session.snapshot.contextSigns, isEmpty);
      h.session.stop();
    });
  });
}
