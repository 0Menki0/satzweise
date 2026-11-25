import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/catalog.dart';
import '../data/models.dart';
import '../logic/coach.dart';
import '../logic/controller.dart';
import '../logic/workout.dart';
import '../ui/pictogram.dart';
import '../ui/widgets.dart';

/// Ein Knopf auf dem Sperrbildschirm. [icon] ist der Name eines Symbols auf
/// Android-Seite (WorkoutService.iconRes).
class LockAction {
  const LockAction(this.id, this.label, this.icon);
  final String id, label, icon;
  Map<String, String> toMap() => {'id': id, 'label': label, 'icon': icon};
}

enum LockMode { set, rest, other }

/// Inhalt der Player-Karte auf dem Sperrbildschirm, ähnlich einem
/// Musikplayer: Piktogramm als Bild, Übung als Titel, Pause als
/// Fortschrittsbalken. Der große Knopf ist im Satz ⏸ („Satz fertig“, die
/// Pause beginnt) und in der Pause ▶ („Weiter“). Dazu bis zu vier weitere.
class LockContent {
  const LockContent({
    required this.title,
    required this.subtitle,
    required this.dayName,
    required this.mode,
    required this.start,
    required this.buttons,
    required this.artKind,
    this.primary,
    this.setStart,
    this.restStart,
    this.restEnd,
  });

  final String title;

  /// „{total}“ ersetzt Android durch die laufende Gesamtzeit.
  final String subtitle;
  final String dayName;
  final LockMode mode;
  final DateTime start;
  final DateTime? setStart, restStart, restEnd;
  final LockAction? primary;
  final List<LockAction> buttons;
  final String artKind;

  Map<String, Object?> toMap() => {
        'title': title,
        'subtitle': subtitle,
        'dayName': dayName,
        'mode': mode.name,
        'startMs': start.millisecondsSinceEpoch,
        'setStartMs': setStart?.millisecondsSinceEpoch ?? 0,
        'restStartMs': restStart?.millisecondsSinceEpoch ?? 0,
        'restEndMs': restEnd?.millisecondsSinceEpoch ?? 0,
        'primary': primary?.toMap(),
        'buttons': [for (final b in buttons) b.toMap()],
        'artKey': artKind,
      };
}

const _undo = LockAction('undo', 'Zurück', 'undo');
const _end = LockAction('end', 'Übung beenden', 'flag');

LockContent? lockContent(AppController c) {
  final w = c.workout;
  if (w == null) return null;
  final now = c.now, day = dayById(w.day).name;
  final art = w.exercise == null ? 'press' : pictogramFor(c.tryExercise(w.exercise!), w.exercise!);
  LockContent other(String title, String subtitle, List<LockAction> b, {String? artKind}) => LockContent(
      title: title, subtitle: subtitle, dayName: day, mode: LockMode.other, start: w.startedAt, buttons: b, artKind: artKind ?? art);

  switch (w.phase) {
    case Phase.set:
      final s = w.currentSet;
      if (s == null) return other('${w.exercise}: alle Sätze fertig', '{total}', const [_undo, _end]);
      final setText = '${s.reps} × ${fmtKg(s.weight)} kg${w.machine.isEmpty ? '' : ' · Gerät ${w.machine}'}';
      final pos = 'Satz ${w.current + 1}/${w.sets.length}';
      if (w.resting(now)) {
        return LockContent(
          title: 'Pause · danach $pos',
          subtitle: '${w.exercise}: $setText · {total}',
          dayName: day,
          mode: LockMode.rest,
          start: w.startedAt,
          restStart: w.restEndsAt!.subtract(Duration(seconds: w.restSec)),
          restEnd: w.restEndsAt,
          primary: const LockAction('skip', 'Weiter', 'play'),
          buttons: const [_undo, LockAction('restMinus', '−15 s', 'rest_minus'), LockAction('restPlus', '+15 s', 'rest_plus'), _end],
          artKind: art,
        );
      }
      final setStart = w.restEndsAt != null && w.restEndsAt!.isAfter(w.setStartedAt!) ? w.restEndsAt! : w.setStartedAt!;
      return LockContent(
        title: '${w.exercise} · $pos',
        subtitle: '$setText · {total}',
        dayName: day,
        mode: LockMode.set,
        start: w.startedAt,
        setStart: setStart,
        primary: const LockAction('done', 'Satz fertig', 'pause'),
        buttons: const [_undo, LockAction('repsMinus', '− Wdh.', 'minus'), LockAction('repsPlus', '+ Wdh.', 'plus'), _end],
        artKind: art,
      );
    case Phase.feedback:
      return other('${w.exercise}: wie war\'s?', '▮ leicht · ▮▮ passend · ▮▮▮ schwer', const [
        LockAction('rate:leicht', 'Leicht', 'level1'),
        LockAction('rate:passend', 'Passend', 'level2'),
        LockAction('rate:schwer', 'Schwer', 'level3'),
        _undo,
      ]);
    case Phase.recommend:
      final keep = w.sets.where((s) => s.done).map((s) => s.weight).reduce((a, b) => a > b ? a : b);
      return other('Nächstes Mal: ${fmtKg(w.recommendation!)} kg', '✓ übernehmen · = bei ${fmtKg(keep)} kg bleiben', const [
        _undo,
        LockAction('keep', 'Gleich lassen', 'equal'),
        LockAction('accept', 'Übernehmen', 'check'),
      ]);
    case Phase.next:
      final sg = c.suggestions(max: 2);
      final names = [for (var i = 0; i < sg.length; i++) '${i + 1} ${sg[i].exercise}'];
      return other(
        w.items.isEmpty ? 'Womit startest du?' : 'Als Nächstes?',
        '${names.join(' · ')} · {total}',
        [
          _undo,
          for (var i = 0; i < sg.length; i++) LockAction('pick:${sg[i].exercise}', sg[i].exercise, i == 0 ? 'one' : 'two'),
          if (w.items.isNotEmpty) const LockAction('finish', 'Training beenden', 'flag'),
        ],
        artKind: sg.isEmpty ? art : pictogramFor(c.tryExercise(sg.first.exercise), sg.first.exercise),
      );
    case Phase.summary:
      final m = c.summary();
      return other('$day fertig: ${m.title}', '${clock(w.elapsedSec(now))} · ${kg(m.volume)} · ${m.setCount} Sätze',
          const [_undo, LockAction('save', 'Speichern', 'save')]);
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

/// Hält die Player-Karte auf dem Stand des Trainings (nur Android).
class LockScreenBridge {
  LockScreenBridge(this.c, {MethodChannel? channel, this.renderArtwork = pictogramArtwork})
      : _ch = channel ?? const MethodChannel('satzweise/workout_notification');

  final AppController c;
  final MethodChannel _ch;
  final Future<Uint8List> Function(String kind) renderArtwork;
  String? _last;
  String? _artSent;

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
        return;
      }
      if (_artSent != content.artKind) {
        _artSent = content.artKind;
        await _ch.invokeMethod<void>('artwork', {'key': content.artKind, 'png': await renderArtwork(content.artKind)});
      }
      await _ch.invokeMethod<void>('update', content.toMap());
    } on PlatformException {
      // Ohne Benachrichtigung läuft das Training in der App normal weiter.
    }
  }
}
