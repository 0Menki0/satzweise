import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:satzweise/data/store.dart';
import 'package:satzweise/logic/controller.dart';
import 'package:satzweise/logic/workout.dart';
import 'package:satzweise/platform/lock_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('de_DE'));

  late DateTime t;
  late AppController c;
  setUp(() async {
    t = DateTime(2026, 11, 26, 17);
    c = AppController(store: MemoryStore(), now: () => t);
    await c.load();
  });
  tearDown(() => c.dispose());

  LockContent l() => lockContent(c)!;
  List<List<String>> rows() => [
        for (final r in l().rows) [for (final a in r) a.id],
      ];
  String? primary() => l().all.where((a) => a.primary).firstOrNull?.id;

  test('ohne Training keine Benachrichtigung', () {
    expect(lockContent(c), isNull);
  });

  test('ganzer Ablauf nur über die Knöpfe des Sperrbildschirms', () {
    c.startWorkout('limbs');
    expect(l().title, 'Womit startest du?');
    expect(l().wide!.id, 'cancel', reason: 'Training beenden schon vor der ersten Übung');
    runLockAction(c, l().all.firstWhere((a) => a.id.startsWith('pick:')).id);

    expect(l().status, LockStatus.warmup);
    expect(rows(), [
      ['startSet'],
    ]);
    expect(l().setStart, t, reason: 'Aufwärmzeit läuft ab der Übungswahl');
    runLockAction(c, 'startSet');

    expect(l().status, LockStatus.setRunning);
    expect(l().title, endsWith('Satz 1'));
    expect(rows(), [
      ['done'],
    ]);
    runLockAction(c, 'done');

    expect(c.workout!.phase, Phase.log);
    expect(l().status, LockStatus.resting, reason: 'Pause läuft schon beim Eintragen');
    expect(rows(), [
      ['repsMinus', 'repsPlus', 'cont'],
      ['weightMinus', 'weightPlus', 'end'],
    ]);
    expect(primary(), 'cont');
    final before = c.workout!.currentSet!.reps;
    runLockAction(c, 'repsPlus');
    expect(c.workout!.sets.first.reps, before + 1, reason: 'Eintragen ändert den beendeten Satz');
    runLockAction(c, 'cont');

    expect(c.workout!.phase, Phase.rest);
    expect(rows(), [
      ['restMinus', 'restPlus', 'skip'],
    ]);
    expect(l().restEnd, t.add(const Duration(seconds: 90)));
    runLockAction(c, 'restPlus');
    expect(l().restEnd, t.add(const Duration(seconds: 105)));
    expect(l().restStart, t);
    runLockAction(c, 'skip');
    expect(c.workout!.phase, Phase.set);
    runLockAction(c, 'done');
    runLockAction(c, 'end');

    expect(rows(), [
      ['rate:leicht', 'rate:passend', 'rate:schwer'],
    ]);
    runLockAction(c, 'rate:passend');
    expect(c.workout!.phase, Phase.next);
    expect(l().text, contains('nächstes Mal'));
    expect(l().wide!.id, 'finish');
    runLockAction(c, 'finish');
    expect(rows().single, ['undo', 'save']);
    runLockAction(c, 'save');
    expect(c.sessions, hasLength(1));
    expect(lockContent(c), isNull);
  });

  test('höchstens zwei Reihen à drei Knöpfe in jedem Schritt', () {
    void check() {
      expect(l().rows.length, lessThanOrEqualTo(2));
      for (final r in l().rows) {
        expect(r.length, lessThanOrEqualTo(3));
      }
    }

    c.startWorkout('torso');
    check();
    c.pickExercise('Bankdrücken');
    check();
    c.startSet();
    check();
    c.completeSet();
    check();
    c.continueSets();
    check();
  });

  test('Ton-Einstellung geht mit an die Benachrichtigung', () {
    c.startWorkout('torso');
    expect(l().toMap()['sound'], isFalse);
    c.setRestSound(true);
    expect(l().toMap()['sound'], isTrue);
  });

  test('Brücke schickt nur bei Änderungen und beendet die Benachrichtigung', () async {
    final calls = <String>[];
    const ch = MethodChannel('test/lock');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (m) async {
      calls.add(m.method);
      return m.method == 'pendingActions' ? <String>[] : null;
    });
    await LockScreenBridge(c, channel: ch).start();
    calls.clear();
    c.startWorkout('torso');
    await pumpEventQueue();
    c.tick();
    c.tick();
    await pumpEventQueue();
    expect(calls, ['update'], reason: 'Sekundentakt löst kein erneutes Senden aus');
    c.cancelWorkout();
    await pumpEventQueue();
    expect(calls.last, 'stop');
  });
}
