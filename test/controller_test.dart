import 'package:flutter_test/flutter_test.dart';
import 'package:satzweise/data/models.dart';
import 'package:satzweise/data/store.dart';
import 'package:satzweise/logic/controller.dart';
import 'package:satzweise/logic/workout.dart';

void main() {
  late DateTime t;
  late MemoryStore store;
  late AppController c;

  Future<void> boot() async {
    c = AppController(store: store, now: () => t);
    await c.load();
  }

  setUp(() async {
    t = DateTime(2026, 11, 25, 17, 0);
    store = MemoryStore();
    await boot();
  });

  tearDown(() => c.dispose());

  void pass(int sec) => t = t.add(Duration(seconds: sec));

  test('kompletter Ablauf: Start, Sätze mit Pause, Rückmeldung, Speichern', () async {
    c.startWorkout('limbs');
    expect(c.workout!.plan, 'tl');
    expect(c.workout!.restSec, 90);

    c.pickExercise('Kniebeuge');
    final w = c.workout!;
    expect(w.phase, Phase.set);
    expect(w.sets.length, 3);
    expect(w.sets.first.weight, 50);

    pass(40);
    expect(w.setElapsedSec(c.now), 40);
    c.completeSet();
    expect(w.sets.first.durationSec, 40);
    expect(w.resting(c.now), isTrue);
    expect(w.setElapsedSec(c.now), 0);

    var buzzed = 0;
    c.onRestFinished = () => buzzed++;
    pass(89);
    c.tick();
    expect(buzzed, 0);
    pass(1);
    c.tick();
    expect(buzzed, 1, reason: 'Pausenende löst genau einmal aus');
    c.tick();
    expect(buzzed, 1);

    pass(30);
    expect(w.setElapsedSec(c.now), 30, reason: 'Satzzeit läuft ab Pausenende');
    c.completeSet();
    c.skipRest();
    c.completeSet();
    expect(w.phase, Phase.feedback);

    c.rate(Rating.passend);
    expect(w.phase, Phase.recommend);
    expect(w.recommendation, 52.5, reason: 'alle Sätze bei 8 Wdh.: +2,5 kg');
    c.finishExercise(accept: true);
    expect(c.exercise('Kniebeuge').nextWeight, 52.5);
    expect(w.phase, Phase.next);

    c.finishWorkout();
    pass(600);
    expect(c.workout!.elapsedSec(c.now), 160, reason: 'Gesamtzeit steht nach dem Beenden still');
    c.saveWorkout();
    expect(c.workout, isNull);
    expect(c.sessions.single.day, 'limbs');
    expect(c.sessions.single.durationSec, 160);
    expect(c.sessions.single.items.single.sets.length, 3);
  });

  test('Zurück nimmt Schritte nacheinander zurück, auch das Speichern', () {
    c.startWorkout('torso');
    c.pickExercise('Bankdrücken');
    c.changeReps(1);
    expect(c.workout!.sets.first.reps, 9);
    expect(c.undoLabel, 'Wiederholung +1');
    c.undo();
    expect(c.workout!.sets.first.reps, 8);

    c.completeSet();
    c.completeSet();
    c.completeSet();
    c.rate(Rating.leicht);
    c.finishExercise(accept: true);
    c.finishWorkout();
    c.saveWorkout();
    expect(c.sessions, hasLength(1));
    c.undo();
    expect(c.sessions, isEmpty);
    expect(c.workout!.phase, Phase.summary);
    c.undo();
    c.undo();
    expect(c.workout!.phase, Phase.recommend);
    expect(c.exercise('Bankdrücken').nextWeight, isNull);
  });

  test('Pausenzeit: Standard aus Einstellungen, im Training ±15 s', () {
    c.setDefaultRest(120);
    c.startWorkout('torso');
    c.adjustRest(-15);
    expect(c.workout!.restSec, 105);
    expect(c.settings.restSec, 120, reason: 'Standard bleibt unverändert');
    c.pickExercise('Bankdrücken');
    c.completeSet();
    expect(c.workout!.restRemaining(c.now), 105);
    c.adjustRest(15);
    expect(c.workout!.restRemaining(c.now), 120);
  });

  test('Gewicht ändern gilt für aktuellen und folgende Sätze', () {
    c.startWorkout('torso');
    c.pickExercise('Bankdrücken');
    c.completeSet();
    c.changeWeight(1);
    expect(c.workout!.sets.map((s) => s.weight), [40, 42.5, 42.5]);
  });

  test('Gerät und Notiz landen im Training und optional als Standard', () {
    c.startWorkout('limbs');
    c.pickExercise('Beinpresse');
    c.setMachine('15', 'hinten links');
    c.completeSet();
    c.endExercise();
    c.rate(Rating.passend);
    c.finishExercise(accept: false);
    expect(c.workout!.items.single.machine, '15');
    expect(c.exercise('Beinpresse').machine, '');
    c.pickExercise('Kniebeuge');
    c.setMachine('2', '');
    c.saveMachineAsDefault();
    expect(c.exercise('Kniebeuge').machine, '2');
  });

  test('eigene Übung anlegen mit Prüfungen', () {
    expect(c.addCustomExercise(name: ' ', group: MuscleGroup.beine, repMin: 8, repMax: 12, startWeight: 20, step: 2.5),
        isNotNull);
    expect(c.addCustomExercise(name: 'kniebeuge', group: MuscleGroup.beine, repMin: 8, repMax: 12, startWeight: 20, step: 2.5),
        contains('gibt es schon'));
    expect(c.addCustomExercise(name: 'Zercher Squat', group: MuscleGroup.beine, repMin: 12, repMax: 8, startWeight: 20, step: 2.5),
        isNotNull);
    expect(
        c.addCustomExercise(
            name: 'Zercher  Squat', group: MuscleGroup.beine, repMin: 6, repMax: 8, startWeight: 40, step: 2.5, machine: 'R1'),
        isNull);
    final e = c.exercise('Zercher Squat');
    expect(e.selected && e.custom, isTrue);
    expect(e.machine, 'R1');
  });

  test('laufendes Training übersteht einen Neustart der App', () async {
    c.startWorkout('limbs');
    c.pickExercise('Kniebeuge');
    c.completeSet();
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    pass(30);
    await boot();
    final w = c.workout!;
    expect(w.exercise, 'Kniebeuge');
    expect(w.current, 1);
    expect(w.restRemaining(c.now), 60);
    expect(w.elapsedSec(c.now), 30);
  });
}
