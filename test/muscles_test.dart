import 'package:flutter_test/flutter_test.dart';
import 'package:satzweise/data/models.dart';
import 'package:satzweise/logic/muscles.dart';

ExerciseLog _log(String n, int sets) =>
    ExerciseLog(exercise: n, sets: [for (var i = 0; i < sets; i++) SetEntry(reps: 8, weight: 50, done: true)]);

void main() {
  test('Übungen werden den richtigen Muskeln zugeordnet', () {
    expect(musclesFor('Latzug', MuscleGroup.ruecken).main, [Muscle.lats]);
    expect(musclesFor('Latzug mit gestreckten Armen', null).main, [Muscle.lats]);
    expect(musclesFor('Rumänisches Kreuzheben', MuscleGroup.beine).main, contains(Muscle.hamstrings));
    expect(musclesFor('Reverse Butterfly', MuscleGroup.schultern).main, contains(Muscle.shoulders));
    expect(musclesFor('Butterfly Maschine', MuscleGroup.brust).main, [Muscle.chest]);
    expect(musclesFor('Wadenheben', MuscleGroup.beine).main, [Muscle.calves]);
    expect(musclesFor('Beinheben liegend', MuscleGroup.rumpf).main, [Muscle.abs]);
    expect(musclesFor('Meine Spezialübung', MuscleGroup.arme).main, [Muscle.biceps, Muscle.triceps],
        reason: 'unbekannter Name: nach Muskelgruppe');
  });

  test('Hauptmuskel zählt voll, Hilfsmuskel halb', () {
    final load = muscleLoad([_log('Latzug', 3), _log('Bizepscurls', 2)], (_) => null);
    expect(load[Muscle.lats], 3);
    expect(load[Muscle.biceps], 1.5 + 2);
    expect(loadLevel(0), 0);
    expect(loadLevel(load[Muscle.biceps]!), 2);
    expect(loadLevel(12), 4);
  });
}
