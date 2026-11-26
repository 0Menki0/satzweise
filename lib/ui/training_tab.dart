import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../data/models.dart';
import '../logic/coach.dart';
import '../logic/controller.dart';
import '../logic/workout.dart';
import 'pictogram.dart';
import 'theme.dart';
import 'widgets.dart';

/// Ablauf (gleich auf Uhr, App und Sperrbildschirm):
/// Ort → Trainingsart → Übung → Aufwärmen → Satz → Satz eintragen (Pause
/// läuft) → Pause → Satz … → Übung beenden → Rückmeldung → Übung …
class TrainingTab extends StatelessWidget {
  const TrainingTab({super.key, required this.c, required this.openSettings});
  final AppController c;
  final VoidCallback openSettings;

  @override
  Widget build(BuildContext context) {
    final w = c.workout;
    final Widget body = switch (w?.phase) {
      null => StartView(c: c),
      Phase.warmup => _WarmupView(c: c),
      Phase.set => _SetRunView(c: c),
      Phase.log => _LogView(c: c),
      Phase.rest => _RestView(c: c),
      Phase.feedback => _FeedbackView(c: c),
      Phase.next => _NextView(c: c, openSettings: openSettings),
      Phase.summary => _SummaryView(c: c),
    };
    return ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24), children: [body]);
  }
}

// ------------------------------------------------------------------ Start

/// Zwei Schritte: erst der Ort, dann die Trainingsart.
class StartView extends StatefulWidget {
  const StartView({super.key, required this.c});
  final AppController c;

  @override
  State<StartView> createState() => _StartViewState();
}

class _StartViewState extends State<StartView> {
  Place? place;
  bool more = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c, col = AppColors.of(context);
    final last = c.sessions.lastOrNull;
    final head = Row(children: [
      Expanded(
          child: Text(place == null ? DateFormat('EEEE, d. MMMM', 'de_DE').format(c.now) : place!.label,
              style: TextStyle(color: col.mute, fontSize: 13))),
      if (place != null)
        OutlinedButton.icon(
          onPressed: () => setState(() => place = null),
          icon: const Icon(Icons.undo, size: 18),
          label: const Text('Zurück'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), shape: const StadiumBorder()),
        )
      else
        UndoButton(c),
    ]);

    if (place == null) {
      final usual = last?.place ?? Place.studio;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        const SizedBox(height: 6),
        Text('Wo trainierst du heute?', style: display(context, 32)),
        const SizedBox(height: 14),
        for (final p in [usual, ...Place.values.where((p) => p != usual)]) ...[
          ChoiceCard(
            title: p == Place.studio ? 'Im Studio' : 'Daheim',
            subtitle: p == Place.home
                ? 'Nur Übungen, die daheim gehen'
                : (last == null ? 'Alle Übungen' : 'Zuletzt am ${dayLabel(last.start)}'),
            selected: p == usual,
            onTap: () => setState(() => place = p),
          ),
          const SizedBox(height: 10),
        ],
      ]);
    }

    final plan = last?.plan ?? 'tl';
    final due = nextDay(c.sessions, plan);
    final options = <DayType>[
      due,
      for (final d in planById(plan).days)
        if (d.id != due.id) d,
      if (plan != 'gk') dayById('gk') else ...planById('tl').days,
    ];
    final others = [
      for (final p in plans)
        if (p.id != plan && p.id != 'gk' && !(plan == 'gk' && p.id == 'tl')) p,
    ];
    Widget card(DayType d, {bool dueMark = false}) {
      final l = c.sessions.where((s) => s.day == d.id).lastOrNull;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ChoiceCard(
          title: d.name,
          subtitle: [d.description, if (l != null) 'zuletzt ${dayLabel(l.start)}'].join(' · '),
          selected: dueMark,
          badge: dueMark ? 'dran' : null,
          onTap: () => c.startWorkout(d.id, place: place!),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      head,
      const SizedBox(height: 6),
      Text('Was trainierst du?', style: display(context, 32)),
      const SizedBox(height: 14),
      for (final d in options) card(d, dueMark: d.id == due.id),
      TextButton(
        onPressed: () => setState(() => more = !more),
        child: Text(more ? 'Weitere Trainingsarten ausblenden' : 'Weitere Trainingsarten'),
      ),
      if (more)
        for (final p in others) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Text(p.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: col.mute)),
          ),
          for (final d in p.days) card(d, dueMark: false),
        ],
    ]);
  }
}

// ------------------------------------------------------------------ Kopfzeile

