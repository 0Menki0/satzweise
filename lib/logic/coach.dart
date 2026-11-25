/// Trainingslogik ohne Oberfläche: Vorschläge für die nächste Übung,
/// Vorbelegung, Steigerungsempfehlung und Zusammenfassung.
library;

import 'dart:math' as math;

import '../data/catalog.dart';
import '../data/models.dart';

double estimated1rm(double weight, int reps) => weight * (1 + reps / 30);

double best1rm(List<SetEntry> sets) =>
    sets.map((s) => estimated1rm(s.weight, s.reps)).fold(0, math.max);

/// Letzter Eintrag einer Übung über alle Trainings.
({DateTime date, ExerciseLog log})? lastLog(List<Session> sessions, String exercise) {
  for (var i = sessions.length - 1; i >= 0; i--) {
    for (final it in sessions[i].items) {
      if (it.exercise == exercise) return (date: sessions[i].start, log: it);
    }
  }
  return null;
}

/// Der Tag, der in einem Plan als Nächstes dran ist.
DayType nextDay(List<Session> sessions, String planId) {
  final plan = planById(planId);
  for (var i = sessions.length - 1; i >= 0; i--) {
    if (sessions[i].plan == planId) {
      final idx = plan.days.indexWhere((d) => d.id == sessions[i].day);
      return plan.days[(idx + 1) % plan.days.length];
    }
  }
  return plan.days.first;
}

/// Die übliche Reihenfolge an einem Trainingstag, gelernt aus der mittleren
/// Position jeder Übung. Übungen, die nur einmal vorkamen, zählen nicht.
List<String> usualOrder(List<Session> sessions, String dayId, {Set<String>? only}) {
  final pos = <String, double>{};
  final count = <String, int>{};
  for (final s in sessions.where((s) => s.day == dayId)) {
    for (var i = 0; i < s.items.length; i++) {
      final n = s.items[i].exercise;
      pos[n] = (pos[n] ?? 0) + i;
      count[n] = (count[n] ?? 0) + 1;
    }
  }
  final names = pos.keys.where((n) => count[n]! >= 2 && (only == null || only.contains(n))).toList()
    ..sort((a, b) => (pos[a]! / count[a]!).compareTo(pos[b]! / count[b]!));
  return names;
}

/// Wie oft eine Übung an welchem Trainingstag gemacht wurde.
Map<String, int> dayCounts(List<Session> sessions, String exercise) {
  final c = <String, int>{};
  for (final s in sessions) {
    if (s.items.any((i) => i.exercise == exercise)) c[s.day] = (c[s.day] ?? 0) + 1;
  }
  return c;
}

class Suggestion {
  const Suggestion(this.exercise, this.reason);
  final String exercise;
  final String reason;
}

/// Schlägt die wahrscheinlich nächste Übung vor. Grundlage sind die bisherigen
/// Trainings desselben Tages: welche Übung folgte wie oft auf die letzte.
List<Suggestion> suggestNext({
  required List<Session> sessions,
  required List<Exercise> exercises,
  required String dayId,
  required String? previous,
  required Set<String> done,
  int max = 3,
}) {
  final day = dayById(dayId);
  final selected = {for (final e in exercises.where((e) => e.selected)) e.name: e};
  bool ok(String n) => selected.containsKey(n) && !done.contains(n) && n != previous;

  final from = previous ?? '';
  final counts = <String, int>{};
  var total = 0;
  for (final s in sessions.where((s) => s.day == dayId)) {
    for (var i = 0; i < s.items.length; i++) {
      final before = i == 0 ? '' : s.items[i - 1].exercise;
      if (before == from) {
        counts[s.items[i].exercise] = (counts[s.items[i].exercise] ?? 0) + 1;
        total++;
      }
    }
  }
  final ranked = counts.entries.where((e) => ok(e.key)).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final out = <Suggestion>[
    for (final e in ranked)
      Suggestion(
          e.key,
          previous == null
              ? 'Einstieg in ${e.value} von $total ${day.name}-Trainings'
              : 'folgte ${e.value} von $total Mal auf $previous'),
  ];
  void add(String n, String why) {
    if (out.length < max && ok(n) && !out.any((s) => s.exercise == n)) out.add(Suggestion(n, why));
  }

  for (final n in usualOrder(sessions, dayId)) {
    add(n, 'gehört zu deinem üblichen ${day.name}');
  }
  for (final e in selected.values.where(day.matches)) {
    add(e.name, 'passt zu ${day.name}');
  }
  for (final e in selected.values) {
    add(e.name, 'aus deiner Auswahl');
  }
  return out.take(max).toList();
}

