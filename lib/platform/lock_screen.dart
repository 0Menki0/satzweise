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

enum LockStatus { none, setRunning, resting }

/// Inhalt der Trainings-Benachrichtigung: eine normale Android-Benachrichtigung
/// mit bis zu zwei Reihen à drei Textknöpfen und einem breiten Knopf darunter.
/// Eingeklappt zeigt sie nur die erste Reihe.
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
const _end = LockAction('end', 'Übung beenden');

LockContent? lockContent(AppController c) {
  final w = c.workout;
  if (w == null) return null;
  final now = c.now, day = dayById(w.day).name;
  LockContent simple(String title, String text, List<List<LockAction>> rows, {LockAction? wide}) => LockContent(
      title: title, text: text, dayName: day, start: w.startedAt, rows: rows, wide: wide, sound: c.settings.restSound);

  switch (w.phase) {
    case Phase.set:
      final s = w.currentSet!;
      final e = c.exercise(w.exercise!);
      final step = fmtKg(e.step);
      final setText = '${s.reps} × ${fmtKg(s.weight)} kg${w.machine.isEmpty ? '' : ' · Gerät ${w.machine}'}';
      final n = w.current + 1;
      if (w.resting(now)) {
        return LockContent(
          title: 'Pause · danach Satz $n',
          text: '${w.exercise}: $setText',
          dayName: day,
          start: w.startedAt,
          status: LockStatus.resting,
          restStart: w.restEndsAt!.subtract(Duration(seconds: w.restSec)),
          restEnd: w.restEndsAt,
          sound: c.settings.restSound,
          rows: const [
            [LockAction('restMinus', '−15 s'), LockAction('restPlus', '+15 s'), LockAction('skip', 'Weiter', primary: true)],
            [LockAction('repsMinus', '− Wdh.'), LockAction('repsPlus', '+ Wdh.'), _undo],
          ],
          wide: _end,
        );
      }
      final setStart = w.restEndsAt != null && w.restEndsAt!.isAfter(w.setStartedAt!) ? w.restEndsAt! : w.setStartedAt!;
      return LockContent(
        title: '${w.exercise} · Satz $n',
        text: setText,
        dayName: day,
        start: w.startedAt,
        status: LockStatus.setRunning,
        setStart: setStart,
        sound: c.settings.restSound,
        rows: [
          const [LockAction('repsMinus', '− Wdh.'), LockAction('repsPlus', '+ Wdh.'), LockAction('done', 'Satz fertig', primary: true)],
          [LockAction('weightMinus', '− $step kg'), LockAction('weightPlus', '+ $step kg'), _undo],
        ],
        wide: w.doneSets.isEmpty ? null : LockAction('end', 'Übung beenden (${w.doneSets.length} Sätze)'),
      );
    case Phase.feedback:
      final done = w.sets.where((s) => s.done);
      return simple('${w.exercise}: Wie war\'s?', '${done.map((s) => s.reps).join(' / ')} Wdh. bei ${fmtKg(done.first.weight)} kg', [
        [for (final r in Rating.values) LockAction('rate:${r.name}', r.label, primary: r == Rating.passend)],
      ], wide: _undo);
    case Phase.recommend:
      final keep = w.sets.where((s) => s.done).map((s) => s.weight).reduce((a, b) => a > b ? a : b);
      final rec = w.recommendation!;
      return simple('Nächstes Mal ${w.exercise}', w.recommendationReason ?? '', [
        [
          if (rec != keep) LockAction('keep', '${fmtKg(keep)} kg lassen'),
          LockAction('accept', '${fmtKg(rec)} kg ok', primary: true),
        ],
      ], wide: _undo);
    case Phase.next:
      final sg = c.suggestions(max: 3);
      final picks = [for (var i = 0; i < sg.length; i++) LockAction('pick:${sg[i].exercise}', sg[i].exercise, primary: i == 0)];
      return simple(
        w.items.isEmpty ? 'Womit startest du?' : 'Als Nächstes?',
        sg.isEmpty ? 'Übung in der App wählen' : sg.first.reason,
        [
          [...picks.take(2), if (picks.length < 3) _undo],
          if (picks.length >= 3) [picks[2], _undo],
        ],
        wide: w.items.isEmpty ? null : const LockAction('finish', 'Training beenden'),
      );
    case Phase.summary:
      final m = c.summary();
      return simple('$day fertig: ${m.title}', '${clock(w.elapsedSec(now))} · ${kg(m.volume)} · ${m.setCount} Sätze', const [
        [_undo, LockAction('save', 'Speichern', primary: true)],
      ]);
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
