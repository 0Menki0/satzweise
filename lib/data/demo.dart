import 'dart:math' as math;

import 'catalog.dart';
import 'models.dart';

/// Beispieldaten für die Vorschau im Browser (Aufruf mit `?demo`): zwölf
/// Wochen Torso/Limbs im Wechsel, dazu gelegentlich Ganzkörper.
List<Session> demoSessions(List<Exercise> exercises, DateTime today) {
  final rnd = math.Random(11);
  final ex = {for (final e in exercises) e.name: e};
  const tpl = {
    'torso': ['Bankdrücken', 'Rudern Kurzhantel', 'Schulterdrücken', 'Latzug', 'Seitheben', 'Kabel-Crunch'],
    'limbs': ['Kniebeuge', 'Rumänisches Kreuzheben', 'Beinpresse', 'Beinbeuger', 'Bizepscurls', 'Trizepsdrücken', 'Wadenheben'],
    'gk': ['Kniebeuge', 'Bankdrücken', 'Kreuzheben', 'Rudern Kurzhantel', 'Schulterdrücken', 'Bizepscurls'],
  };
  final lastMonday = today.subtract(Duration(days: (today.weekday - 1) % 7 + (today.weekday == 1 ? 7 : 0)));
  final dates = <(DateTime, bool)>[];
  for (var w = 11; w >= 0; w--) {
    for (final off in [0, 2, 4]) {
      final d = lastMonday.subtract(Duration(days: 7 * w - off)).add(const Duration(hours: 17, minutes: 30));
      if (!d.isAfter(lastMonday.add(const Duration(hours: 18))) && (w == 0 || rnd.nextDouble() > .12)) {
        dates.add((d, off == 4 && w % 4 == 1));
      }
    }
  }
  final types = List.filled(dates.length, '');
  var alt = 0;
  for (var i = dates.length - 1; i >= 0; i--) {
    types[i] = dates[i].$2 ? 'gk' : (alt++ % 2 == 0 ? 'torso' : 'limbs');
  }
  final weights = <String, double>{};
  final out = <Session>[];
  for (var k = 0; k < dates.length; k++) {
    final order = [...tpl[types[k]]!];
    if (rnd.nextDouble() < .35) {
      final i = 1 + rnd.nextInt(order.length - 2);
      final t = order[i];
      order[i] = order[i + 1];
      order[i + 1] = t;
    }
    if (rnd.nextDouble() < .2) order.removeAt(2 + rnd.nextInt(order.length - 2));
    final items = <ExerciseLog>[];
    for (final n in order) {
      final e = ex[n]!;
      final w = weights[n] ?? e.startWeight + e.step * 4;
      final sets = [
        for (var s = 0; s < 3; s++)
          SetEntry(
              reps: math.min(e.repMax, e.repMin - 1 + rnd.nextInt(e.repMax - e.repMin + 3)),
              weight: w,
              done: true,
              durationSec: 30 + rnd.nextInt(30)),
      ];
      if (sets.every((s) => s.reps >= e.repMax)) weights[n] = w + e.step;
      var machine = e.machine, note = e.note;
      if (n == 'Beinpresse') {
        machine = rnd.nextDouble() < .35 ? '15' : '12';
        note = machine == '15' ? 'zweite Presse hinten links' : 'Sitz Stufe 4';
      }
      items.add(ExerciseLog(exercise: n, sets: sets, machine: machine, note: note));
    }
    out.add(Session(
      id: 'demo$k',
      start: dates[k].$1,
      durationSec: (items.length * 7 + 5 + rnd.nextInt(12)) * 60,
      plan: dayById(types[k]).planId,
      day: types[k],
      items: items,
    ));
  }
  return out;
}
