import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/catalog.dart';
import '../data/models.dart';
import '../logic/coach.dart';
import '../logic/controller.dart';
import '../logic/workout.dart';
import '../ui/widgets.dart';

/// Ein Knopf auf dem Sperrbildschirm.
class LockAction {
  const LockAction(this.id, this.label);
  final String id;
  final String label;
  Map<String, String> toMap() => {'id': id, 'label': label};
}

/// Inhalt der Trainings-Benachrichtigung. Die Uhr läuft auf dem Gerät selbst
/// (Chronometer), deshalb muss die App nicht jede Sekunde aktualisieren.
class LockContent {
  const LockContent({
    required this.title,
    required this.text,
    required this.subText,
    required this.chronoBase,
    required this.chronoDown,
    required this.restEndsAt,
    required this.actions,
  });

  final String title, text, subText;
  final DateTime chronoBase;
  final bool chronoDown;
  final DateTime? restEndsAt;
  final List<LockAction> actions;

  Map<String, Object?> toMap() => {
        'title': title,
        'text': text,
        'subText': subText,
        'chronoBase': chronoBase.millisecondsSinceEpoch,
        'chronoDown': chronoDown,
        'restEndsAt': restEndsAt?.millisecondsSinceEpoch ?? 0,
        'actions': [for (final a in actions) a.toMap()],
      };
}

const _undo = LockAction('undo', 'Zurück');

/// Baut den Inhalt aus dem Trainingsstand. Android zeigt höchstens drei Knöpfe.
LockContent? lockContent(AppController c) {
  final w = c.workout;
  if (w == null) return null;
  final now = c.now, day = dayById(w.day).name;
  const total = 'Gesamtzeit';
  LockContent up(String title, String text, List<LockAction> a) => LockContent(
      title: title, text: text, subText: '$day · $total', chronoBase: w.startedAt, chronoDown: false, restEndsAt: null, actions: a);

  switch (w.phase) {
    case Phase.set:
      final s = w.currentSet;
      if (s == null) return up('${w.exercise}: alle Sätze fertig', '', [_undo, const LockAction('end', 'Übung beenden')]);
      final setText = '${s.reps} × ${fmtKg(s.weight)} kg${w.machine.isEmpty ? '' : ' · Gerät ${w.machine}'}';
      if (w.resting(now)) {
        return LockContent(
          title: 'Pause · danach Satz ${w.current + 1}/${w.sets.length}',
          text: '${w.exercise}: $setText',
          subText: day,
          chronoBase: w.restEndsAt!,
          chronoDown: true,
          restEndsAt: w.restEndsAt,
          actions: const [_undo, LockAction('restPlus', '+15 s'), LockAction('skip', 'Weiter')],
        );
      }
      return up('${w.exercise} · Satz ${w.current + 1}/${w.sets.length}', setText,
          const [_undo, LockAction('repsMinus', '− Wdh.'), LockAction('done', 'Satz fertig')]);
    case Phase.feedback:
      return up('${w.exercise}: wie war\'s?', 'Rückmeldung für das nächste Gewicht', [
        for (final r in Rating.values) LockAction('rate:${r.name}', r.label),
      ]);
    case Phase.recommend:
      return up('Nächstes Mal ${w.exercise}: ${fmtKg(w.recommendation!)} kg', w.recommendationReason ?? '',
          const [_undo, LockAction('keep', 'Gleich lassen'), LockAction('accept', 'Übernehmen')]);
    case Phase.next:
      final sg = c.suggestions(max: 2);
      final picks = [for (final s in sg) LockAction('pick:${s.exercise}', s.exercise)];
      return up(w.items.isEmpty ? 'Womit startest du?' : 'Als Nächstes?', sg.map((s) => '${s.exercise}: ${s.reason}').join('\n'),
          w.items.isEmpty ? [_undo, ...picks] : [...picks.take(2), const LockAction('finish', 'Beenden')]);
    case Phase.summary:
      final m = c.summary();
      return LockContent(
        title: '$day fertig: ${m.title}',
        text: '${clock(w.elapsedSec(now))} · ${kg(m.volume)} · ${m.setCount} Sätze',
        subText: day,
        chronoBase: w.finishedAt ?? now,
        chronoDown: false,
        restEndsAt: null,
        actions: const [_undo, LockAction('save', 'Speichern')],
      );
  }
}

/// Führt einen Knopfdruck vom Sperrbildschirm aus.
void runLockAction(AppController c, String id) {
  final w = c.workout;
  if (id == 'undo') return c.undo();
  if (id == 'restFinished') return c.tick();
  if (w == null) return;
  switch (id) {
    case 'done':
      c.completeSet();
    case 'repsMinus':
      c.changeReps(-1);
    case 'repsPlus':
      c.changeReps(1);
    case 'restPlus':
      c.adjustRest(15);
    case 'restMinus':
      c.adjustRest(-15);
    case 'skip':
      c.skipRest();
    case 'end':
      c.endExercise();
    case 'accept':
      c.finishExercise(accept: true);
    case 'keep':
      c.finishExercise(accept: false);
    case 'finish':
      c.finishWorkout();
    case 'save':
      c.saveWorkout();
    default:
      if (id.startsWith('rate:')) c.rate(Rating.values.byName(id.substring(5)));
      if (id.startsWith('pick:')) c.pickExercise(id.substring(5));
  }
}

/// Hält die Benachrichtigung auf dem Stand des Trainings (nur Android).
class LockScreenBridge {
  LockScreenBridge(this.c, {MethodChannel? channel}) : _ch = channel ?? const MethodChannel('satzweise/workout_notification');

  final AppController c;
  final MethodChannel _ch;
  String? _last;

  Future<void> start() async {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'action') runLockAction(c, call.arguments as String);
    });
    c.addListener(_sync);
    try {
      final pending = await _ch.invokeListMethod<String>('pendingActions') ?? [];
      for (final a in pending) {
        runLockAction(c, a);
      }
    } on MissingPluginException {
      return;
    }
    _sync();
  }

  void _sync() {
    if (!c.loaded) return;
    final content = lockContent(c);
    final sig = content == null ? 'stop' : jsonEncode(content.toMap());
    if (sig == _last) return;
    _last = sig;
    if (content == null) {
      _ch.invokeMethod<void>('stop').catchError((_) {});
    } else {
      _ch.invokeMethod<void>('update', content.toMap()).catchError((_) {});
    }
  }
}
