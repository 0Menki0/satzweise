import '../data/models.dart';
import 'coach.dart';

/// Schritte einer Übung: Aufwärmen → Satz → Satz eintragen (Pause läuft
/// schon) → Pause → Satz … → Rückmeldung → nächste Übung.
enum Phase { warmup, set, log, rest, feedback, next, summary }

/// Zustand eines laufenden Trainings. Zeiten werden als Zeitpunkte gespeichert,
/// nicht als Zähler: So stimmen Gesamtzeit, Satzzeit und Pause auch dann, wenn
/// die App im Hintergrund war oder neu gestartet wurde.
class ActiveWorkout {
  ActiveWorkout({
    required this.plan,
    required this.day,
    required this.startedAt,
    required this.restSec,
    this.place = Place.studio,
    this.phase = Phase.next,
    this.exercise,
    List<SetEntry>? sets,
    this.current = 0,
    this.setStartedAt,
    this.warmupStartedAt,
    this.restEndsAt,
    this.finishedAt,
    this.recommendation,
    this.recommendationReason,
    List<ExerciseLog>? items,
    this.machine = '',
    this.note = '',
    this.lastMachine = '',
    this.rating,
    List<int>? lastReps,
  })  : sets = sets ?? [],
        items = items ?? [],
        lastReps = lastReps ?? [];

  final String plan;
  final String day;
  final Place place;
  final DateTime startedAt;

  /// Pausenzeit für dieses Training (Standard aus den Einstellungen, im
  /// Training um ±15 s änderbar).
  int restSec;
  Phase phase;
  String? exercise;
  List<SetEntry> sets;
  int current;
  DateTime? setStartedAt;
  DateTime? warmupStartedAt;
  DateTime? restEndsAt;
  DateTime? finishedAt;
  double? recommendation;
  String? recommendationReason;
  final List<ExerciseLog> items;
  String machine;
  String note;
  String lastMachine;
  Rating? rating;

  /// Wiederholungen je Satz vom letzten Mal (Vorlage für neue Sätze).
  List<int> lastReps;

  /// Erledigte Sätze der laufenden Übung.
  List<SetEntry> get doneSets => sets.where((s) => s.done).toList();

  Set<String> get done => {for (final i in items) i.exercise};
  SetEntry? get currentSet => current < sets.length ? sets[current] : null;

  int elapsedSec(DateTime now) => (finishedAt ?? now).difference(startedAt).inSeconds;

  int restRemaining(DateTime now) {
    if (restEndsAt == null) return 0;
    final r = restEndsAt!.difference(now).inMilliseconds;
    return r <= 0 ? 0 : (r / 1000).ceil();
  }

  /// Pause läuft: beim Eintragen des Satzes und in der Pause selbst.
  bool resting(DateTime now) => (phase == Phase.log || phase == Phase.rest) && restRemaining(now) > 0;

  int setElapsedSec(DateTime now) {
    if (phase != Phase.set || setStartedAt == null) return 0;
    final s = now.difference(setStartedAt!).inSeconds;
    return s < 0 ? 0 : s;
  }

  int warmupElapsedSec(DateTime now) =>
      warmupStartedAt == null ? 0 : now.difference(warmupStartedAt!).inSeconds.clamp(0, 1 << 30);

  Map<String, dynamic> toJson() => {
        'plan': plan,
        'day': day,
        'place': place.name,
        'startedAt': startedAt.toIso8601String(),
        'restSec': restSec,
        'phase': phase.name,
        'exercise': exercise,
        'sets': sets.map((s) => s.toJson()).toList(),
        'current': current,
        'setStartedAt': setStartedAt?.toIso8601String(),
        'warmupStartedAt': warmupStartedAt?.toIso8601String(),
        'restEndsAt': restEndsAt?.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'recommendation': recommendation,
        'recommendationReason': recommendationReason,
        'items': items.map((i) => i.toJson()).toList(),
        'machine': machine,
        'note': note,
        'lastMachine': lastMachine,
        'rating': rating?.name,
        'lastReps': lastReps,
      };

  static DateTime? _d(Object? v) => v == null ? null : DateTime.parse(v as String);

  factory ActiveWorkout.fromJson(Map<String, dynamic> j) => ActiveWorkout(
        plan: j['plan'] as String,
        day: j['day'] as String,
        place: Place.values.byName(j['place'] as String? ?? 'studio'),
        startedAt: DateTime.parse(j['startedAt'] as String),
        restSec: j['restSec'] as int,
        phase: Phase.values.asNameMap()[j['phase']] ?? Phase.next,
        exercise: j['exercise'] as String?,
        sets: (j['sets'] as List).map((s) => SetEntry.fromJson(s as Map<String, dynamic>)).toList(),
        current: j['current'] as int,
        setStartedAt: _d(j['setStartedAt']),
        warmupStartedAt: _d(j['warmupStartedAt']),
        restEndsAt: _d(j['restEndsAt']),
        finishedAt: _d(j['finishedAt']),
        recommendation: (j['recommendation'] as num?)?.toDouble(),
        recommendationReason: j['recommendationReason'] as String?,
        items: (j['items'] as List).map((i) => ExerciseLog.fromJson(i as Map<String, dynamic>)).toList(),
        machine: j['machine'] as String? ?? '',
        note: j['note'] as String? ?? '',
        lastMachine: j['lastMachine'] as String? ?? '',
        rating: j['rating'] == null ? null : Rating.values.byName(j['rating'] as String),
        lastReps: [for (final r in (j['lastReps'] as List?) ?? const []) r as int],
      );

  ActiveWorkout clone() => ActiveWorkout.fromJson(toJson());
}

/// Hilfsfunktion für die Anzeige von Zeiten.
String clock(int sec) {
  final h = sec ~/ 3600, m = (sec % 3600) ~/ 60, s = sec % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// Wiederholungen je Satz vom letzten Mal, als Vorlage für die Vorbelegung.
/// Leer, wenn es kein letztes Mal gibt oder das Gewicht gestiegen ist: dann
/// beginnt jeder Satz unten im Wiederholungsbereich.
List<int> repPlan(Exercise e, ExerciseLog? last) {
  final p = prefill(e, last);
  if (last == null || p.increased) return const [];
  return [for (final s in last.sets) e.bodyweight ? s.reps : s.reps.clamp(0, e.repMax)];
}

/// Erster Satz einer neu gewählten Übung.
SetEntry firstSet(Exercise e, ExerciseLog? last) {
  final p = prefill(e, last);
  final plan = repPlan(e, last);
  return SetEntry(reps: plan.isEmpty ? p.reps : plan.first, weight: p.weight);
}

/// Nächster Satz: Gewicht wie der eben beendete, Wiederholungen wie im
/// gleichen Satz beim letzten Mal (gibt es den nicht, wie eben).
SetEntry nextSet(List<int> plan, int index, SetEntry previous) =>
    SetEntry(reps: index < plan.length ? plan[index] : previous.reps, weight: previous.weight);
