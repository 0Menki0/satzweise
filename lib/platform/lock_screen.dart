import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/catalog.dart';
import '../data/models.dart';
import '../logic/coach.dart';
import '../logic/controller.dart';
import '../logic/workout.dart';
import '../ui/widgets.dart';

/// Ein Textknopf auf dem Sperrbildschirm.
class LockAction {
  const LockAction(this.id, this.label, {this.primary = false});
  final String id, label;

  /// Rot hervorgehoben: die wahrscheinlichste nächste Aktion.
  final bool primary;
  Map<String, Object> toMap() => {'id': id, 'label': label, 'primary': primary};
}

enum LockStatus { none, warmup, setRunning, resting }

class LockContent {
  const LockContent({
    required this.title,
    required this.text,
    required this.dayName,
    required this.start,
    required this.rows,
    this.wide,
    this.status = LockStatus.none,
    this.setStart,
    this.restStart,
    this.restEnd,
    this.sound = false,
  });

  final String title, text, dayName;
  final DateTime start;
  final List<List<LockAction>> rows;
  final LockAction? wide;
  final LockStatus status;
  final DateTime? setStart, restStart, restEnd;

  /// Ton am Pausenende zusätzlich zur Vibration.
  final bool sound;

  List<LockAction> get all => [for (final r in rows) ...r, ?wide];

  Map<String, Object?> toMap() => {
        'title': title,
        'text': text,
        'dayName': dayName,
        'startMs': start.millisecondsSinceEpoch,
        'status': status.name,
        'setStartMs': setStart?.millisecondsSinceEpoch ?? 0,
        'restStartMs': restStart?.millisecondsSinceEpoch ?? 0,
        'restEndMs': restEnd?.millisecondsSinceEpoch ?? 0,
        'rows': [
          for (final r in rows) [for (final a in r) a.toMap()],
        ],
        'wide': wide?.toMap(),
        'sound': sound,
      };
}

const _undo = LockAction('undo', '↶ Zurück');

