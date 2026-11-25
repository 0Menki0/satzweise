import 'package:flutter_test/flutter_test.dart';
import 'package:satzweise/data/catalog.dart';
import 'package:satzweise/data/models.dart';
import 'package:satzweise/logic/coach.dart';
import 'package:satzweise/logic/workout.dart';

ExerciseLog log(String n, List<(int, double)> sets, {String machine = ''}) => ExerciseLog(
    exercise: n, machine: machine, sets: [for (final s in sets) SetEntry(reps: s.$1, weight: s.$2, done: true)]);

Session session(String day, DateTime d, List<ExerciseLog> items) => Session(
    id: d.toIso8601String(), start: d, durationSec: 3000, plan: dayById(day).planId, day: day, items: items);

void main() {
  final ex = defaultExercises();
  Exercise e(String n) => ex.firstWhere((x) => x.name == n);
  final d0 = DateTime(2026, 11, 2);

  group('Vorbelegung (doppelte Progression)', () {
    test('ohne Verlauf: Startgewicht und untere Wiederholungen', () {
      final p = prefill(e('Bankdrücken'), null);
      expect(p.weight, 40);
      expect(p.reps, 6);
      expect(p.increased, isFalse);
    });

    test('alle Sätze oben geschafft: Gewicht steigt, Ziel beginnt unten', () {
      final p = prefill(e('Bankdrücken'), log('Bankdrücken', [(8, 60), (8, 60), (8, 60)]));
      expect(p.weight, 62.5);
      expect(p.reps, 6);
      expect(p.increased, isTrue);
    });

    test('nicht alle oben: gleiches Gewicht, Wiederholungen vom besten Satz', () {
      final p = prefill(e('Bankdrücken'), log('Bankdrücken', [(8, 60), (7, 60), (6, 60)]));
      expect(p.weight, 60);
      expect(p.reps, 8);
    });
  });

  group('Empfehlung nach Rückmeldung (Bankdrücken 6–8 Wdh.)', () {
    List<SetEntry> sets(List<int> reps) => [for (final r in reps) SetEntry(reps: r, weight: 60, done: true)];
    double rec(List<int> reps, Rating r) => recommend(e('Bankdrücken'), sets(reps), r).weight;

    test('leicht und passend unterscheiden sich', () {
      expect(rec([7, 6, 6], Rating.leicht), 62.5, reason: 'im Bereich und Luft: eine Stufe');
      expect(rec([7, 6, 6], Rating.passend), 60, reason: 'passend: erst wenn alle oben');
      expect(rec([8, 8, 8], Rating.leicht), 65, reason: 'oben und leicht: zwei Stufen');
      expect(rec([8, 8, 8], Rating.passend), 62.5);
    });
    test('unter dem Bereich: leicht hält, schwer senkt', () {
      expect(rec([6, 5, 5], Rating.leicht), 60);
      expect(rec([5, 4, 4], Rating.schwer), 55);
    });
    test('schwer im Bereich: halten', () {
      expect(rec([8, 8, 8], Rating.schwer), 60);
    });
  });

  test('Vorbelegung übernimmt die Wiederholungen je Satz vom letzten Mal', () {
    final s = plannedSets(e('Bankdrücken'), log('Bankdrücken', [(8, 60), (7, 60), (6, 60)]));
    expect(s.map((x) => x.reps), [8, 7, 6]);
    expect(s.map((x) => x.weight), [60, 60, 60]);
  });

  group('Nächste Übung und gelernte Abläufe', () {
    final history = [
      for (var i = 0; i < 4; i++)
        session('limbs', d0.add(Duration(days: i * 7)), [
          log('Kniebeuge', [(8, 80)]),
          log(i == 3 ? 'Beinpresse' : 'Rumänisches Kreuzheben', [(10, 60)]),
          log(i == 3 ? 'Rumänisches Kreuzheben' : 'Beinpresse', [(12, 100)]),
        ]),
      session('torso', d0.add(const Duration(days: 2)), [log('Bankdrücken', [(8, 60)])]),
    ];

    test('Einstieg kommt aus Trainings desselben Tages', () {
      final s = suggestNext(sessions: history, exercises: ex, dayId: 'limbs', previous: null, done: {});
      expect(s.first.exercise, 'Kniebeuge');
      expect(s.first.reason, 'Einstieg in 4 von 4 Limbs-Trainings');
    });

    test('Nachfolger nach Häufigkeit', () {
      final s = suggestNext(
          sessions: history, exercises: ex, dayId: 'limbs', previous: 'Kniebeuge', done: {'Kniebeuge'});
      expect(s[0].exercise, 'Rumänisches Kreuzheben');
      expect(s[0].reason, 'folgte 3 von 4 Mal auf Kniebeuge');
      expect(s[1].exercise, 'Beinpresse');
    });

    test('erledigte und nicht ausgewählte Übungen werden nicht vorgeschlagen', () {
      final s = suggestNext(
          sessions: history, exercises: ex, dayId: 'limbs', previous: 'Kniebeuge', done: {'Kniebeuge', 'Beinpresse'});
      expect(s.map((x) => x.exercise), isNot(contains('Beinpresse')));
      expect(s.map((x) => x.exercise), isNot(contains('Hip Thrust')));
    });

    test('übliche Reihenfolge je Trainingstag', () {
      expect(usualOrder(history, 'limbs'), ['Kniebeuge', 'Rumänisches Kreuzheben', 'Beinpresse']);
      expect(usualOrder(history, 'torso'), isEmpty);
    });

    test('nächster Split-Tag wechselt ab', () {
      expect(nextDay(history, 'tl').id, 'limbs');
      expect(nextDay([], 'tl').id, 'torso');
      expect(nextDay(history, 'ppl').id, 'push');
    });

    test('Übung wird den Tagen zugeordnet, an denen sie vorkam', () {
      expect(dayCounts(history, 'Kniebeuge'), {'limbs': 4});
    });
  });

  group('Zusammenfassung', () {
    final history = [
      session('limbs', d0, [log('Kniebeuge', [(8, 80), (8, 80)]), log('Beinpresse', [(12, 100)])]),
    ];

    test('gesteigert', () {
      final s = summarize(history, 'limbs', [log('Kniebeuge', [(8, 82.5), (8, 82.5)]), log('Beinpresse', [(12, 100)])]);
      expect(s.tone, Tone.up);
      expect(s.rows.first.trend, Trend.up);
      expect(s.rows.first.change, '+2,5 kg');
      expect(s.text, contains('Kniebeuge'));
    });

    test('gehalten', () {
      final s = summarize(history, 'limbs', [log('Kniebeuge', [(8, 80), (8, 80)])]);
      expect(s.tone, Tone.same);
      expect(s.fewerExercises, isTrue);
    });

    test('schwächer', () {
      final s = summarize(history, 'limbs', [log('Kniebeuge', [(6, 80), (5, 80)])]);
      expect(s.tone, Tone.down);
      expect(s.title, 'Heute etwas schwächer.');
    });

    test('erstes Training dieser Art', () {
      final s = summarize([], 'torso', [log('Bankdrücken', [(8, 60)])]);
      expect(s.rows.single.trend, Trend.neu);
      expect(s.volumeChangePct, isNull);
    });
  });

  test('Gewicht wird deutsch formatiert', () {
    expect(fmtKg(62.5), '62,5');
    expect(fmtKg(60), '60');
  });
}
