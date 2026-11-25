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

class TrainingTab extends StatelessWidget {
  const TrainingTab({super.key, required this.c, required this.openSettings});
  final AppController c;
  final VoidCallback openSettings;

  @override
  Widget build(BuildContext context) {
    final w = c.workout;
    final Widget body = switch (w?.phase) {
      null => StartView(c: c),
      Phase.set => _SetView(c: c),
      Phase.feedback => _FeedbackView(c: c),
      Phase.recommend => _RecommendView(c: c),
      Phase.next => _NextView(c: c, openSettings: openSettings),
      Phase.summary => _SummaryView(c: c),
    };
    return ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24), children: [body]);
  }
}

// ------------------------------------------------------------------ Start

class StartView extends StatefulWidget {
  const StartView({super.key, required this.c});
  final AppController c;

  @override
  State<StartView> createState() => _StartViewState();
}

class _StartViewState extends State<StartView> {
  late String plan;
  late String day;

  @override
  void initState() {
    super.initState();
    final last = widget.c.sessions.lastOrNull;
    plan = last?.plan ?? 'tl';
    day = nextDay(widget.c.sessions, plan).id;
  }

  void _pickPlan(String p) => setState(() {
        plan = p;
        day = nextDay(widget.c.sessions, p).id;
      });

  @override
  Widget build(BuildContext context) {
    final c = widget.c, col = AppColors.of(context);
    final p = planById(plan), due = nextDay(c.sessions, plan);
    final last = c.sessions.lastWhereOrNull((s) => s.plan == plan);
    final order = usualOrder(c.sessions, day, only: {for (final e in c.selected) e.name});
    Widget planCard(TrainingPlan x) =>
        ChoiceCard(title: x.name, subtitle: x.description, selected: plan == x.id, onTap: () => _pickPlan(x.id));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(DateFormat('EEEE, d. MMMM', 'de_DE').format(c.now), style: TextStyle(color: col.mute, fontSize: 13))),
        UndoButton(c),
      ]),
      const SizedBox(height: 6),
      Text('Was trainierst du heute?', style: display(context, 32)),
      const SizedBox(height: 12),
      for (final x in plans.where((x) => x.usual)) ...[planCard(x), const SizedBox(height: 8)],
      if (p.days.length > 1) ...[
        const SectionTitle('Welcher Tag?'),
        Row(children: [
          for (final d in p.days) ...[
            Expanded(
                child: ChoiceCard(
                    title: d.name,
                    subtitle: d.description,
                    selected: day == d.id,
                    badge: d.id == due.id ? 'dran' : null,
                    onTap: () => setState(() => day = d.id))),
            if (d != p.days.last) const SizedBox(width: 8),
          ],
        ]),
      ],
      const SizedBox(height: 12),
      Hint(Text([
        last == null ? 'Mit diesem Plan hast du noch nicht trainiert.' : 'Zuletzt ${dayById(last.day).name} am ${dayLabel(last.start)}',
        if (order.isNotEmpty) 'Üblicher Ablauf: ${order.join(' → ')}',
      ].join('\n'))),
      const SizedBox(height: 12),
      FilledButton(onPressed: () => c.startWorkout(day), child: Text('${dayById(day).name} starten')),
      const SizedBox(height: 22),
      Text('Weitere Trainingsarten', style: TextStyle(color: col.mute, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      for (final x in plans.where((x) => !x.usual)) ...[planCard(x), const SizedBox(height: 8)],
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
          Text('· Gesamt', style: TextStyle(fontSize: 13, color: col.mute)),
          Text(clock(w.elapsedSec(c.now)),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
          Text('· ${w.items.length} erledigt', style: TextStyle(fontSize: 13, color: col.mute)),
        ]),
      ),
      UndoButton(c),
    ]);
  }
}

// ------------------------------------------------------------------ Satz

class _SetView extends StatelessWidget {
  const _SetView({required this.c});
  final AppController c;

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
    final w = c.workout!, col = AppColors.of(context), now = c.now;
    final e = c.exercise(w.exercise!);
    final last = lastLog(c.sessions, e.name);
    final resting = w.resting(now);
    final cur = w.currentSet;