class _Header extends StatelessWidget {
  const _Header({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final w = c.workout!, col = AppColors.of(context);
    return Row(children: [
      Expanded(
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
          DayTag(w.day),
          Text('· ${w.place.label} · Gesamt', style: TextStyle(fontSize: 13, color: col.mute)),
          Text(clock(w.elapsedSec(c.now)),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
      ),
      UndoButton(c),
    ]);
  }
}

/// Großer Zeitblock: Aufwärmen, Satz oder Pause.
class _BigClock extends StatelessWidget {
  const _BigClock({required this.label, required this.value, required this.color, this.progress});
  final String label, value;
  final Color color;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final col = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(color: col.soft, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Text(label, style: TextStyle(fontSize: 13, color: col.mute)),
        const SizedBox(height: 4),
        Text(value, style: display(context, 64, color: color)),
        if (progress != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: progress, color: color, backgroundColor: col.line, minHeight: 6),
          ),
        ],
      ]),
    );
  }
}

class _ExerciseTitle extends StatelessWidget {
  const _ExerciseTitle({required this.c, required this.subtitle});
  final AppController c;
  final String subtitle;

  Future<void> _editMachine(BuildContext context) async {
    final w = c.workout!;
    final m = TextEditingController(text: w.machine), n = TextEditingController(text: w.note);
    final r = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Gerät und Notiz für heute', style: display(ctx, 22)),
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(
                width: 110,
                child: TextField(controller: m, decoration: const InputDecoration(labelText: 'Gerät Nr.', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: n,
                    decoration: const InputDecoration(labelText: 'Notiz', hintText: 'z. B. Sitz Stufe 4', border: OutlineInputBorder()))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, 'default'), child: Text('Als Standard für ${w.exercise}'))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton(onPressed: () => Navigator.pop(ctx, 'ok'), child: const Text('Fertig'))),
          ]),
        ]),
      ),
    );
    if (r == null) return;
    c.setMachine(m.text, n.text);
    if (r == 'default') c.saveMachineAsDefault();
  }

  @override
  Widget build(BuildContext context) {
    final w = c.workout!, col = AppColors.of(context);
    final e = c.exercise(w.exercise!);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Pictogram(kind: pictogramFor(e, e.name), size: 52),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.name, style: display(context, 28)),
            Text(subtitle, style: TextStyle(fontSize: 13, color: col.mute)),
          ]),
        ),
      ]),
      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _editMachine(context),
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: Text([
            w.machine.isEmpty ? 'Kein Gerät' : 'Gerät ${w.machine}',
            if (w.note.isNotEmpty) w.note,
            if (w.lastMachine.isNotEmpty && w.lastMachine != w.machine) 'zuletzt Gerät ${w.lastMachine}',
          ].join(' · ')),
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ Aufwärmen

class _WarmupView extends StatelessWidget {
  const _WarmupView({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final w = c.workout!, col = AppColors.of(context);
    final e = c.exercise(w.exercise!);
    final s = w.currentSet!;
    final last = lastLog(c.sessions, e.name);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Header(c: c),
      const SizedBox(height: 8),
      _ExerciseTitle(c: c, subtitle: 'Ziel ${e.repMin}–${e.repMax} Wdh. je Satz'),
      const SizedBox(height: 8),
      _BigClock(label: 'Aufwärmen', value: clock(w.warmupElapsedSec(c.now)), color: col.blue),
      const SizedBox(height: 12),
      Hint(Text.rich(TextSpan(children: [
        const TextSpan(text: '1. Satz geplant: '),
        TextSpan(text: setLabel(e, s.reps, s.weight), style: const TextStyle(fontWeight: FontWeight.w700)),
        if (last != null)
          TextSpan(
              text: '\nLetztes Mal (${dayLabel(last.date)}): ${last.log.sets.map((x) => x.reps).join(' / ')} Wdh. · '
                  '${weightText(e, last.log.topSet.weight)}'
                  '${s.weight > last.log.topSet.weight ? ' · Steigerung' : ''}'),
      ]))),
      const SizedBox(height: 14),
      FilledButton(onPressed: c.startSet, child: const Text('Satz starten')),
    ]);
  }
}

// ------------------------------------------------------------------ Satz läuft

