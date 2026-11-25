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

  List<String> ids() => lockContent(c)!.actions.map((a) => a.id).toList();

  test('ohne Training keine Benachrichtigung', () {
    expect(lockContent(c), isNull);
  });

  test('ganzes Training nur über die Knöpfe des Sperrbildschirms', () {
    c.startWorkout('limbs');
    expect(lockContent(c)!.title, 'Womit startest du?');
    final pick = ids().firstWhere((i) => i.startsWith('pick:'));
    runLockAction(c, pick);

    var l = lockContent(c)!;
    expect(l.title, endsWith('Satz 1/3'));
    expect(l.chronoDown, isFalse, reason: 'Gesamtzeit läuft hoch');
    expect(l.actions.length, lessThanOrEqualTo(3));
    expect(ids(), ['undo', 'repsMinus', 'done']);

    runLockAction(c, 'repsMinus');
    expect(c.workout!.sets.first.reps, 7);
    runLockAction(c, 'undo');
    expect(c.workout!.sets.first.reps, 8);

    runLockAction(c, 'done');
    l = lockContent(c)!;
    expect(l.title, startsWith('Pause'));
    expect(l.chronoDown, isTrue, reason: 'Pause zählt rückwärts');
    expect(l.restEndsAt, t.add(const Duration(seconds: 90)));
    runLockAction(c, 'restPlus');
    expect(lockContent(c)!.restEndsAt, t.add(const Duration(seconds: 105)));
    runLockAction(c, 'skip');
    runLockAction(c, 'done');
    runLockAction(c, 'skip');
    runLockAction(c, 'done');

    expect(ids(), ['rate:leicht', 'rate:passend', 'rate:schwer']);
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
    c.tick();
    c.tick();
    expect(calls, ['update'], reason: 'Sekundentakt löst kein erneutes Senden aus');
    c.cancelWorkout();
    expect(calls.last, 'stop');
  });
}
