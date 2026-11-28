import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/catalog.dart';
import '../data/models.dart';
import '../logic/coach.dart';
import '../logic/controller.dart';
import '../logic/workout.dart';
import 'lock_screen.dart';

int _s(DateTime? d) => d == null ? 0 : d.millisecondsSinceEpoch ~/ 1000;

/// Garmins Uhrenschrift kennt weder das Minuszeichen noch den Pfeil.
String _watchLabel(String s) => s.replaceAll('−', '-').replaceAll('↶ ', '');

Map<String, Object> _btn(LockAction a) => {'id': a.id, 'label': _watchLabel(a.label), if (a.primary) 'p': true};

/// Was die Garmin-Uhr zeigt. Zeiten in Sekunden seit 1970; die Uhr zählt
/// Gesamtzeit, Aufwärmen, Satz und Pause selbst. Für Aufwärmen, Satz,
/// Eintragen und Pause bekommt sie die Zahlen und baut ihre Knöpfe selbst,
/// damit sie auch ohne Verbindung weiterlaufen kann; für die übrigen Schritte
/// die Knöpfe wie auf dem Sperrbildschirm.
Map<String, Object?> watchContent(AppController c) {
  final w = c.workout;
  if (w == null) {
    final last = c.sessions.lastOrNull;
    final plan = last?.plan ?? 'tl';
    final due = nextDay(c.sessions, plan);
    final days = [
      due,
      for (final d in planById(plan).days)
        if (d.id != due.id) d,
      if (plan != 'gk') dayById('gk') else ...planById('tl').days,
    ];
    return {
      'idle': true,
      'day': 'Satzweise',
      'place': (last?.place ?? Place.studio).name,
      'days': [
        for (final d in days) {'id': d.id, 'label': d.id == due.id ? '${d.name} · dran' : d.name, if (d.id == due.id) 'p': true},
      ],
      'ended': c.lastEnd,
    };
  }
  final l = lockContent(c)!;
  final s = w.currentSet;
  final e = w.exercise == null ? null : c.tryExercise(w.exercise!);
  final inSet = const {Phase.warmup, Phase.set, Phase.log, Phase.rest}.contains(w.phase);
  return {
    'idle': false,
    'phase': w.phase.name,
    'title': _watchLabel(l.title),
    'text': _watchLabel(l.text),
    'day': l.dayName,
    'startS': _s(w.startedAt),
    'warmupS': _s(w.warmupStartedAt),
    'setStartS': _s(w.setStartedAt),
    'restStartS': _s(l.restStart),
    'restEndS': _s(w.restEndsAt),
    'sound': c.settings.restSound,
    'rows': [
      for (final r in l.rows) [for (final a in r) _btn(a)],
    ],
    'wide': l.wide == null ? null : _btn(l.wide!),
    if (inSet && s != null && e != null)
      'set': {
        'ex': e.name,
        'no': w.current + 1,
        'reps': s.reps,
        'w': s.weight,
        'step': e.step,
        'bw': e.bodyweight,
        'rest': w.restSec,
        'doneCount': w.doneSets.length,
        'machine': w.machine,
        'nextReps': w.lastReps.length > w.current + 1 ? w.lastReps[w.current + 1] : s.reps,
      },
  };
}

/// Hält die Uhr auf dem Stand des Trainings und führt ihre Knopfdrücke aus.
class WatchBridge {
  WatchBridge(this.c, {MethodChannel? channel}) : _ch = channel ?? const MethodChannel('satzweise/watch');

  final AppController c;
  final MethodChannel _ch;
  String? _last;
  bool? _wasActive;
  DateTime? _fromWatchAt;

  Future<void> start() async {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'action') handle(call.arguments as String);
    });
    c.addListener(_sync);
    try {
      for (final a in await _ch.invokeListMethod<String>('pendingActions') ?? const <String>[]) {
        handle(a);
      }
    } on MissingPluginException {
      return;
    }
    _sync();
  }

  void handle(String action) {
    _fromWatchAt = DateTime.now();
    if (action == 'hello') {
      _last = null; // Uhr ist neu gestartet: Stand auf jeden Fall schicken.
      _sync();
      return;
    }
    runLockAction(c, action);
  }

  Future<void> _sync() async {
    if (!c.loaded) return;
    // Training am Handy begonnen: Satzweise auf der Uhr öffnen (die Uhr
    // fragt nach). Kam der Start von der Uhr, läuft sie schon.
    final active = c.workout != null;
    if (active && _wasActive == false &&
        (_fromWatchAt == null || DateTime.now().difference(_fromWatchAt!) > const Duration(seconds: 5))) {
      _ch.invokeMethod<void>('open').catchError((_) {});
    }
    _wasActive = active;
    final content = watchContent(c);
    final sig = jsonEncode(content);
    if (sig == _last) return;
    _last = sig;
    try {
      await _ch.invokeMethod<void>('send', content);
    } on PlatformException {
      // Ohne Uhr läuft alles normal weiter.
    }
  }
}
