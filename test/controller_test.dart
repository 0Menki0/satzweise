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
    t = DateTime(2026, 11, 26, 17, 0);
    store = MemoryStore();
    await boot();
  });

  tearDown(() => c.dispose());

  void pass(int sec) => t = t.add(Duration(seconds: sec));

  /// Ein Satz: starten (aus Aufwärmen oder Pause), beenden, eintragen, weiter.
  void oneSet({bool end = false}) {
    c.startSet();
    c.completeSet();
    end ? c.endExercise() : c.continueSets();
  }

  test('neuer Ablauf: Aufwärmen, Satz, Eintragen mit laufender Pause, Pause, Satz', () {
    c.startWorkout('limbs');
    c.pickExercise('Kniebeuge');
    final w = c.workout!;
    expect(w.phase, Phase.warmup);
    expect(w.sets.single.weight, 50, reason: 'erster Satz ist geplant');
    pass(120);
    expect(w.warmupElapsedSec(c.now), 120);

    c.startSet();
    expect(w.phase, Phase.set);
    pass(40);
    expect(w.setElapsedSec(c.now), 40);

    c.completeSet();
    expect(w.phase, Phase.log, reason: 'nach dem Satz wird eingetragen');
    expect(w.sets.first.durationSec, 40);
    expect(w.resting(c.now), isTrue, reason: 'die Pause läuft schon beim Eintragen');
    c.changeReps(2);
    expect(w.sets.first.reps, 7, reason: 'Eintragen ändert den eben beendeten Satz');
    pass(20);
    c.continueSets();
    expect(w.phase, Phase.rest);
    expect(w.sets, hasLength(2));
    expect(w.sets[1].reps, 7, reason: 'nächster Satz vorbelegt mit dem eingetragenen');
    expect(w.restRemaining(c.now), 70);

    var buzzed = 0;
    c.onRestFinished = () => buzzed++;
    pass(70);
    c.tick();
    expect(buzzed, 1);
    expect(w.phase, Phase.set, reason: 'Pause abgelaufen: Satz 2 beginnt von selbst');
    expect(w.setStartedAt, t);
    c.tick();
    expect(buzzed, 1);

    c.completeSet();
    pass(90);
    c.tick();
    expect(w.phase, Phase.set, reason: 'auch ohne Eintragen geht es weiter, mit den vorbelegten Werten');
    expect(w.sets, hasLength(3));
    expect(buzzed, 2);

    c.completeSet();
    c.endExercise();
    expect(w.phase, Phase.feedback);
    expect(w.sets, hasLength(3));

    c.rate(Rating.leicht);
    expect(w.phase, Phase.next, reason: 'nach der Rückmeldung direkt zur nächsten Übung');
    expect(c.exercise('Kniebeuge').nextWeight, 52.5);
    expect(w.recommendationReason, contains('Kniebeuge: nächstes Mal 52,5 kg'));

    c.finishWorkout();
    pass(600);
    final total = c.workout!.elapsedSec(c.now);
    c.saveWorkout();
    expect(c.sessions.single.durationSec, total);
    expect(c.sessions.single.items.single.sets.map((s) => s.reps), [7, 7, 7]);
  });

  test('Pause beenden startet sofort den nächsten Satz', () {
    c.startWorkout('torso');
    c.pickExercise('Bankdrücken');
    oneSet();
    expect(c.workout!.phase, Phase.rest);
    c.skipRest();
    expect(c.workout!.phase, Phase.set);
    expect(c.workout!.restEndsAt, isNull);
  });

  test('Eintragen nach abgelaufener Pause startet den Satz direkt', () {
    c.startWorkout('torso');
    c.pickExercise('Bankdrücken');
    c.startSet();
    c.completeSet();
    pass(30);
    c.adjustRest(-60);
    c.continueSets();
    expect(c.workout!.phase, Phase.set);
  });

  test('Zurück nimmt Schritte nacheinander zurück, auch das Speichern', () {
    c.startWorkout('torso');
    c.pickExercise('Bankdrücken');
    c.startSet();
    c.completeSet();
    final before = c.workout!.sets.first.reps;
    c.changeReps(1);
    expect(c.undoLabel, 'Wiederholung +1');
    c.undo();
    expect(c.workout!.sets.first.reps, before);
    c.undo();
    expect(c.workout!.phase, Phase.set);
    c.undo();
    expect(c.workout!.phase, Phase.warmup);

    oneSet(end: true);
    c.rate(Rating.passend);
    c.finishWorkout();
    c.saveWorkout();
    expect(c.sessions, hasLength(1));
    c.undo();
    expect(c.sessions, isEmpty);
    c.undo();
    c.undo();
    expect(c.workout!.phase, Phase.feedback);
    expect(c.exercise('Bankdrücken').nextWeight, isNull);
  });

  test('Pausenzeit: Standard aus Einstellungen, im Training ±15 s', () {
    c.setDefaultRest(120);
    c.startWorkout('torso');
    c.adjustRest(-15);
    expect(c.workout!.restSec, 105);
    expect(c.settings.restSec, 120);
    c.pickExercise('Bankdrücken');
    c.startSet();
    c.completeSet();
    expect(c.workout!.restRemaining(c.now), 105);
    c.adjustRest(15);
    expect(c.workout!.restRemaining(c.now), 120);
  });

  test('Gewicht beim Eintragen ändern gilt auch für den nächsten Satz', () {
    c.startWorkout('torso');
    c.pickExercise('Bankdrücken');
    c.startSet();
    c.completeSet();
    c.changeWeight(1);
    c.continueSets();
    expect(c.workout!.sets.map((s) => s.weight), [42.5, 42.5]);
  });

  test('Gerät und Notiz landen im Training und optional als Standard', () {
    c.startWorkout('limbs');
    c.pickExercise('Beinpresse');
    c.setMachine('15', 'hinten links');
    oneSet(end: true);
    c.rate(Rating.passend);
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
    expect(
        c.addCustomExercise(name: 'Zercher Squat', group: MuscleGroup.beine, repMin: 12, repMax: 8, startWeight: 20, step: 2.5),
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
    c.startSet();
    c.completeSet();
    c.continueSets();
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    pass(30);
    await boot();
    final w = c.workout!;
    expect(w.exercise, 'Kniebeuge');
    expect(w.phase, Phase.rest);
    expect(w.restRemaining(c.now), 60);
  });

  test('neue Sätze übernehmen die Wiederholungen vom letzten Mal, Satz für Satz', () {
    c.startWorkout('torso');
    c.pickExercise('Bankdrücken');
    for (final delta in [2, -1, -1, 0]) {
      c.startSet();
      c.completeSet();
      c.changeReps(delta);
      c.continueSets();
    }
    c.endExercise();
    c.rate(Rating.passend);
    expect(c.workout!.items.single.sets.map((s) => s.reps), [8, 7, 6, 6]);
    c.finishWorkout();
    c.saveWorkout();

    c.startWorkout('torso');
    c.pickExercise('Bankdrücken');
    final w = c.workout!;
    expect(w.lastReps, [8, 7, 6, 6]);
    expect(w.sets.single.reps, 8);
    c.startSet();
    c.completeSet();
    c.continueSets();
    expect(w.sets.last.reps, 7);
  });

  test('Ton am Pausenende ist eine Einstellung', () {
    expect(c.settings.restSound, isFalse);
    c.setRestSound(true);
    expect(c.toJson()['settings'], {'restSec': 90, 'restSound': true});
  });

  test('Training löschen setzt die Gewichtsvorgabe zurück', () {
    void train(Rating r) {
      c.startWorkout('torso');
      c.pickExercise('Bankdrücken');
      oneSet(end: true);
      c.rate(r);
      c.finishWorkout();
      pass(60);
      c.saveWorkout();
      pass(3600);
    }

    train(Rating.passend);
    expect(c.exercise('Bankdrücken').nextWeight, 40);
    train(Rating.leicht);
    expect(c.exercise('Bankdrücken').nextWeight, 42.5);
    c.deleteSession(c.sessions.last.id);
    expect(c.exercise('Bankdrücken').nextWeight, 40);
    c.deleteSession(c.sessions.single.id);
    expect(c.exercise('Bankdrücken').nextWeight, isNull);
    expect(c.canUndo, isFalse);
  });

  test('Studio und daheim: Ort wird gespeichert, daheim nur passende Übungen', () {
    c.startWorkout('torso', place: Place.home);
    for (final n in c.suggestions(max: 3).map((s) => s.exercise)) {
      expect(c.exercise(n).home, isTrue, reason: '$n muss daheim gehen');
    }
    c.pickExercise('Liegestütze');
    oneSet(end: true);
    c.rate(Rating.passend);
    c.finishWorkout();
    c.saveWorkout();
    expect(c.sessions.single.place, Place.home);
  });

  test('Körpergewicht: kein Zusatzgewicht von selbst', () {
    c.startWorkout('torso', place: Place.home);
    c.pickExercise('Liegestütze');
    c.startSet();
    c.completeSet();
    for (var i = 0; i < 12; i++) {
      c.changeReps(1);
    }
    c.endExercise();
    c.rate(Rating.leicht);
    expect(c.exercise('Liegestütze').nextWeight, 0);
    expect(c.workout!.recommendationReason, contains('Zusatzgewicht'));
  });

  test('Gewicht von Hand eintragen, mit Zurück', () {
    c.startWorkout('torso');
    c.pickExercise('Bankdrücken');
    c.setWeight(43.75);
    expect(c.workout!.sets.single.weight, 43.75);
    c.undo();
    expect(c.workout!.sets.single.weight, 40);
    c.setWeight(-5);
    expect(c.workout!.sets.single.weight, 40);
  });

  test('gespeicherte Daten älterer Versionen bekommen die neuen Übungen', () async {
    final old = c.toJson();
    old['exercises'] = [
      for (final e in (old['exercises'] as List).cast<Map<String, dynamic>>())
        if (e['name'] != 'Liegestütze' && e['name'] != 'Crunches') {...e}..remove('home')..remove('bodyweight'),
    ];
    final c2 = AppController(store: MemoryStore(old), now: () => t);
    await c2.load();
    expect(c2.tryExercise('Liegestütze')?.bodyweight, isTrue);
    expect(c2.exercise('Rudern Kurzhantel').home, isTrue);
    c2.dispose();
  });
}