/// Ob eine Übung zu einem Tag passt: nach Muskelgruppe oder weil sie an
/// diesem Tag schon gemacht wurde.
bool fitsDay(List<Session> sessions, Exercise e, String dayId) =>
    dayById(dayId).matches(e) ||
    sessions.any((s) => s.day == dayId && s.items.any((i) => i.exercise == e.name));

class Prefill {
  const Prefill(this.reps, this.weight, {required this.increased});
  final int reps;
  final double weight;
  final bool increased;
}

/// Vorbelegung nach doppelter Progression: Wurden letztes Mal in allen Sätzen
/// die oberen Wiederholungen geschafft, steigt das Gewicht und das Ziel
/// beginnt wieder unten im Wiederholungsbereich.
Prefill prefill(Exercise e, ExerciseLog? last) {
  if (last == null || last.sets.isEmpty) {
    return Prefill(e.repMin, e.nextWeight ?? e.startWeight, increased: false);
  }
  final top = last.topSet;
  final allTop = last.sets.every((s) => s.reps >= e.repMax);
  final w = e.nextWeight ?? (allTop ? top.weight + e.step : top.weight);
  final increased = w > top.weight;
  return Prefill(increased ? e.repMin : math.min(e.repMax, top.reps), w, increased: increased);
}

class Recommendation {
  const Recommendation(this.weight, this.reason);
  final double weight;
  final String reason;
}

String fmtKg(double w) {
  final r = (w * 100).round() / 100;
  final s = r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString();
  return s.replaceAll('.', ',');
}

/// Empfehlung fürs nächste Mal nach der Rückmeldung (doppelte Progression):
///
/// * leicht: alle Sätze oben → zwei Steigerungsstufen; alle im Zielbereich →
///   eine Stufe. Es wären noch Wiederholungen gegangen.
/// * passend: erst steigern, wenn alle Sätze oben im Bereich liegen.
/// * schwer: Gewicht halten; unter dem Zielbereich etwa 10 % runter.
Recommendation recommend(Exercise e, List<SetEntry> sets, Rating rating) {
  final done = sets.where((s) => s.done).toList();
  final w = done.map((s) => s.weight).fold<double>(0, math.max);
  final allTop = done.every((s) => s.reps >= e.repMax);
  final inRange = done.every((s) => s.reps >= e.repMin);
  final step = fmtKg(e.step);
  switch (rating) {
    case Rating.leicht when allTop:
      return Recommendation(w + 2 * e.step,
          'Alle Sätze bei ${e.repMax} Wdh. und es wären noch einige gegangen: gleich zwei Stufen, +${fmtKg(2 * e.step)} kg.');
    case Rating.leicht when inRange:
      return Recommendation(w + e.step, 'Im Zielbereich und noch Luft: +$step kg, dann wieder Richtung ${e.repMax} Wdh. arbeiten.');
    case Rating.leicht:
      return Recommendation(w, 'Noch unter ${e.repMin} Wdh.: Gewicht halten und mehr Wiederholungen schaffen.');
    case Rating.passend when allTop:
      return Recommendation(w + e.step, 'Alle Sätze bei ${e.repMax} Wdh.: Zeit für +$step kg.');
    case Rating.passend:
      return Recommendation(w, 'Gleiches Gewicht. Gesteigert wird, sobald alle Sätze ${e.repMax} Wdh. erreichen.');
    case Rating.schwer when !inRange:
      final down = math.max(e.step, (w * 0.9 / e.step).round() * e.step);
      return Recommendation(down, 'Unter ${e.repMin} Wdh. und am Limit: etwa 10 % runter und sauber neu aufbauen.');
    case Rating.schwer:
      return Recommendation(w, 'Am Limit: Gewicht halten, bis es sich wieder passend anfühlt.');
  }
}