    final hint = last == null
        ? 'Erstes Mal: Startgewicht ${fmtKg(w.sets.first.weight)} kg, passe es nach dem ersten Satz an.'
        : 'Letztes Mal (${dayLabel(last.date)}): ${last.log.sets.map((s) => s.reps).join(' / ')} Wdh. × '
            '${fmtKg(last.log.topSet.weight)} kg'
            '${w.sets.first.weight > last.log.topSet.weight ? ' · Steigerung auf ${fmtKg(w.sets.first.weight)} kg' : ''}';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Header(c: c),
      const SizedBox(height: 8),
      Row(children: [
        Pictogram(kind: pictogramFor(e, e.name), size: 58),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.name, style: display(context, 30)),
            Text('Ziel ${e.repMin}–${e.repMax} Wdh. je Satz · Pause ${clock(w.restSec)}',
                style: TextStyle(fontSize: 13, color: col.mute)),
          ]),
        ),
      ]),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: () => _editMachine(context),
        style: OutlinedButton.styleFrom(
            side: BorderSide(color: col.line, style: BorderStyle.solid), padding: const EdgeInsets.symmetric(horizontal: 10)),
        child: Row(children: [
          if (w.machine.isEmpty) Text('Kein Gerät ', style: TextStyle(color: col.mute, fontSize: 13)) else MachineBadge(w.machine),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
                [if (w.note.isNotEmpty) w.note, if (w.lastMachine.isNotEmpty && w.lastMachine != w.machine) 'zuletzt Gerät ${w.lastMachine}']
                    .join(' · '),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: col.ink, fontWeight: FontWeight.w400)),
          ),
          Text('ändern', style: TextStyle(fontSize: 13, color: col.mute)),
        ]),
      ),
      const SizedBox(height: 8),
      Hint(Text(hint)),
      const SizedBox(height: 6),
      for (var i = 0; i < w.sets.length; i++)
        if (i == w.current)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.red.withValues(alpha: .08), borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: Text(
                        'Satz ${i + 1}${w.lastReps.length > i ? ' · letztes Mal ${w.lastReps[i]} Wdh.' : ''}',
                        style: TextStyle(fontSize: 13, color: col.mute))),
                if (!resting)
                  Text('Satz läuft ${clock(w.setElapsedSec(now))}',
                      style: const TextStyle(fontSize: 13, color: AppColors.red, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                    child: StepField(
                        value: '${w.sets[i].reps}',
                        unit: 'Wdh.',
                        semantics: 'Wiederholungen',
                        onMinus: () => c.changeReps(-1),
                        onPlus: () => c.changeReps(1))),
                const SizedBox(width: 10),
                Expanded(
                    child: StepField(
                        value: fmtKg(w.sets[i].weight),
                        unit: 'kg',
                        semantics: 'Gewicht',
                        onMinus: () => c.changeWeight(-1),
                        onPlus: () => c.changeWeight(1))),
              ]),
            ]),
          )
        else
          _SetRow(i: i, s: w.sets[i]),
      const SizedBox(height: 10),
      if (resting)
        _RestPanel(c: c)
      else if (c.restJustFinished)
        Hint(const Text('Pause vorbei, auf zum nächsten Satz', style: TextStyle(fontWeight: FontWeight.w600)),
            color: col.green, fg: Colors.white)
      else if (cur != null)
        Row(children: [
          Expanded(child: Text('Pause nach dem Satz\nStandard ${clock(c.settings.restSec)}', style: TextStyle(fontSize: 13, color: col.mute))),
          SizedBox(
            width: 190,
            child: StepField(
                value: clock(w.restSec),
                unit: 'Pause',
                minusLabel: '−15',
                plusLabel: '+15',
                semantics: 'Pause',
                onMinus: () => c.adjustRest(-15),
                onPlus: () => c.adjustRest(15)),
          ),
        ]),
      const SizedBox(height: 12),
      if (cur != null) FilledButton(onPressed: c.completeSet, child: const Text('Satz fertig')),
      const SizedBox(height: 10),
      OutlinedButton(
          onPressed: w.sets.any((s) => s.done) ? c.endExercise : null,
          child: Text(w.sets.any((s) => s.done) ? 'Übung beenden (${w.doneSets.length} Sätze)' : 'Übung beenden')),
    ]);
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({required this.i, required this.s});
  final int i;
  final SetEntry s;

  @override
  Widget build(BuildContext context) {
    final col = AppColors.of(context);
    return Opacity(
      opacity: s.done ? 1 : .45,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: col.line))),
        child: Row(children: [
          SizedBox(width: 56, child: Text('Satz ${i + 1}', style: TextStyle(fontSize: 13, color: col.mute))),
          Expanded(child: Text('${s.reps} × ${fmtKg(s.weight)} kg', style: display(context, 22, weight: FontWeight.w600))),
          if (s.done) ...[
            Icon(Icons.check, color: col.green, size: 18),
            const SizedBox(width: 4),
            Text('${s.durationSec} s', style: TextStyle(fontSize: 12, color: col.mute)),
          ],
        ]),
      ),
    );
  }
}

