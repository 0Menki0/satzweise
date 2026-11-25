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
    t = DateTime(2026, 11, 25, 17);
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

  test('ganzes Training nur über die Knöpfe des Sperrbildschirms', () {
    c.startWorkout('limbs');
    expect(l().title, 'Womit startest du?');
    runLockAction(c, l().all.firstWhere((a) => a.id.startsWith('pick:')).id);

    expect(l().status, LockStatus.setRunning);
    expect(l().title, endsWith('Satz 1'));
    expect(rows(), [
      ['repsMinus', 'repsPlus', 'done'],
      ['weightMinus', 'weightPlus', 'undo'],
    ]);
    expect(primary(), 'done');
    expect(l().wide, isNull, reason: 'Übung beenden erst nach dem ersten Satz');

    final before = c.workout!.sets.first.reps;
    runLockAction(c, 'repsPlus');
    expect(c.workout!.sets.first.reps, before + 1);
    runLockAction(c, 'undo');
    expect(c.workout!.sets.first.reps, before);
    final w0 = c.workout!.sets.first.weight;
    runLockAction(c, 'weightPlus');
    expect(c.workout!.sets.first.weight, greaterThan(w0));
    runLockAction(c, 'weightMinus');

    runLockAction(c, 'done');
    expect(l().status, LockStatus.resting);
    expect(l().title, 'Pause · danach Satz 2');
    expect(rows().first, ['restMinus', 'restPlus', 'skip']);
    expect(l().restStart, t);
    expect(l().restEnd, t.add(const Duration(seconds: 90)));
    runLockAction(c, 'restPlus');
    expect(l().restEnd, t.add(const Duration(seconds: 105)));
    runLockAction(c, 'skip');
    expect(l().status, LockStatus.setRunning);
    expect(l().wide!.label, 'Übung beenden (1 Sätze)');
    runLockAction(c, 'done');
    runLockAction(c, 'end');

    expect(rows(), [
      ['rate:leicht', 'rate:passend', 'rate:schwer'],
    ]);
    expect(l().wide!.id, 'undo');
    runLockAction(c, 'rate:leicht');
    expect(rows().single, ['keep', 'accept']);
    runLockAction(c, 'accept');
    expect(l().wide!.id, 'finish');
    runLockAction(c, 'finish');
    expect(c.workout!.phase, Phase.summary);
    expect(rows().single, ['undo', 'save']);
    runLockAction(c, 'save');
    expect(c.sessions, hasLength(1));
    expect(lockContent(c), isNull);
  });

  test('höchstens zwei Reihen à drei Knöpfe plus ein breiter in jedem Schritt', () {
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
    c.completeSet();
    check();
    c.endExercise();
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