class _SetRunView extends StatelessWidget {
  const _SetRunView({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final w = c.workout!, col = AppColors.of(context);
    final e = c.exercise(w.exercise!);
    final s = w.currentSet!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Header(c: c),
      const SizedBox(height: 8),
      _ExerciseTitle(c: c, subtitle: 'Satz ${w.current + 1} · geplant ${setLabel(e, s.reps, s.weight)}'),
      if (c.restJustFinished) ...[
        const SizedBox(height: 8),
        Hint(const Text('Pause vorbei, auf zum nächsten Satz', style: TextStyle(fontWeight: FontWeight.w600)),
            color: col.green, fg: Colors.white),
      ],
      const SizedBox(height: 8),
      _BigClock(label: 'Satz läuft', value: clock(w.setElapsedSec(c.now)), color: AppColors.red),
      const SizedBox(height: 16),
      FilledButton(onPressed: c.completeSet, child: const Text('Satz beenden')),
      const SizedBox(height: 10),
      for (final d in w.doneSets.reversed) _SetRow(i: w.sets.indexOf(d), s: d, e: e),
    ]);
  }
}

// ------------------------------------------------------------------ Satz eintragen

class _LogView extends StatelessWidget {
  const _LogView({required this.c});
  final AppController c;

  /// Gewicht von Hand eintragen: Tipp auf die Zahl.
  Future<void> _enterWeight(BuildContext context, Exercise e, double current) async {
    final t = TextEditingController(text: current == 0 && e.bodyweight ? '' : fmtKg(current));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) {
        void ok() => Navigator.pop(ctx, double.tryParse(t.text.trim().replaceAll(',', '.')) ?? (t.text.trim().isEmpty ? 0 : null));
        return AlertDialog(
          title: Text(e.bodyweight ? 'Zusatzgewicht' : 'Gewicht'),
          content: TextField(
            controller: t,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(suffixText: 'kg', hintText: e.bodyweight ? '0 = ohne' : null),
            onSubmitted: (_) => ok(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: ok, child: const Text('Übernehmen')),
          ],
        );
      },
    );
    if (v != null) c.setWeight(v);
  }

  @override
  Widget build(BuildContext context) {
    final w = c.workout!;
    final e = c.exercise(w.exercise!);
    final s = w.currentSet!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Header(c: c),
      const SizedBox(height: 8),
      _RestBar(c: c),
      const SizedBox(height: 12),
      Text('Wie lief Satz ${w.current + 1}?', style: display(context, 28)),
      Text(e.name, style: TextStyle(fontSize: 13, color: AppColors.of(context).mute)),
      const SizedBox(height: 12),
      StepField(
          value: '${s.reps}',
          unit: 'Wiederholungen',
          semantics: 'Wiederholungen',
          onMinus: () => c.changeReps(-1),
          onPlus: () => c.changeReps(1)),
      const SizedBox(height: 10),
      StepField(
          value: e.bodyweight && s.weight == 0 ? 'KG' : fmtKg(s.weight),
          unit: e.bodyweight ? (s.weight == 0 ? 'Körpergewicht' : 'kg Zusatz') : 'kg · tippen zum Eintippen',
          semantics: 'Gewicht',
          onTapValue: () => _enterWeight(context, e, s.weight),
          onMinus: () => c.changeWeight(-1),
          onPlus: () => c.changeWeight(1)),
      const SizedBox(height: 16),
      FilledButton(onPressed: c.continueSets, child: const Text('Weiter')),
      const SizedBox(height: 10),
      OutlinedButton(onPressed: c.endExercise, child: Text('Übung beenden (${w.doneSets.length} ${w.doneSets.length == 1 ? 'Satz' : 'Sätze'})')),
      const SizedBox(height: 8),
      Text('Läuft die Pause ab, geht es mit diesen Werten weiter.',
          style: TextStyle(fontSize: 12, color: AppColors.of(context).mute)),
    ]);
  }
}

class _RestBar extends StatelessWidget {
  const _RestBar({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final w = c.workout!, col = AppColors.of(context);
    final rem = w.restRemaining(c.now);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: col.blue, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Expanded(child: Text('Pause läuft', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
        Text(clock(rem), style: display(context, 26, color: Colors.white)),
      ]),
    );
  }
}

// ------------------------------------------------------------------ Pause