LockContent? lockContent(AppController c) {
  final w = c.workout;
  if (w == null) return null;
  final now = c.now, day = '${dayById(w.day).name} · ${w.place.label}';
  LockContent simple(String title, String text, List<List<LockAction>> rows, {LockAction? wide}) => LockContent(
      title: title, text: text, dayName: day, start: w.startedAt, rows: rows, wide: wide, sound: c.settings.restSound);
  final e = w.exercise == null ? null : c.exercise(w.exercise!);
  final s = w.currentSet;
  String label(SetEntry x) => '${setLabel(e, x.reps, x.weight)}${w.machine.isEmpty ? '' : ' · Gerät ${w.machine}'}';
  final n = w.current + 1;
  LockContent timed(String title, String text, LockStatus st, List<List<LockAction>> rows, {LockAction? wide}) => LockContent(
        title: title,
        text: text,
        dayName: day,
        start: w.startedAt,
        // Pause schon vorbei (nach „Zurück“): keine laufende Pausenuhr.
        status: st == LockStatus.resting && w.restEndsAt == null ? LockStatus.none : st,
        setStart: st == LockStatus.warmup ? w.warmupStartedAt : w.setStartedAt,
        restStart: w.restEndsAt?.subtract(Duration(seconds: w.restSec)),
        restEnd: w.restEndsAt,
        sound: c.settings.restSound,
        rows: rows,
        wide: wide,
      );

  switch (w.phase) {
    case Phase.warmup:
      return timed('${w.exercise} · Aufwärmen', '1. Satz: ${label(s!)}', LockStatus.warmup, const [
        [LockAction('startSet', 'Satz starten', primary: true)],
      ], wide: _undo);
    case Phase.set:
      return timed('${w.exercise} · Satz $n', 'geplant ${label(s!)}', LockStatus.setRunning, const [
        [LockAction('done', 'Satz beenden', primary: true)],
      ], wide: _undo);
    case Phase.log:
      final step = fmtKg(e!.step);
      return timed('Wie lief Satz $n? ${setLabel(e, s!.reps, s.weight)}', w.exercise!, LockStatus.resting, [
        const [LockAction('repsMinus', '− Wdh.'), LockAction('repsPlus', '+ Wdh.'), LockAction('cont', 'Weiter', primary: true)],
        [LockAction('weightMinus', '− $step kg'), LockAction('weightPlus', '+ $step kg'), const LockAction('end', 'Übung beenden')],
      ]);
    case Phase.rest:
      return timed('Pause · danach Satz $n', '${w.exercise}: ${label(s!)}', LockStatus.resting, const [
        [LockAction('restMinus', '−15 s'), LockAction('restPlus', '+15 s'), LockAction('skip', 'Pause beenden', primary: true)],
      ], wide: _undo);
    case Phase.feedback:
      final done = w.sets.where((x) => x.done);
      return simple('${w.exercise}: Wie war\'s?', '${done.map((x) => x.reps).join(' / ')} Wdh. · ${weightText(e, done.first.weight)}', [
        [for (final r in Rating.values) LockAction('rate:${r.name}', r.label, primary: r == Rating.passend)],
      ], wide: _undo);
    case Phase.next:
      final sg = c.suggestions(max: 3);
      final picks = [for (var i = 0; i < sg.length; i++) LockAction('pick:${sg[i].exercise}', sg[i].exercise, primary: i == 0)];
      return simple(
        w.items.isEmpty ? 'Womit startest du?' : 'Als Nächstes?',
        w.items.isNotEmpty && w.recommendationReason != null
            ? w.recommendationReason!
            : (sg.isEmpty ? 'Übung in der App wählen' : sg.first.reason),
        [
          [...picks.take(2), if (picks.length < 3) _undo],
          if (picks.length >= 3) [picks[2], _undo],
        ],
        wide: LockAction(w.items.isEmpty ? 'cancel' : 'finish', 'Training beenden'),
      );
    case Phase.summary:
      final m = c.summary();
      return simple('${dayById(w.day).name} fertig: ${m.title}', '${clock(w.elapsedSec(now))} · ${kg(m.volume)} · ${m.setCount} Sätze',
          const [
            [_undo, LockAction('save', 'Speichern', primary: true)],
          ]);
  }
}

/// Führt einen Knopfdruck vom Sperrbildschirm (oder der Uhr) aus.
void runLockAction(AppController c, String id) {
  final w = c.workout;
  if (id == 'undo') return c.undo();
  if (id == 'restFinished') return c.tick();
  if (id.startsWith('go:')) {
    // go:<Tag>:<Ort>, z. B. von der Uhr: Training starten.
    final p = id.split(':');
    if (w == null && p.length == 3 && dayTypes.containsKey(p[1])) {
      c.startWorkout(p[1], place: Place.values.asNameMap()[p[2]] ?? Place.studio);
    }
    return;
  }
  if (w == null) return;
  switch (id) {
    case 'startSet':
      c.startSet();
    case 'done':
      c.completeSet();
    case 'cont':
      c.continueSets();
    case 'repsMinus':
      c.changeReps(-1);
    case 'repsPlus':
      c.changeReps(1);
    case 'weightMinus':
      c.changeWeight(-1);
    case 'weightPlus':
      c.changeWeight(1);
    case 'restPlus':
      c.adjustRest(15);
    case 'restMinus':
      c.adjustRest(-15);
    case 'skip':
      c.skipRest();
    case 'end':
      c.endExercise();
    case 'finish':
      c.finishWorkout();
    case 'cancel':
      c.cancelWorkout();
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

  Future<void> _sync() async {
    if (!c.loaded) return;
    final content = lockContent(c);
    final sig = content == null ? 'stop' : jsonEncode(content.toMap());
    if (sig == _last) return;
    _last = sig;
    try {
      if (content == null) {
        await _ch.invokeMethod<void>('stop');
      } else {
        await _ch.invokeMethod<void>('update', content.toMap());
      }
    } on PlatformException {
      // Ohne Benachrichtigung läuft das Training in der App normal weiter.
    }
  }
}
