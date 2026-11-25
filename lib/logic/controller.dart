import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/catalog.dart';
import '../data/demo.dart';
import '../data/models.dart';
import '../data/store.dart';
import 'coach.dart';
import 'workout.dart';

class _Snapshot {
  _Snapshot(this.label, this.workout, this.nextWeights, this.sessionIds);
  final String label;
  final String? workout;
  final Map<String, double?> nextWeights;
  final Set<String> sessionIds;
}

/// Zentrale Steuerung: hält alle Daten, führt jede Aktion des Trainings aus,
/// speichert nach jeder Änderung und kann jeden Trainingsschritt zurücknehmen.
///
/// Die Aktionen sind bewusst kleine, benannte Methoden. Sperrbildschirm und
/// Garmin-Uhr rufen später genau dieselben auf.
class AppController extends ChangeNotifier {
  AppController({required this.store, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final Store store;
  final DateTime Function() _now;
  DateTime get now => _now();

  List<Exercise> exercises = [];
  List<Session> sessions = [];
  Settings settings = Settings();
  ActiveWorkout? workout;
  bool loaded = false;

  final List<_Snapshot> _undo = [];
  Timer? _ticker;
  bool _wasResting = false;

  /// Wird aufgerufen, wenn eine Pause abläuft (Vibration).
  VoidCallback? onRestFinished;

  /// Zeitpunkt, an dem die letzte Pause ablief; für den Hinweis „Pause vorbei“.
  DateTime? restFinishedAt;

  // ---------------------------------------------------------------- Laden

  /// [demo] füllt einen leeren Speicher mit Beispieltrainings (Vorschau).
  Future<void> load({bool demo = false}) async {
    final j = await store.load();
    if (j == null) {
      exercises = defaultExercises();
      if (demo) {
        exercise('Latzug')
          ..machine = '7'
          ..note = 'breiter Griff';
        exercise('Beinpresse')
          ..machine = '12'
          ..note = 'Sitz Stufe 4';
        sessions = demoSessions(exercises, now);
      }
    } else {
      exercises = (j['exercises'] as List).map((e) => Exercise.fromJson(e as Map<String, dynamic>)).toList();
      sessions = (j['sessions'] as List).map((s) => Session.fromJson(s as Map<String, dynamic>)).toList();
      settings = Settings.fromJson((j['settings'] as Map<String, dynamic>?) ?? {});
      final w = j['workout'];
      workout = w == null ? null : ActiveWorkout.fromJson(w as Map<String, dynamic>);
    }
    loaded = true;
    _wasResting = workout?.resting(now) ?? false;
    _startTicker();
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'exercises': exercises.map((e) => e.toJson()).toList(),
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'settings': settings.toJson(),
        'workout': workout?.toJson(),
      };

  Future<void> _persist() => store.save(toJson());

  void _changed() {
    notifyListeners();
    unawaited(_persist());
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  /// Einmal pro Sekunde: Uhren aktualisieren und Pausenende erkennen.
  /// Wird auch vom Sperrbildschirm angestoßen, wenn dort die Pause abläuft.
  void tick() {
    final w = workout;
    if (w == null || w.phase == Phase.summary) return;
    final resting = w.resting(now);
    if (_wasResting && !resting) {
      restFinishedAt = now;
      onRestFinished?.call();
    }
    _wasResting = resting;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- Abfragen

  Exercise exercise(String name) => exercises.firstWhere((e) => e.name == name);
  Exercise? tryExercise(String name) => exercises.where((e) => e.name == name).firstOrNull;
  List<Exercise> get selected => exercises.where((e) => e.selected).toList();

  bool get canUndo => _undo.isNotEmpty;
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;

  List<Suggestion> suggestions({int max = 3}) {
    final w = workout!;
    return suggestNext(
        sessions: sessions, exercises: exercises, dayId: w.day, previous: w.items.lastOrNull?.exercise, done: w.done, max: max);
  }

  WorkoutSummary summary() => summarize(sessions, workout!.day, workout!.items);

  bool get restJustFinished => restFinishedAt != null && now.difference(restFinishedAt!).inSeconds < 5;

  // ---------------------------------------------------------------- Rückgängig

  void _snap(String label) {
    _undo.add(_Snapshot(
      label,
      workout == null ? null : jsonEncode(workout!.toJson()),
      {for (final e in exercises) e.name: e.nextWeight},
      {for (final x in sessions) x.id},
    ));
    if (_undo.length > 60) _undo.removeAt(0);
  }

  void undo() {
    if (_undo.isEmpty) return;
    final s = _undo.removeLast();
    workout = s.workout == null ? null : ActiveWorkout.fromJson(jsonDecode(s.workout!) as Map<String, dynamic>);
    for (final e in exercises) {
      if (s.nextWeights.containsKey(e.name)) e.nextWeight = s.nextWeights[e.name];
    }
    sessions.removeWhere((x) => !s.sessionIds.contains(x.id));
    _wasResting = workout?.resting(now) ?? false;
    _changed();
  }

  // ---------------------------------------------------------------- Training

  void startWorkout(String dayId) {
    _snap('${dayById(dayId).name} gestartet');
    workout = ActiveWorkout(plan: dayById(dayId).planId, day: dayId, startedAt: now, restSec: settings.restSec);
    _changed();
  }

  void cancelWorkout() {
    _snap('Training abgebrochen');
    workout = null;
    _changed();
  }

  void pickExercise(String name) {
    final w = workout!;
    final e = exercise(name);
    final last = lastLog(sessions, name)?.log;
    _snap('$name gewählt');
    w
      ..exercise = name
      ..sets = plannedSets(e, last)
      ..current = 0
      ..phase = Phase.set
      ..setStartedAt = now
      ..restEndsAt = null
      ..machine = e.machine
      ..note = e.note
      ..lastMachine = last?.machine ?? ''
      ..rating = null;
    restFinishedAt = null;
    _changed();
  }

  void changeReps(int delta) {
    final s = workout?.currentSet;
    if (s == null || s.reps + delta < 0) return;
    _snap(delta > 0 ? 'Wiederholung +1' : 'Wiederholung −1');
    s.reps += delta;
    _changed();
  }

  /// Ändert das Gewicht des aktuellen und aller folgenden Sätze.
  void changeWeight(int direction) {
    final w = workout!;
    final s = w.currentSet;
    if (s == null) return;
    final step = exercise(w.exercise!).step;
    final nw = s.weight + direction * step;
    if (nw < 0) return;
    _snap(direction > 0 ? 'Gewicht erhöht' : 'Gewicht gesenkt');
    for (var i = w.current; i < w.sets.length; i++) {
      w.sets[i].weight = nw;
    }
    _changed();
  }

  void completeSet() {
    final w = workout!;
    final s = w.currentSet;
    if (s == null) return;
    _snap('Satz ${w.current + 1} abgehakt');
    s
      ..done = true
      ..durationSec = w.setElapsedSec(now)
      ..finishedAt = now;
    w.current++;
    if (w.current >= w.sets.length) {
      w
        ..phase = Phase.feedback
        ..restEndsAt = null;
    } else {
      w
        ..restEndsAt = now.add(Duration(seconds: w.restSec))
        ..setStartedAt = now;
      _wasResting = true;
    }
    restFinishedAt = null;
    _changed();
  }

  void addSet() {
    final w = workout!;
    final l = w.sets.last;
    _snap('Satz hinzugefügt');
    w.sets.add(SetEntry(reps: l.reps, weight: l.weight));
    w.phase = Phase.set;
    _changed();
  }

  void endExercise() {
    final w = workout!;
    if (!w.sets.any((s) => s.done)) return;
    _snap('Übung beendet');
    w
      ..phase = Phase.feedback
      ..restEndsAt = null;
    _changed();
  }

  /// Pause für dieses Training um ±15 s ändern; eine laufende Pause ebenso.
  void adjustRest(int deltaSec) {
    final w = workout!;
    w.restSec = (w.restSec + deltaSec).clamp(15, 600);
    if (w.resting(now)) {
      final end = w.restEndsAt!.add(Duration(seconds: deltaSec));
      w.restEndsAt = end.isBefore(now) ? now : end;
    }
    _changed();
  }

  void skipRest() {
    final w = workout!;
    if (!w.resting(now)) return;
    _snap('Pause übersprungen');
    w.restEndsAt = now;
    _wasResting = false;
    _changed();
  }

  void setMachine(String machine, String note) {
    workout!
      ..machine = machine.trim()
      ..note = note.trim();
    _changed();
  }

  void saveMachineAsDefault() {
    final w = workout!;
    exercise(w.exercise!)
      ..machine = w.machine
      ..note = w.note;
    _changed();
  }

  void rate(Rating r) {
    final w = workout!;
    final rec = recommend(exercise(w.exercise!), w.sets, r);
    _snap('Rückmeldung „${r.label}“');
    w
      ..rating = r
      ..recommendation = rec.weight
      ..recommendationReason = rec.reason
      ..phase = Phase.recommend;
    _changed();
  }

  /// [accept] = Empfehlung übernehmen, sonst Gewicht so lassen.
  void finishExercise({required bool accept}) {
    final w = workout!;
    final done = w.sets.where((s) => s.done).map((s) => s.copy()).toList();
    final log = ExerciseLog(exercise: w.exercise!, sets: done, machine: w.machine, note: w.note, rating: w.rating);
    _snap(accept ? 'Gewicht übernommen' : 'Gewicht gelassen');
    log.nextWeight = accept ? w.recommendation : log.topSet.weight;
    exercise(w.exercise!).nextWeight = log.nextWeight;
    w
      ..items.add(log)
      ..phase = Phase.next;
    _changed();
  }

  void finishWorkout() {
    final w = workout!;
    if (w.items.isEmpty) return;
    _snap('Training beendet');
    w
      ..phase = Phase.summary
      ..finishedAt = now
      ..restEndsAt = null;
    _changed();
  }

  void saveWorkout() {
    final w = workout!;
    _snap('Training gespeichert');
    sessions.add(Session(
      id: w.startedAt.microsecondsSinceEpoch.toRadixString(36),
      start: w.startedAt,
      durationSec: w.elapsedSec(now),
      plan: w.plan,
      day: w.day,
      items: w.items.map((i) => i.copy()).toList(),
    ));
    workout = null;
    _changed();
  }

  /// Löscht ein gespeichertes Training. Die Gewichtsvorgabe fürs nächste Mal
  /// richtet sich danach wieder nach dem letzten verbliebenen Training.
  void deleteSession(String id) {
    final gone = sessions.where((s) => s.id == id).firstOrNull;
    if (gone == null) return;
    sessions.remove(gone);
    // Zurück würde sonst in ein Training springen, das es nicht mehr gibt.
    _undo.clear();
    final active = workout?.items ?? const <ExerciseLog>[];
    for (final it in gone.items) {
      final e = tryExercise(it.exercise);
      if (e == null) continue;
      final inActive = active.where((a) => a.exercise == e.name).lastOrNull;
      e.nextWeight = inActive?.nextWeight ?? lastLog(sessions, e.name)?.log.nextWeight;
    }
    _changed();
  }

  // ---------------------------------------------------------------- Einstellungen

  void setDefaultRest(int sec) {
    settings.restSec = sec.clamp(15, 600);
    _changed();
  }

  void toggleSelected(String name) {
    final e = exercise(name);
    e.selected = !e.selected;
    _changed();
  }

  void editExercise(String name, {required String machine, required String note}) {
    exercise(name)
      ..machine = machine.trim()
      ..note = note.trim();
    _changed();
  }

  /// Legt eine eigene Übung an. Gibt eine Fehlermeldung zurück oder null.
  String? addCustomExercise({
    required String name,
    required MuscleGroup group,
    required int repMin,
    required int repMax,
    required double startWeight,
    required double step,
    String machine = '',
    String note = '',
    String? pictogram,
  }) {
    final n = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) return 'Bitte einen Namen eingeben.';
    if (exercises.any((e) => e.name.toLowerCase() == n.toLowerCase())) {
      return '„$n“ gibt es schon. Suche danach und füge sie hinzu.';
    }
    if (repMin <= 0 || repMax < repMin) return 'Wiederholungen: „bis“ muss mindestens „von“ sein.';
    if (startWeight < 0 || step <= 0) return 'Gewicht und Steigerung prüfen.';
    exercises.add(Exercise(
      name: n,
      group: group,
      repMin: repMin,
      repMax: repMax,
      step: step,
      startWeight: startWeight,
      selected: true,
      custom: true,
      machine: machine.trim(),
      note: note.trim(),
      pictogram: pictogram,
    ));
    _changed();
    return null;
  }

  /// Gesamtmasse, Dauer usw. über einen Zeitraum, für den Verlauf.
  ({int count, double avgMin, double avgVolume}) stats(Iterable<Session> list) {
    final l = list.toList();
    if (l.isEmpty) return (count: 0, avgMin: 0, avgVolume: 0);
    return (
      count: l.length,
      avgMin: l.fold<int>(0, (a, s) => a + s.durationSec) / l.length / 60,
      avgVolume: l.fold<double>(0, (a, s) => a + s.volume) / l.length,
    );
  }

  int sessionsInLastDays(int days) =>
      sessions.where((s) => now.difference(s.start).inDays < days).length;

  double maxVolume(Iterable<Session> l) => l.map((s) => s.volume).fold(0, math.max);
}