class _RestPanel extends StatelessWidget {
  const _RestPanel({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final col = AppColors.of(context), w = c.workout!;
    final rem = w.restRemaining(c.now);
    ButtonStyle s() => OutlinedButton.styleFrom(
        foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54), minimumSize: const Size(0, 40));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: col.blue, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Row(children: [
          const Expanded(child: Text('Pause läuft', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          Text(clock(rem), style: display(context, 30, color: Colors.white)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
              value: w.restSec == 0 ? 0 : rem / w.restSec, color: Colors.white, backgroundColor: Colors.white24, minHeight: 6),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton(style: s(), onPressed: () => c.adjustRest(-15), child: const Text('−15 s'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(style: s(), onPressed: () => c.adjustRest(15), child: const Text('+15 s'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(style: s(), onPressed: c.skipRest, child: const Text('Weiter'))),
        ]),
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
    final done = w.sets.where((s) => s.done);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Header(c: c),
      const SizedBox(height: 10),
      Text('${w.exercise} · ${done.map((s) => s.reps).join(' / ')} Wdh. bei ${fmtKg(done.first.weight)} kg',
          style: TextStyle(fontSize: 13, color: col.mute)),
      const SizedBox(height: 6),
      Text('Wie hat es sich angefühlt?', style: display(context, 28)),
      const SizedBox(height: 14),
      for (final r in Rating.values) ...[
        SizedBox(
          height: 64,
          child: OutlinedButton(
            onPressed: () => c.rate(r),
            style: OutlinedButton.styleFrom(side: BorderSide(color: col.line, width: 2), padding: const EdgeInsets.symmetric(horizontal: 16)),
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
          'Passend steigert erst, wenn alle Sätze ${c.exercise(w.exercise!).repMax} Wdh. erreichen. '
          'Schwer hält das Gewicht oder senkt es.',
          style: TextStyle(fontSize: 13, color: col.mute)),
    ]);
  }
}

class _RecommendView extends StatelessWidget {
  const _RecommendView({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final w = c.workout!, col = AppColors.of(context);
    final keep = w.sets.where((s) => s.done).map((s) => s.weight).reduce((a, b) => a > b ? a : b);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Header(c: c),
      const SizedBox(height: 10),
      Text('Nächstes Mal bei ${w.exercise}', style: display(context, 28)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: col.soft, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${fmtKg(w.recommendation!)} kg', style: display(context, 56, color: AppColors.red)),
          const SizedBox(height: 6),
          Text(w.recommendationReason ?? ''),
        ]),
      ),
      const SizedBox(height: 14),
      FilledButton(onPressed: () => c.finishExercise(accept: true), child: const Text('Übernehmen')),
      const SizedBox(height: 10),
      OutlinedButton(onPressed: () => c.finishExercise(accept: false), child: Text('Lieber ${fmtKg(keep)} kg lassen')),
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
    final rest = c.selected.where((e) => !w.done.contains(e.name) && !sg.any((s) => s.exercise == e.name)).toList();
    final fit = rest.where((e) => fitsDay(c.sessions, e, w.day)).toList();
    final other = rest.where((e) => !fitsDay(c.sessions, e, w.day)).toList();
    Widget chips(List<Exercise> l) => Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in l) ActionChip(label: Text(e.name), onPressed: () => c.pickExercise(e.name)),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Header(c: c),
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
        OutlinedButton(onPressed: c.cancelWorkout, child: const Text('Abbrechen')),
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
        DayTag(w.day),
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
      for (final r in m.rows) _CompareRow(r: r),
      const SizedBox(height: 12),
      Hint(Text('Garmin: Mit der Uhren-App wird dieses Training als Aktivität „$dn“ an Garmin Connect '
          'und weiter an Strava übertragen. Die Uhren-App folgt im nächsten Schritt.')),
      const SizedBox(height: 12),
      FilledButton(onPressed: c.saveWorkout, child: const Text('Speichern')),
    ]);
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({required this.r});
  final ExerciseComparison r;

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
            Text('${t.reps} × ${fmtKg(t.weight)} kg${p == null ? '' : ', zuletzt ${p.reps} × ${fmtKg(p.weight)} kg'}',
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

extension<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) f) {
    for (var i = length - 1; i >= 0; i--) {
      if (f(this[i])) return this[i];
    }
    return null;
  }
}
