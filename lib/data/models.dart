/// Datenmodell der App. Alles ist als JSON speicherbar, damit ein laufendes
/// Training auch einen Neustart der App übersteht und später mit der Uhr
/// abgeglichen werden kann.
library;

enum MuscleGroup {
  brust('Brust'),
  ruecken('Rücken'),
  beine('Beine'),
  schultern('Schultern'),
  arme('Arme'),
  rumpf('Rumpf');

  const MuscleGroup(this.label);
  final String label;
}

/// Wo trainiert wird.
enum Place {
  studio('Studio'),
  home('Daheim');

  const Place(this.label);
  final String label;
}

enum Rating {
  leicht('Leicht', 'noch 3+ Wdh. drin'),
  passend('Passend', '1–2 Wdh. drin'),
  schwer('Schwer', 'am Limit');

  const Rating(this.label, this.hint);
  final String label;
  final String hint;
}

class Exercise {
  Exercise({
    required this.name,
    required this.group,
    required this.repMin,
    required this.repMax,
    required this.step,
    required this.startWeight,
    this.selected = false,
    this.custom = false,
    this.machine = '',
    this.note = '',
    this.pictogram,
    this.nextWeight,
    this.bodyweight = false,
    this.home = false,
  });

  final String name;
  MuscleGroup group;

  /// Übung mit dem eigenen Körpergewicht; das Gewicht ist Zusatzgewicht
  /// (0 = ohne).
  bool bodyweight;

  /// Auch daheim möglich (im Studio geht jede Übung).
  bool home;

  bool availableAt(Place p) => p == Place.studio || home;
  int repMin;
  int repMax;

  /// Steigerung in kg.
  double step;
  double startWeight;
  bool selected;
  bool custom;

  /// Standard-Gerätenummer, z. B. „12“.
  String machine;

  /// Standard-Notiz, z. B. „Sitz Stufe 4“.
  String note;

  /// Schlüssel des Piktogramms; null = Vorgabe nach Name bzw. Muskelgruppe.
  String? pictogram;

  /// Empfohlenes Gewicht fürs nächste Mal (aus der Rückmeldung).
  double? nextWeight;

  Map<String, dynamic> toJson() => {
        'name': name,
        'group': group.name,
        'repMin': repMin,
        'repMax': repMax,
        'step': step,
        'startWeight': startWeight,
        'selected': selected,
        'custom': custom,
        'machine': machine,
        'note': note,
        if (pictogram != null) 'pictogram': pictogram,
        if (nextWeight != null) 'nextWeight': nextWeight,
        'bodyweight': bodyweight,
        'home': home,
      };

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
        name: j['name'] as String,
        group: MuscleGroup.values.byName(j['group'] as String),
        repMin: j['repMin'] as int,
        repMax: j['repMax'] as int,
        step: (j['step'] as num).toDouble(),
        startWeight: (j['startWeight'] as num).toDouble(),
        selected: j['selected'] as bool? ?? false,
        custom: j['custom'] as bool? ?? false,
        machine: j['machine'] as String? ?? '',
        note: j['note'] as String? ?? '',
        pictogram: j['pictogram'] as String?,
        nextWeight: (j['nextWeight'] as num?)?.toDouble(),
        bodyweight: j['bodyweight'] as bool? ?? false,
        home: j['home'] as bool? ?? false,
      );
}

class SetEntry {
  SetEntry({
    required this.reps,
    required this.weight,
    this.done = false,
    this.durationSec = 0,
    this.finishedAt,
  });

  int reps;
  double weight;
  bool done;
  int durationSec;

  /// Zeitpunkt des Abhakens; dient später dem Abgleich mit der Uhr und der
  /// Zuordnung der Herzfrequenz.
  DateTime? finishedAt;

  double get volume => reps * weight;

  SetEntry copy() => SetEntry(
      reps: reps, weight: weight, done: done, durationSec: durationSec, finishedAt: finishedAt);

  Map<String, dynamic> toJson() => {
        'reps': reps,
        'weight': weight,
        'done': done,
        'durationSec': durationSec,
        if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
      };

  factory SetEntry.fromJson(Map<String, dynamic> j) => SetEntry(
        reps: j['reps'] as int,
        weight: (j['weight'] as num).toDouble(),
        done: j['done'] as bool? ?? true,
        durationSec: j['durationSec'] as int? ?? 0,
        finishedAt: j['finishedAt'] == null ? null : DateTime.parse(j['finishedAt'] as String),
      );
}

class ExerciseLog {
  ExerciseLog({
    required this.exercise,
    required this.sets,
    this.machine = '',
    this.note = '',
    this.rating,
    this.nextWeight,
  });

  final String exercise;
  final List<SetEntry> sets;
  String machine;
  String note;
  Rating? rating;

  /// Gewicht, das nach diesem Training fürs nächste Mal festgelegt wurde.
  double? nextWeight;

  double get volume => sets.fold(0, (a, s) => a + s.volume);

  SetEntry get topSet => sets.reduce(
      (b, s) => s.weight > b.weight || (s.weight == b.weight && s.reps > b.reps) ? s : b);

  ExerciseLog copy() => ExerciseLog(
      exercise: exercise,
      sets: sets.map((s) => s.copy()).toList(),
      machine: machine,
      note: note,
      rating: rating,
      nextWeight: nextWeight);

  Map<String, dynamic> toJson() => {
        'exercise': exercise,
        'sets': sets.map((s) => s.toJson()).toList(),
        'machine': machine,
        'note': note,
        if (rating != null) 'rating': rating!.name,
        if (nextWeight != null) 'nextWeight': nextWeight,
      };

  factory ExerciseLog.fromJson(Map<String, dynamic> j) => ExerciseLog(
        exercise: j['exercise'] as String,
        sets: (j['sets'] as List).map((s) => SetEntry.fromJson(s as Map<String, dynamic>)).toList(),
        machine: j['machine'] as String? ?? '',
        note: j['note'] as String? ?? '',
        rating: j['rating'] == null ? null : Rating.values.byName(j['rating'] as String),
        nextWeight: (j['nextWeight'] as num?)?.toDouble(),
      );
}

class Session {
  Session({
    required this.id,
    required this.start,
    required this.durationSec,
    required this.plan,
    required this.day,
    required this.items,
    this.place = Place.studio,
  });

  final String id;
  final DateTime start;
  final int durationSec;
  final String plan;
  final String day;
  final Place place;
  final List<ExerciseLog> items;

  double get volume => items.fold(0, (a, i) => a + i.volume);
  int get setCount => items.fold(0, (a, i) => a + i.sets.length);

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start.toIso8601String(),
        'durationSec': durationSec,
        'plan': plan,
        'day': day,
        'place': place.name,
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        id: j['id'] as String,
        start: DateTime.parse(j['start'] as String),
        durationSec: j['durationSec'] as int,
        plan: j['plan'] as String,
        day: j['day'] as String,
        place: Place.values.byName(j['place'] as String? ?? 'studio'),
        items: (j['items'] as List)
            .map((i) => ExerciseLog.fromJson(i as Map<String, dynamic>))
            .toList(),
      );
}

class Settings {
  Settings({this.restSec = 90, this.restSound = false});

  /// Standard-Pausenzeit in Sekunden.
  int restSec;

  /// Zusätzlich zur Vibration ein Ton am Ende der Pause.
  bool restSound;

  Map<String, dynamic> toJson() => {'restSec': restSec, 'restSound': restSound};

  factory Settings.fromJson(Map<String, dynamic> j) =>
      Settings(restSec: j['restSec'] as int? ?? 90, restSound: j['restSound'] as bool? ?? false);
}
