import '../data/models.dart';

/// Einzelne Muskeln für die Muskelfigur.
enum Muscle {
  chest('Brust'),
  shoulders('Schultern'),
  traps('Nacken'),
  upperback('oberer Rücken'),
  lats('Latissimus'),
  lowerback('unterer Rücken'),
  biceps('Bizeps'),
  triceps('Trizeps'),
  forearms('Unterarme'),
  abs('Bauch'),
  obliques('seitl. Bauch'),
  glutes('Gesäß'),
  quads('Oberschenkel vorn'),
  hamstrings('Beinbeuger'),
  adductors('Adduktoren'),
  calves('Waden');

  const Muscle(this.label);
  final String label;
}

typedef MuscleUse = ({List<Muscle> main, List<Muscle> help});


/// Stichwörter im Übungsnamen → Haupt- und Hilfsmuskeln. Die Reihenfolge
/// zählt: das erste passende Stichwort gewinnt.
final List<(List<String>, MuscleUse)> _rules = [
  (['wade'], (main: [Muscle.calves], help: [])),
  (['beinbeuger', 'leg curl'], (main: [Muscle.hamstrings], help: [Muscle.calves])),
  (['beinstrecker'], (main: [Muscle.quads], help: [])),
  (['hip thrust', 'glute', 'bridge'], (main: [Muscle.glutes], help: [Muscle.hamstrings])),
  (['rumän'], (main: [Muscle.hamstrings, Muscle.glutes], help: [Muscle.lowerback])),
  (['kreuzheben'], (main: [Muscle.glutes, Muscle.hamstrings, Muscle.lowerback], help: [Muscle.traps, Muscle.forearms, Muscle.quads])),
  (['kniebeuge', 'squat', 'beinpresse', 'ausfall'], (main: [Muscle.quads, Muscle.glutes], help: [Muscle.hamstrings, Muscle.adductors])),
  (['adduktor'], (main: [Muscle.adductors], help: [])),
  (['latzug', 'klimmz', 'pullover', 'gestreckten'], (main: [Muscle.lats], help: [Muscle.biceps, Muscle.upperback])),
  (['rudern', 'row'], (main: [Muscle.upperback, Muscle.lats], help: [Muscle.biceps, Muscle.shoulders])),
  (['face pull', 'reverse butterfly', 'reverse fly'], (main: [Muscle.shoulders, Muscle.upperback], help: [Muscle.traps])),
  (['shrug'], (main: [Muscle.traps], help: [])),
  (['superman', 'hyperext', 'rückenstrecker'], (main: [Muscle.lowerback], help: [Muscle.glutes])),
  (['seitheben'], (main: [Muscle.shoulders], help: [Muscle.traps])),
  (['schulterdr', 'military', 'pike', 'overhead'], (main: [Muscle.shoulders], help: [Muscle.triceps, Muscle.traps])),
  (['trizeps', 'french', 'dips am stuhl', 'diamant'], (main: [Muscle.triceps], help: [Muscle.chest])),
  (['curl'], (main: [Muscle.biceps], help: [Muscle.forearms])),
  (['bankdr', 'liegest', 'butterfly', 'crossover', 'dips', 'brust'], (main: [Muscle.chest], help: [Muscle.shoulders, Muscle.triceps])),
  (['pallof', 'seitstütz', 'russian'], (main: [Muscle.obliques], help: [Muscle.abs])),
  (['crunch', 'bauch', 'beinheben', 'sit-up', 'situp', 'plank', 'unterarmstütz'], (main: [Muscle.abs], help: [Muscle.obliques])),
];

const Map<MuscleGroup, MuscleUse> _byGroup = {
  MuscleGroup.brust: (main: [Muscle.chest], help: [Muscle.shoulders, Muscle.triceps]),
  MuscleGroup.ruecken: (main: [Muscle.lats, Muscle.upperback], help: [Muscle.biceps]),
  MuscleGroup.beine: (main: [Muscle.quads, Muscle.glutes], help: [Muscle.hamstrings]),
  MuscleGroup.schultern: (main: [Muscle.shoulders], help: [Muscle.triceps]),
  MuscleGroup.arme: (main: [Muscle.biceps, Muscle.triceps], help: [Muscle.forearms]),
  MuscleGroup.rumpf: (main: [Muscle.abs], help: [Muscle.obliques]),
};

/// Welche Muskeln eine Übung beansprucht: nach Name, sonst nach Muskelgruppe.
MuscleUse musclesFor(String name, MuscleGroup? group) {
  final n = name.toLowerCase();
  for (final (keys, use) in _rules) {
    if (keys.any(n.contains)) return use;
  }
  return _byGroup[group] ?? (main: <Muscle>[], help: <Muscle>[]);
}

/// Beanspruchung je Muskel in Sätzen: Hauptmuskel zählt voll, Hilfsmuskel halb.
Map<Muscle, double> muscleLoad(Iterable<ExerciseLog> items, MuscleGroup? Function(String) groupOf) {
  final out = <Muscle, double>{};
  for (final it in items) {
    final n = it.sets.where((s) => s.done).length;
    if (n == 0) continue;
    final use = musclesFor(it.exercise, groupOf(it.exercise));
    for (final m in use.main) {
      out[m] = (out[m] ?? 0) + n;
    }
    for (final m in use.help) {
      out[m] = (out[m] ?? 0) + n / 2;
    }
  }
  return out;
}

/// Farbstufe 0 (nichts) bis 4 (sehr stark).
int loadLevel(double sets) => sets <= 0
    ? 0
    : sets <= 2
        ? 1
        : sets <= 5
            ? 2
            : sets <= 8
                ? 3
                : 4;

