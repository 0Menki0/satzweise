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

  /// Wird aufgerufen, wenn eine Pause abläuft (Vibration).
  VoidCallback? onRestFinished;

  /// Wie das letzte Training endete ("saved" oder "cancelled"); die Uhr
  /// speichert oder verwirft danach ihre Aufzeichnung.
  String? lastEnd;

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
      _mergeNewDefaults(j['exercises'] as List);
      sessions = (j['sessions'] as List).map((s) => Session.fromJson(s as Map<String, dynamic>)).toList();
      settings = Settings.fromJson((j['settings'] as Map<String, dynamic>?) ?? {});
      final w = j['workout'];
      workout = w == null ? null : ActiveWorkout.fromJson(w as Map<String, dynamic>);
    }
    loaded = true;
    _startTicker();
    notifyListeners();
  }

  /// Übungen, die in einer neueren App-Version dazugekommen sind, in den
  /// gespeicherten Katalog übernehmen; bei älteren Einträgen fehlt noch, ob
  /// sie daheim gehen.
  void _mergeNewDefaults(List<dynamic> raw) {
    final hadHomeFlag = raw.isNotEmpty && (raw.first as Map).containsKey('home');
    for (final d in defaultExercises()) {
      final e = tryExercise(d.name);
      if (e == null) {
        exercises.add(d);
      } else if (!hadHomeFlag) {
        e
          ..home = d.home
          ..bodyweight = d.bodyweight;
      }
    }
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
    // Pause abgelaufen: der nächste Satz beginnt von selbst, auch wenn der
    // letzte Satz noch nicht eingetragen wurde (dann gelten die vorbelegten
    // Werte).
    if ((w.phase == Phase.log || w.phase == Phase.rest) && w.restEndsAt != null && !now.isBefore(w.restEndsAt!)) {
      final at = w.restEndsAt!;
      if (w.phase == Phase.log) _planNext(w);
      _beginSet(w, at);
      restFinishedAt = now;
      onRestFinished?.call();
      _changed();
      return;
    }
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
        sessions: sessions,
        exercises: exercises,
        dayId: w.day,
        place: w.place,
        previous: w.items.lastOrNull?.exercise,
        done: w.done,
        max: max);
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
    _changed();
  }

  // ---------------------------------------------------------------- Training

  void startWorkout(String dayId, {Place place = Place.studio}) {
    _snap('${dayById(dayId).name} ${place.label.toLowerCase()} gestartet');
    lastEnd = null;
    workout = ActiveWorkout(
        plan: dayById(dayId).planId, day: dayId, place: place, startedAt: now, restSec: settings.restSec);
    _changed();
  }

  void cancelWorkout() {
    _snap('Training abgebrochen');
    workout = null;
    lastEnd = 'cancelled';
    _changed();
  }

  /// Übung gewählt: Aufwärmen beginnt, der erste Satz ist geplant.
  void pickExercise(String name) {
    final w = workout!;
    final e = exercise(name);
    final last = lastLog(sessions, name)?.log;
    _snap('$name gewählt');
    w
      ..exercise = name
      ..sets = [firstSet(e, last)]
      ..lastReps = repPlan(e, last)
      ..current = 0
      ..phase = Phase.warmup
      ..warmupStartedAt = now
      ..setStartedAt = null
      ..restEndsAt = null
      ..machine = e.machine
      ..note = e.note
      ..lastMachine = last?.machine ?? ''
      ..rating = null;
    restFinishedAt = null;
    _changed();
  }

  /// Satz beginnt: nach dem Aufwärmen oder vorzeitig aus der Pause.
  void startSet() {
    final w = workout!;
    if (w.phase != Phase.warmup && w.phase != Phase.rest) return;
    _snap(w.phase == Phase.warmup ? 'Satz gestartet' : 'Pause beendet');
    _beginSet(w, now);
    _changed();
  }

  void _beginSet(ActiveWorkout w, DateTime at) {
    w
      ..phase = Phase.set
      ..setStartedAt = at
      ..restEndsAt = null;
  }

  /// Wiederholungen ändern: im Plan vor dem Satz oder beim Eintragen danach.
  void changeReps(int delta) {
    final s = workout?.currentSet;
    if (s == null || s.reps + delta < 0) return;
    _snap(delta > 0 ? 'Wiederholung +1' : 'Wiederholung −1');
    s.reps += delta;
    _changed();
  }

  /// Gewicht ändern; folgende Sätze übernehmen es.
  void changeWeight(int direction) {
    final w = workout!;
    final s = w.currentSet;
    if (s == null) return;
    final step = exercise(w.exercise!).step;
    final nw = s.weight + direction * step;
    if (nw < 0) return;
    _snap(direction > 0 ? 'Gewicht erhöht' : 'Gewicht gesenkt');
    s.weight = nw;
    _changed();
  }

  /// Gewicht von Hand eintragen (nur in der App, nicht auf dem Sperrbildschirm).
  void setWeight(double kg) {
    final s = workout?.currentSet;
    if (s == null || kg < 0 || kg > 1000) return;
    final rounded = (kg * 100).round() / 100;
    if (rounded == s.weight) return;
    _snap('Gewicht auf ${fmtKg(rounded)} kg gesetzt');
    s.weight = rounded;
    _changed();
  }

  /// Satz beenden: die Pause beginnt sofort, Wiederholungen und Gewicht
  /// werden jetzt eingetragen (vorbelegt mit dem Plan).
  void completeSet() {
    final w = workout!;
    final s = w.currentSet;
    if (s == null || w.phase != Phase.set) return;
    _snap('Satz ${w.current + 1} beendet');
    s
      ..done = true
      ..durationSec = w.setElapsedSec(now)
      ..finishedAt = now;
    w
      ..phase = Phase.log
      ..restEndsAt = now.add(Duration(seconds: w.restSec));
    restFinishedAt = null;
    _changed();
  }

  /// Nach dem Eintragen: weiter mit einem neuen Satz (Pause läuft weiter).
  void continueSets() {
    final w = workout!;
    if (w.phase != Phase.log) return;
    _snap('Satz ${w.current + 1} eingetragen');
    _planNext(w);
    w.phase = w.resting(now) ? Phase.rest : Phase.set;
    if (w.phase == Phase.set) _beginSet(w, now);
    _changed();
  }

  void _planNext(ActiveWorkout w) {
    w.sets.add(nextSet(w.lastReps, w.current + 1, w.sets[w.current]));
    w.current++;
  }

  void endExercise() {
    final w = workout!;
    if (!w.sets.any((s) => s.done)) return;
    _snap('Übung beendet');
    w.sets.removeWhere((s) => !s.done);
    w.current = w.sets.length;
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

  /// „Pause beenden“.
  void skipRest() => startSet();

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

  /// Rückmeldung nach der Übung: legt das Gewicht fürs nächste Mal fest und
  /// geht zurück zur Übungswahl.
  void rate(Rating r) {
    final w = workout!;
    if (w.phase != Phase.feedback) return;
    final rec = recommend(exercise(w.exercise!), w.sets, r);
    final done = w.sets.where((s) => s.done).map((s) => s.copy()).toList();
    final log = ExerciseLog(exercise: w.exercise!, sets: done, machine: w.machine, note: w.note, rating: r)
      ..nextWeight = rec.weight;
    _snap('Rückmeldung „${r.label}“');
    exercise(w.exercise!).nextWeight = rec.weight;
    w
      ..rating = r
      ..recommendation = rec.weight
      ..recommendationReason = '${w.exercise}: nächstes Mal ${weightText(exercise(w.exercise!), rec.weight)}. ${rec.reason}'
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
      place: w.place,
      items: w.items.map((i) => i.copy()).toList(),
    ));
    workout = null;
    lastEnd = 'saved';
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

  void setRestSound(bool on) {
    settings.restSound = on;
    _changed();
  }

  void toggleSelected(String name) {
    final e = exercise(name);
    e.selected = !e.selected;
    _changed();
  }

  void toggleHome(String name) {
    final e = exercise(name);
    e.home = !e.home;
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
    bool home = false,
    bool bodyweight = false,
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
      home: home || bodyweight,
      bodyweight: bodyweight,
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