enum Trend { up, same, down, neu }

enum Tone { up, same, down }

class ExerciseComparison {
  ExerciseComparison(this.log, this.previous, this.trend, this.change, this.score);
  final ExerciseLog log;
  final ExerciseLog? previous;
  final Trend trend;
  final String change;
  final double score;
}

class WorkoutSummary {
  WorkoutSummary({
    required this.volume,
    required this.previous,
    required this.volumeChangePct,
    required this.rows,
    required this.tone,
    required this.title,
    required this.text,
    required this.setCount,
  });

  final double volume;
  final Session? previous;
  final int? volumeChangePct;
  final List<ExerciseComparison> rows;
  final Tone tone;
  final String title;
  final String text;
  final int setCount;

  bool get fewerExercises => previous != null && rows.length < previous!.items.length;
}

/// Vergleicht das heutige Training mit dem letzten Mal: je Übung über das
/// geschätzte 1RM, insgesamt über die bewegte Masse am selben Trainingstag.
WorkoutSummary summarize(List<Session> history, String dayId, List<ExerciseLog> items) {
  Session? prev;
  for (var i = history.length - 1; i >= 0; i--) {
    if (history[i].day == dayId) {
      prev = history[i];
      break;
    }
  }
  final volume = items.fold<double>(0, (a, i) => a + i.volume);
  final rows = <ExerciseComparison>[];
  for (final it in items) {
    final last = lastLog(history, it.exercise)?.log;
    if (last == null) {
      rows.add(ExerciseComparison(it, null, Trend.neu, 'neu', 0));
      continue;
    }
    final d = (best1rm(it.sets) - best1rm(last.sets)) / best1rm(last.sets);
    final t = it.topSet, pt = last.topSet;
    final dw = t.weight - pt.weight, dr = t.reps - pt.reps;
    final change = dw != 0
        ? '${dw > 0 ? '+' : ''}${fmtKg(dw)} kg'
        : dr != 0
            ? '${dr > 0 ? '+' : ''}$dr Wdh.'
            : 'gehalten';
    rows.add(ExerciseComparison(
        it, last, d > 0.01 ? Trend.up : (d < -0.01 ? Trend.down : Trend.same), change, d));
  }
  final cmp = rows.where((r) => r.trend != Trend.neu).toList();
  final ups = cmp.where((r) => r.trend == Trend.up).length;
  final downs = cmp.where((r) => r.trend == Trend.down).length;
  final pct = prev == null || prev.volume == 0 ? null : ((volume - prev.volume) / prev.volume * 100).round();

  Tone tone;
  String title, text;
  if (cmp.isEmpty) {
    tone = Tone.same;
    title = 'Erstes Training dieser Art.';
    text = 'Ab jetzt hast du einen Vergleichswert. Beim nächsten Mal siehst du, wo du zulegst.';
  } else if (ups > downs) {
    final best = (cmp.where((r) => r.trend == Trend.up).toList()..sort((a, b) => b.score.compareTo(a.score))).first;
    tone = Tone.up;
    title = 'Stark gesteigert!';
    text = 'Bei $ups von ${cmp.length} Übungen warst du besser als beim letzten Mal, '
        'am meisten bei ${best.log.exercise} (${best.change}). Genau so entsteht Fortschritt.';
  } else if (downs > ups) {
    tone = Tone.down;
    title = 'Heute etwas schwächer.';
    text = 'Bei $downs von ${cmp.length} Übungen lagst du unter dem letzten Mal. Das passiert, '
        'Schlaf, Essen und Stress spielen mit. Wichtig ist, dass du da warst. '
        'Nächstes Mal geht es mit denselben Gewichten weiter.';
  } else {
    tone = Tone.same;
    title = 'Niveau gehalten.';
    text = 'Die meisten Übungen lagen auf dem Stand vom letzten Mal. '
        'Das ist die Basis für die nächste Steigerung, bleib dran.';
  }
  return WorkoutSummary(
    volume: volume,
    previous: prev,
    volumeChangePct: pct,
    rows: rows,
    tone: tone,
    title: title,
    text: text,
    setCount: items.fold(0, (a, i) => a + i.sets.length),
  );
}