class _RestView extends StatelessWidget {
  const _RestView({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final w = c.workout!, col = AppColors.of(context);
    final e = c.exercise(w.exercise!);
    final s = w.currentSet!;
    final rem = w.restRemaining(c.now);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Header(c: c),
      const SizedBox(height: 8),
      _ExerciseTitle(c: c, subtitle: 'danach Satz ${w.current + 1} · ${setLabel(e, s.reps, s.weight)}'),
      const SizedBox(height: 8),
      _BigClock(label: 'Pause', value: clock(rem), color: col.blue, progress: w.restSec == 0 ? 0 : rem / w.restSec),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => c.adjustRest(-15), child: const Text('−15 s'))),
        const SizedBox(width: 10),
        Expanded(child: OutlinedButton(onPressed: () => c.adjustRest(15), child: const Text('+15 s'))),
      ]),
      const SizedBox(height: 12),
      FilledButton(onPressed: c.skipRest, child: const Text('Pause beenden')),
      const SizedBox(height: 10),
      for (final d in w.doneSets.reversed) _SetRow(i: w.sets.indexOf(d), s: d, e: e),
    ]);
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({required this.i, required this.s, required this.e});
  final int i;
  final SetEntry s;
  final Exercise e;

  @override
  Widget build(BuildContext context) {
    final col = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: col.line))),
      child: Row(children: [
        SizedBox(width: 56, child: Text('Satz ${i + 1}', style: TextStyle(fontSize: 13, color: col.mute))),
        Expanded(child: Text(setLabel(e, s.reps, s.weight), style: display(context, 20, weight: FontWeight.w600))),
        Icon(Icons.check, color: col.green, size: 18),
        const SizedBox(width: 4),
        Text('${s.durationSec} s', style: TextStyle(fontSize: 12, color: col.mute)),
      ]),
    );
  }
}

// ------------------------------------------------------------------ Rückmeldung

