import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/models.dart';
import '../logic/coach.dart';
import '../logic/controller.dart';
import '../logic/workout.dart';
import 'lock_screen.dart';

int _s(DateTime? d) => d == null ? 0 : d.millisecondsSinceEpoch ~/ 1000;

Map<String, Object> _btn(LockAction a) => {'id': a.id, 'label': a.label, if (a.primary) 'p': true};

/// Was die Garmin-Uhr zeigt. Zeiten in Sekunden seit 1970; die Uhr zählt
/// Gesamtzeit, Satzzeit und Pause selbst. Für Satz und Pause bekommt sie die
/// Zahlen, um auch ohne Verbindung weiterrechnen zu können; für die übrigen
/// Schritte die Knöpfe wie auf dem Sperrbildschirm.
Map<String, Object?> watchContent(AppController c) {
  final w = c.workout;
  if (w == null) {
    final last = c.sessions.lastOrNull;
    final plan = last?.plan ?? 'tl';
    final due = nextDay(c.sessions, plan);
    final place = last?.place ?? Place.studio;
    return {
      'idle': true,
      'title': 'Heute dran: ${due.name}',
      'text': 'Wo trainierst du?',
      'day': 'Satzweise',
      'rows': [
        [
          {'id': 'go:${due.id}:studio', 'label': 'Studio', if (place == Place.studio) 'p': true},
          {'id': 'go:${due.id}:home', 'label': 'Daheim', if (place == Place.home) 'p': true},
        ],
      ],
      if (due.id != 'gk') 'wide': {'id': 'go:gk:${place.name}', 'label': 'Ganzkörper'},
      'ended': c.lastEnd,
    };
  }
  final l = lockContent(c)!;
  final set = w.phase == Phase.set ? w.currentSet : null;
  final e = w.exercise == null ? null : c.tryExercise(w.exercise!);
  return {
    'idle': false,
    'title': l.title,
    'text': l.text,
    'day': l.dayName,
    'status': l.status.name,
    'startS': _s(w.startedAt),
    'setStartS': _s(l.setStart),
    'restStartS': _s(l.restStart),
    'restEndS': _s(l.restEnd),
    'sound': c.settings.restSound,
    'rows': [
      for (final r in l.rows) [for (final a in r) _btn(a)],
    ],
    'wide': l.wide == null ? null : _btn(l.wide!),
    if (set != null && e != null)
      'set': {
        'ex': e.name,
        'no': w.current + 1,
        'reps': set.reps,
        'w': set.weight,
        'step': e.step,
        'bw': e.bodyweight,
        'rest': w.restSec,
        'doneCount': w.doneSets.length,
      },
  };
}

/// Hält die Uhr auf dem Stand des Trainings und führt ihre Knopfdrücke aus.
class WatchBridge {
  WatchBridge(this.c, {MethodChannel? channel}) : _ch = channel ?? const MethodChannel('satzweise/watch');

  final AppController c;
  final MethodChannel _ch;
  String? _last;

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
    if (action == 'hello') {
      _last = null; // Uhr ist neu gestartet: Stand auf jeden Fall schicken.
      _sync();
      return;
    }
    runLockAction(c, action);
  }

  Future<void> _sync() async {
    if (!c.loaded) return;
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
