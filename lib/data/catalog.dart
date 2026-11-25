import 'models.dart';

/// Ein Trainingstag innerhalb eines Plans, z. B. „Torso“ im Plan „Torso / Limbs“.
class DayType {
  const DayType({
    required this.id,
    required this.name,
    required this.description,
    required this.planId,
    required this.matches,
  });

  final String id;
  final String name;
  final String description;
  final String planId;

  /// Ob eine Übung grundsätzlich zu diesem Tag passt.
  final bool Function(Exercise e) matches;
}

class TrainingPlan {
  const TrainingPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.days,
    this.usual = false,
  });

  final String id;
  final String name;
  final String description;
  final List<DayType> days;

  /// Wird auf dem Startbildschirm oben als „üblich“ angezeigt.
  final bool usual;
}

bool Function(Exercise) _groups(List<MuscleGroup> gs) => (e) => gs.contains(e.group);

const _push = {
  'Liegestütze', 'Diamant-Liegestütze', 'Pike-Liegestütze', 'Dips am Stuhl',
  'Bankdrücken', 'Schrägbankdrücken Kurzhantel', 'Butterfly Maschine', 'Kabelzug Crossover',
  'Dips mit Gewicht', 'Schulterdrücken', 'Military Press', 'Seitheben', 'Trizepsdrücken',
  'French Press',
};
const _pull = {
  'Klimmzüge', 'Tischrudern', 'Superman',
  'Kreuzheben', 'Latzug', 'Rudern Kurzhantel', 'Rudern Langhantel', 'Klimmzüge mit Gewicht',
  'Rudern Kabel sitzend', 'Face Pulls', 'Reverse Butterfly', 'Bizepscurls', 'Hammercurls',
};

final List<TrainingPlan> plans = [
  TrainingPlan(
    id: 'gk',
    name: 'Ganzkörper',
    description: 'Alle Muskelgruppen in einer Einheit',
    usual: true,
    days: [DayType(id: 'gk', name: 'Ganzkörper', description: 'Alle Muskelgruppen', planId: 'gk', matches: (_) => true)],
  ),
  TrainingPlan(
    id: 'tl',
    name: 'Torso / Limbs',
    description: 'Brust, Rücken, Schultern, Rumpf im Wechsel mit Beinen und Armen',
    usual: true,
    days: [
      DayType(
          id: 'torso',
          name: 'Torso',
          description: 'Brust, Rücken, Schultern, Rumpf',
          planId: 'tl',
          matches: _groups([MuscleGroup.brust, MuscleGroup.ruecken, MuscleGroup.schultern, MuscleGroup.rumpf])),
      DayType(
          id: 'limbs',
          name: 'Limbs',
          description: 'Beine, Arme',
          planId: 'tl',
          matches: _groups([MuscleGroup.beine, MuscleGroup.arme])),
    ],
  ),
  TrainingPlan(
    id: 'ou',
    name: 'Ober- / Unterkörper',
    description: 'Zwei Tage im Wechsel',
    days: [
      DayType(
          id: 'ok',
          name: 'Oberkörper',
          description: 'Brust, Rücken, Schultern, Arme',
          planId: 'ou',
          matches: _groups([MuscleGroup.brust, MuscleGroup.ruecken, MuscleGroup.schultern, MuscleGroup.arme])),
      DayType(
          id: 'uk',
          name: 'Unterkörper',
          description: 'Beine, Rumpf',
          planId: 'ou',
          matches: _groups([MuscleGroup.beine, MuscleGroup.rumpf])),
    ],
  ),
  TrainingPlan(
    id: 'ppl',
    name: 'Push / Pull / Beine',
    description: 'Drei Tage im Wechsel',
    days: [
      DayType(id: 'push', name: 'Push', description: 'Brust, Schultern, Trizeps', planId: 'ppl', matches: (e) => _push.contains(e.name)),
      DayType(id: 'pull', name: 'Pull', description: 'Rücken, Bizeps', planId: 'ppl', matches: (e) => _pull.contains(e.name)),
      DayType(id: 'beine', name: 'Beine', description: 'Beine, Rumpf', planId: 'ppl', matches: _groups([MuscleGroup.beine, MuscleGroup.rumpf])),
    ],
  ),
  TrainingPlan(
    id: 'frei',
    name: 'Freies Training',
    description: 'Ohne Plan, alle Übungen',
    days: [DayType(id: 'frei', name: 'Frei', description: 'Alle Übungen', planId: 'frei', matches: (_) => true)],
  ),
];

final Map<String, DayType> dayTypes = {
  for (final p in plans)
    for (final d in p.days) d.id: d,
};

TrainingPlan planById(String id) => plans.firstWhere((p) => p.id == id);

DayType dayById(String id) =>
    dayTypes[id] ??
    DayType(id: id, name: id, description: '', planId: 'frei', matches: (_) => true);

Exercise _x(String n, MuscleGroup g, int min, int max, double step, double base,
        {bool sel = false, bool home = false, bool bw = false, String? pic}) =>
    Exercise(
        name: n,
        group: g,
        repMin: min,
        repMax: max,
        step: step,
        startWeight: base,
        selected: sel,
        home: home || bw,
        bodyweight: bw,
        pictogram: pic);