class _FeedbackView extends StatelessWidget {
  const _FeedbackView({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final w = c.workout!, col = AppColors.of(context);
    final e = c.exercise(w.exercise!);
    final done = w.sets.where((s) => s.done);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Header(c: c),
      const SizedBox(height: 10),
      Text('${w.exercise} · ${done.map((s) => s.reps).join(' / ')} Wdh. · ${weightText(e, done.first.weight)}',
          style: TextStyle(fontSize: 13, color: col.mute)),
      const SizedBox(height: 6),
      Text('Wie war\'s?', style: display(context, 30)),
      const SizedBox(height: 14),
      for (final r in Rating.values) ...[
        SizedBox(
          height: 64,
          child: OutlinedButton(
            onPressed: () => c.rate(r),
            style: OutlinedButton.styleFrom(
                side: BorderSide(color: r == Rating.passend ? AppColors.red : col.line, width: 2),
                padding: const EdgeInsets.symmetric(horizontal: 16)),
            child: Row(children: [
              Expanded(child: Text(r.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              Text(r.hint, style: TextStyle(fontSize: 13, color: col.mute, fontWeight: FontWeight.w400)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
      ],
      Text(
          'Leicht steigert schneller, auch wenn noch nicht alle Sätze oben im Bereich sind. '
          'Passend steigert erst, wenn alle Sätze ${e.repMax} Wdh. erreichen. '
          'Schwer hält das Gewicht oder senkt es.',
          style: TextStyle(fontSize: 13, color: col.mute)),
    ]);
  }
}

// ------------------------------------------------------------------ Nächste Übung

class _NextView extends StatelessWidget {
  const _NextView({required this.c, required this.openSettings});
  final AppController c;
  final VoidCallback openSettings;

  @override
  Widget build(BuildContext context) {
    final w = c.workout!, col = AppColors.of(context);
    final sg = c.suggestions();
    final rest = c.selected
        .where((e) => e.availableAt(w.place) && !w.done.contains(e.name) && !sg.any((s) => s.exercise == e.name))
        .toList();
    final fit = rest.where((e) => fitsDay(c.sessions, e, w.day)).toList();
    final other = rest.where((e) => !fitsDay(c.sessions, e, w.day)).toList();
    Widget chips(List<Exercise> l) => Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in l) ActionChip(label: Text(e.name), onPressed: () => c.pickExercise(e.name)),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Header(c: c),
      if (w.items.isNotEmpty && w.recommendationReason != null) ...[
        const SizedBox(height: 10),
        Hint(Text(w.recommendationReason!)),
      ],
      const SizedBox(height: 10),
      Text(w.items.isEmpty ? 'Womit startest du?' : 'Als Nächstes?', style: display(context, 28)),
      const SizedBox(height: 12),
      for (var i = 0; i < sg.length; i++) ...[
        Material(
          color: col.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14), side: BorderSide(color: i == 0 ? AppColors.red : col.line, width: 2)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => c.pickExercise(sg[i].exercise),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Pictogram(kind: pictogramFor(c.tryExercise(sg[i].exercise), sg[i].exercise)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(sg[i].exercise, style: display(context, 22)),
                      MachineBadge(c.exercise(sg[i].exercise).machine),
                    ]),
                    Text(sg[i].reason, style: TextStyle(fontSize: 13, color: col.mute)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (fit.isNotEmpty) ...[
        Text('Passt zu ${dayById(w.day).name}', style: TextStyle(fontSize: 13, color: col.mute)),
        const SizedBox(height: 6),
        chips(fit),
        const SizedBox(height: 12),
      ],
      Text('Weitere aus deiner Auswahl', style: TextStyle(fontSize: 13, color: col.mute)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in other) ActionChip(label: Text(e.name), onPressed: () => c.pickExercise(e.name)),
        ActionChip(avatar: const Icon(Icons.add, size: 16), label: const Text('Übung hinzufügen'), onPressed: openSettings),
      ]),
      const SizedBox(height: 18),
      if (w.items.isNotEmpty)
        FilledButton(
            style: FilledButton.styleFrom(backgroundColor: col.ink, foregroundColor: col.surface),
            onPressed: c.finishWorkout,
            child: const Text('Training beenden'))
      else
        OutlinedButton(onPressed: c.cancelWorkout, child: const Text('Training beenden')),
    ]);
  }
}

// ------------------------------------------------------------------ Zusammenfassung

class _SummaryView extends StatelessWidget {
  const _SummaryView({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final w = c.workout!, col = AppColors.of(context);
    final m = c.summary();
    final toneColor = switch (m.tone) { Tone.up => col.green, Tone.same => col.blue, Tone.down => col.amber };
    final pct = m.volumeChangePct;
    final dn = dayById(w.day).name;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Flexible(child: Text('Zusammenfassung · ', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: col.mute))),
        DayTag(w.day, suffix: ' · ${w.place.label}'),
        const Spacer(),
        UndoButton(c),
      ]),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: toneColor, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.title, style: display(context, 28, color: Colors.white)),
          const SizedBox(height: 6),
          Text(m.text, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.45)),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Kpi(clock(w.elapsedSec(c.now)), 'Gesamtzeit')),
        const SizedBox(width: 8),
        Expanded(child: Kpi(kg(m.volume), 'bewegt${pct == null ? '' : ', ${pct > 0 ? '+' : ''}$pct %'}')),
        const SizedBox(width: 8),
        Expanded(child: Kpi('${m.setCount}', 'Sätze, ${w.items.length} Übungen')),
      ]),
      if (m.previous != null) ...[
        const SizedBox(height: 6),
        Text(
            'Vergleich mit deinem letzten $dn am ${dayLabel(m.previous!.start)}: ${kg(m.previous!.volume)}, '
            '${(m.previous!.durationSec / 60).round()} min'
            '${m.fewerExercises ? '. Heute ${w.items.length} statt ${m.previous!.items.length} Übungen, daher weniger Gesamtmasse' : ''}',
            style: TextStyle(fontSize: 13, color: col.mute)),
      ],
      const SizedBox(height: 8),
      for (final r in m.rows) _CompareRow(r: r, e: c.tryExercise(r.log.exercise)),
      const SizedBox(height: 12),
      Hint(Text('Garmin: Mit der Uhren-App wird dieses Training als Aktivität „$dn“ an Garmin Connect '
          'und weiter an Strava übertragen. Die Uhren-App folgt im nächsten Schritt.')),
      const SizedBox(height: 12),
      FilledButton(onPressed: c.saveWorkout, child: const Text('Speichern')),
    ]);
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({required this.r, required this.e});
  final ExerciseComparison r;
  final Exercise? e;

  @override
  Widget build(BuildContext context) {
    final col = AppColors.of(context);
    final (fg, sign) = switch (r.trend) {
      Trend.up => (col.green, '▲ '),
      Trend.down => (col.amber, '▼ '),
      Trend.same => (col.blue, '= '),
      Trend.neu => (col.mute, ''),
    };
    final t = r.log.topSet, p = r.previous?.topSet;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: col.line))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.log.exercise, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text('${setLabel(e, t.reps, t.weight)}${p == null ? '' : ', zuletzt ${setLabel(e, p.reps, p.weight)}'}',
                style: TextStyle(fontSize: 12, color: col.mute)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: fg.withValues(alpha: .13), borderRadius: BorderRadius.circular(99)),
          child: Text('$sign${r.change}', style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ]),
    );
  }
}
