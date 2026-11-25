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
  List<String> ids() => l().buttons.map((a) => a.id).toList();

  test('ohne Training keine Player-Karte', () {
    expect(lockContent(c), isNull);
  });

  test('ganzes Training nur über die Knöpfe des Sperrbildschirms', () {
    c.startWorkout('limbs');
    expect(l().title, 'Womit startest du?');
    expect(ids().first, 'undo');
    runLockAction(c, ids().firstWhere((i) => i.startsWith('pick:')));

    expect(l().mode, LockMode.set);
    expect(l().title, endsWith('Satz 1/3'));
    expect(l().primary!.id, 'done', reason: '⏸ beendet den Satz');
    expect(ids(), ['undo', 'repsMinus', 'repsPlus', 'end']);
    expect(l().subtitle, contains('{total}'));

    final before = c.workout!.sets.first.reps;
    runLockAction(c, 'repsPlus');
    expect(c.workout!.sets.first.reps, before + 1);
    runLockAction(c, 'undo');
    expect(c.workout!.sets.first.reps, before);

    runLockAction(c, 'done');
    expect(l().mode, LockMode.rest);
    expect(l().primary!.id, 'skip', reason: '▶ geht weiter');
    expect(l().restStart, t);
    expect(l().restEnd, t.add(const Duration(seconds: 90)));
    runLockAction(c, 'restPlus');
    expect(l().restEnd, t.add(const Duration(seconds: 105)));
    expect(l().restStart, t, reason: 'Balken beginnt weiter beim Satzende');
    runLockAction(c, 'restMinus');
    runLockAction(c, 'skip');
    expect(l().mode, LockMode.set);
    runLockAction(c, 'done');
    runLockAction(c, 'skip');
    runLockAction(c, 'done');

    expect(ids(), ['rate:leicht', 'rate:passend', 'rate:schwer', 'undo']);
    expect(l().primary, isNull);
    runLockAction(c, 'rate:passend');
    expect(ids(), ['undo', 'keep', 'accept']);
    runLockAction(c, 'accept');
    expect(ids().last, 'finish');
    runLockAction(c, 'finish');
    expect(c.workout!.phase, Phase.summary);
    expect(ids(), ['undo', 'save']);
    runLockAction(c, 'save');
    expect(c.sessions, hasLength(1));
    expect(lockContent(c), isNull);
  });

  test('höchstens vier Zusatzknöpfe plus Hauptknopf in jedem Schritt', () {
    c.startWorkout('torso');
    void check() => expect(l().buttons.length, lessThanOrEqualTo(4));
    check();
    c.pickExercise('Bankdrücken');
    check();
    c.completeSet();
    check();
  });

  test('Brücke schickt Bild einmal je Übung und nur bei Änderungen', () async {
    final calls = <String>[];
    const ch = MethodChannel('test/lock');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (m) async {
      calls.add(m.method);
      return m.method == 'pendingActions' ? <String>[] : null;
    });
    await LockScreenBridge(c, channel: ch, renderArtwork: (_) async => Uint8List(4)).start();
    calls.clear();
    c.startWorkout('torso');
    await pumpEventQueue();
    c.tick();
    c.tick();
    await pumpEventQueue();
    expect(calls, ['artwork', 'update'], reason: 'Sekundentakt löst kein erneutes Senden aus');
    c.pickExercise('Latzug');
    await pumpEventQueue();
    c.changeReps(1);
    await pumpEventQueue();
    expect(calls.where((m) => m == 'artwork'), hasLength(2));
    c.cancelWorkout();
    await pumpEventQueue();
    expect(calls.last, 'stop');
  });
}