/// Vorauswahl an Übungen. Die markierten (sel) sind beim ersten Start in
/// „Meine Übungen“, alle anderen lassen sich in den Einstellungen hinzufügen.
/// Vorauswahl an Übungen. Die markierten (sel) sind beim ersten Start in
/// „Meine Übungen“, alle anderen lassen sich in den Einstellungen hinzufügen.
/// home = auch daheim möglich (Kurzhanteln, Körpergewicht).
List<Exercise> defaultExercises() => [
      _x('Bankdrücken', MuscleGroup.brust, 6, 8, 2.5, 40, sel: true),
      _x('Schrägbankdrücken Kurzhantel', MuscleGroup.brust, 8, 12, 2, 16, home: true),
      _x('Butterfly Maschine', MuscleGroup.brust, 10, 15, 2.5, 30),
      _x('Kabelzug Crossover', MuscleGroup.brust, 12, 15, 2.5, 10),
      _x('Dips mit Gewicht', MuscleGroup.brust, 6, 10, 2.5, 0),
      _x('Liegestütze', MuscleGroup.brust, 8, 20, 2.5, 0, bw: true, sel: true, pic: 'pushup'),
      _x('Kreuzheben', MuscleGroup.ruecken, 4, 6, 5, 60, sel: true),
      _x('Latzug', MuscleGroup.ruecken, 8, 12, 2.5, 40, sel: true),
      _x('Rudern Kurzhantel', MuscleGroup.ruecken, 8, 12, 2, 16, sel: true, home: true),
      _x('Rudern Langhantel', MuscleGroup.ruecken, 6, 10, 2.5, 40),
      _x('Klimmzüge mit Gewicht', MuscleGroup.ruecken, 5, 8, 2.5, 0),
      _x('Rudern Kabel sitzend', MuscleGroup.ruecken, 10, 12, 2.5, 35),
      _x('Klimmzüge', MuscleGroup.ruecken, 3, 10, 2.5, 0, bw: true, sel: true, pic: 'pullup'),
      _x('Tischrudern', MuscleGroup.ruecken, 8, 15, 2.5, 0, bw: true, pic: 'invrow'),
      _x('Superman', MuscleGroup.ruecken, 12, 20, 2.5, 0, bw: true, pic: 'superman'),
      _x('Kniebeuge', MuscleGroup.beine, 5, 8, 2.5, 50, sel: true),
      _x('Beinpresse', MuscleGroup.beine, 10, 15, 5, 80, sel: true),
      _x('Rumänisches Kreuzheben', MuscleGroup.beine, 8, 10, 2.5, 40, sel: true),
      _x('Beinstrecker', MuscleGroup.beine, 10, 15, 2.5, 30),
      _x('Beinbeuger', MuscleGroup.beine, 10, 15, 2.5, 25, sel: true),
      _x('Ausfallschritte Kurzhantel', MuscleGroup.beine, 8, 12, 2, 10, home: true),
      _x('Hip Thrust', MuscleGroup.beine, 8, 12, 5, 60),
      _x('Wadenheben', MuscleGroup.beine, 12, 20, 5, 40, sel: true),
      _x('Kniebeuge ohne Gewicht', MuscleGroup.beine, 15, 25, 2.5, 0, bw: true, sel: true, pic: 'airsquat'),
      _x('Ausfallschritte', MuscleGroup.beine, 10, 16, 2.5, 0, bw: true, sel: true, pic: 'lunge'),
      _x('Bulgarische Split Squats', MuscleGroup.beine, 8, 12, 2.5, 0, bw: true, pic: 'lunge'),
      _x('Glute Bridge', MuscleGroup.beine, 12, 20, 2.5, 0, bw: true, sel: true, pic: 'bridge'),
      _x('Wadenheben einbeinig', MuscleGroup.beine, 12, 20, 2.5, 0, bw: true, pic: 'calf'),
      _x('Schulterdrücken', MuscleGroup.schultern, 6, 10, 2, 12, sel: true, home: true),
      _x('Military Press', MuscleGroup.schultern, 5, 8, 2.5, 30),
      _x('Seitheben', MuscleGroup.schultern, 12, 15, 1, 6, sel: true, home: true),
      _x('Face Pulls', MuscleGroup.schultern, 12, 15, 2.5, 15),
      _x('Reverse Butterfly', MuscleGroup.schultern, 12, 15, 2.5, 20),
      _x('Pike-Liegestütze', MuscleGroup.schultern, 6, 12, 2.5, 0, bw: true, pic: 'pike'),
      _x('Bizepscurls', MuscleGroup.arme, 10, 12, 1, 10, sel: true, home: true),
      _x('Hammercurls', MuscleGroup.arme, 10, 12, 1, 10, sel: true, home: true),
      _x('Trizepsdrücken', MuscleGroup.arme, 10, 15, 2.5, 15, sel: true),
      _x('French Press', MuscleGroup.arme, 8, 12, 2.5, 20, home: true),
      _x('Dips am Stuhl', MuscleGroup.arme, 8, 15, 2.5, 0, bw: true, sel: true, pic: 'dips'),
      _x('Diamant-Liegestütze', MuscleGroup.arme, 6, 15, 2.5, 0, bw: true, pic: 'pushup'),
      _x('Kabel-Crunch', MuscleGroup.rumpf, 12, 15, 2.5, 20, sel: true),
      _x('Pallof Press', MuscleGroup.rumpf, 10, 12, 2.5, 10),
      _x('Bauchmaschine', MuscleGroup.rumpf, 12, 15, 5, 25),
      _x('Crunches', MuscleGroup.rumpf, 15, 25, 2.5, 0, bw: true, sel: true, pic: 'situp'),
      _x('Beinheben liegend', MuscleGroup.rumpf, 10, 20, 2.5, 0, bw: true, pic: 'legraise'),
    ];
