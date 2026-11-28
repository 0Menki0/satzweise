import 'dart:convert';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../data/models.dart';
import '../logic/coach.dart';
import '../logic/controller.dart';
import 'pictogram.dart';
import 'theme.dart';
import 'widgets.dart';
import '../logic/muscles.dart';
import 'muscle_map.dart';

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key, required this.c});
  final AppController c;

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  bool sessionsView = true;
  String dayFilter = 'all';
  String? open;
  Set<String> picked = {};
  String machine = 'all';

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24), children: [
      Text('Verlauf', style: display(context, 30)),
      const SizedBox(height: 10),
      SegmentedButton<bool>(
        segments: const [ButtonSegment(value: true, label: Text('Einheiten')), ButtonSegment(value: false, label: Text('Übungen'))],
        selected: {sessionsView},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => sessionsView = s.first),
      ),
      const SizedBox(height: 10),
      if (c.sessions.isEmpty)
        const Hint(Text('Noch keine Trainings gespeichert. Nach deinem ersten Training erscheint es hier.'))
      else if (sessionsView)
        ..._sessions(context)
      else
        ..._exercises(context),
    ]);
  }

  List<Widget> _sessions(BuildContext context) {
    final c = widget.c, col = AppColors.of(context);
    final ids = {for (final s in c.sessions) s.day}.toList();
    final list = c.sessions.where((s) => dayFilter == 'all' || s.day == dayFilter).toList();
    final st = c.stats(list);
    return [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final id in ['all', ...ids])
          ChoiceChip(
              label: Text(id == 'all' ? 'Alle' : dayById(id).name),
              selected: dayFilter == id,
              onSelected: (_) => setState(() {
                    dayFilter = id;
                    open = null;
                  })),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: Kpi('${c.sessionsInLastDays(28)}', 'Einheiten, 4 Wochen')),
        const SizedBox(width: 8),
        Expanded(child: Kpi('${st.avgMin.round()} min', 'Ø Dauer')),
        const SizedBox(width: 8),
        Expanded(child: Kpi('${fmtKg((st.avgVolume / 100).round() / 10)} t', 'Ø Masse')),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 14, children: [for (final id in ids) DayTag(id)]),
      SizedBox(height: 150, child: CustomPaint(painter: _BarChart(list.reversed.take(16).toList().reversed.toList(), col), size: Size.infinite)),
      for (final s in list.reversed)
        InkWell(
          onTap: () => setState(() => open = open == s.id ? null : s.id),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: col.line))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (open != s.id) ...[
                  BodyFigure(front: true, load: _load(s), width: 22),
                  BodyFigure(front: false, load: _load(s), width: 22),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(dayLabel(s.start), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                      DayTag(s.day, suffix: ' · ${s.place.label}'),
                    ]),
                    Text('${(s.durationSec / 60).round()} min · ${s.items.length} Übungen · ${s.setCount} Sätze · ${kg(s.volume)}',
                        style: TextStyle(fontSize: 13, color: col.mute)),
                  ]),
                ),
              ]),
              if (open == s.id) ...[
                const SizedBox(height: 10),
                MuscleMap(load: _load(s), figureWidth: 96),
                const SizedBox(height: 6),
                const MuscleLegend(),
                const SizedBox(height: 6),
              ],
              if (open == s.id)
                for (final (ii, it) in s.items.indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                          child: Wrap(spacing: 6, children: [Text(it.exercise, style: const TextStyle(fontSize: 13)), MachineBadge(it.machine)])),
                      // Tippen auf einen Satz bietet an, ihn zu löschen (z. B. doppelt eingetragen).
                      Flexible(
                        child: Wrap(alignment: WrapAlignment.end, spacing: 2, runSpacing: 2, children: [
                          for (final (si, x) in it.sets.indexed)
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => _confirmDeleteSet(s, ii, si, it.exercise, setLabel(widget.c.tryExercise(it.exercise), x.reps, x.weight)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Text(setLabel(widget.c.tryExercise(it.exercise), x.reps, x.weight) + (si < it.sets.length - 1 ? ' ·' : ''),
                                    style: const TextStyle(fontSize: 13)),
                              ),
                            ),
                        ]),
                      ),
                    ]),
                  ),
              if (open == s.id)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _confirmDelete(s),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Training löschen'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.red),
                  ),
                ),
            ]),
          ),
        ),
    ];
  }

  Future<void> _confirmDelete(Session s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Training löschen?'),
        content: Text('${dayById(s.day).name} am ${dayLabel(s.start)} mit ${s.items.length} Übungen und ${s.setCount} Sätzen '
            'wird endgültig gelöscht. Die Gewichtsvorgaben richten sich danach wieder nach deinem letzten verbliebenen Training.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final gone = widget.c.deleteSession(s.id);
    setState(() => open = null);
    if (gone == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Training gelöscht'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Rückgängig',
          onPressed: () {
            widget.c.restoreSession(gone.session, gone.nextWeights);
            if (mounted) setState(() => open = gone.session.id);
          },
        ),
      ));
  }

  Map<Muscle, double> _load(Session s) => muscleLoad(s.items, (n) => widget.c.tryExercise(n)?.group);

  Future<void> _confirmDeleteSet(Session s, int item, int set, String exercise, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Satz löschen?'),
        content: Text('$exercise, Satz ${set + 1}: $label'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final backup = jsonEncode(s.toJson());
    widget.c.deleteSetFromSession(s.id, item, set);
    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Satz gelöscht'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Rückgängig',
          onPressed: () {
            widget.c.replaceSession(Session.fromJson(jsonDecode(backup) as Map<String, dynamic>));
            if (mounted) setState(() {});
          },
        ),
      ));
  }

  static const _palette = [AppColors.red, AppColors.blueLight, Color(0xFF1D8A4D), Color(0xFFB86E00), Color(0xFF7B4FB8), Color(0xFF6B6862)];

  List<Widget> _exercises(BuildContext context) {
    final c = widget.c, col = AppColors.of(context);
    final names = <String>{for (final e in c.selected) e.name, for (final s in c.sessions) for (final i in s.items) i.exercise}
        .where((n) => c.sessions.any((s) => s.items.any((i) => i.exercise == n)))
        .toList();
    if (names.isEmpty) return [const Hint(Text('Noch keine Übungen im Verlauf.'))];
    var sel = picked.where(names.contains).toList();
    if (sel.isEmpty) sel = [names.first];
    final color = {for (var i = 0; i < sel.length; i++) sel[i]: _palette[i % _palette.length]};

    List<({DateTime date, String day, Place place, ExerciseLog log})> logsOf(String n) => [
          for (final s in c.sessions)
            for (final it in s.items.where((i) => i.exercise == n)) (date: s.start, day: s.day, place: s.place, log: it),
        ];
    final single = sel.length == 1;
    final machines = single ? {for (final x in logsOf(sel.first)) if (x.log.machine.isNotEmpty) x.log.machine}.toList() : <String>[];
    final m = machines.contains(machine) ? machine : 'all';
    bool keep(ExerciseLog l) => m == 'all' || l.machine == m;

    // Eine Kurve je Übung: Top-Gewicht, bei Körpergewicht die besten Wiederholungen.
    _Series series(String n) {
      final e = c.tryExercise(n);
      final bw = e?.bodyweight ?? false;
      final pts = [
        for (final x in logsOf(n).where((x) => keep(x.log)))
          (x.date, bw ? x.log.sets.map((s) => s.reps.toDouble()).reduce(math.max) : x.log.topSet.weight),
      ];
      return _Series(n, color[n]!, pts.length > 12 ? pts.sublist(pts.length - 12) : pts, bw);
    }

    final all = [for (final n in sel) series(n)];
    final kgSeries = all.where((x) => !x.reps && x.points.isNotEmpty).toList();
    final repSeries = all.where((x) => x.reps && x.points.isNotEmpty).toList();
    final rows = [
      for (final n in sel)
        for (final x in logsOf(n).where((x) => keep(x.log))) (n: n, x: x),
    ]..sort((a, b) => b.x.date.compareTo(a.x.date));

    return [
      MenuAnchor(
        style: const MenuStyle(maximumSize: WidgetStatePropertyAll(Size(360, 460))),
        menuChildren: [
          for (final n in names)
            CheckboxMenuButton(
              value: sel.contains(n),
              closeOnActivate: false,
              onChanged: (v) => setState(() {
                picked = {...sel};
                v == true ? picked.add(n) : picked.remove(n);
                machine = 'all';
              }),
              child: Text(n),
            ),
        ],
        builder: (context, ctrl, _) => OutlinedButton(
          onPressed: () => ctrl.isOpen ? ctrl.close() : ctrl.open(),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          child: Row(children: [
            Expanded(
              child: Text(single ? sel.first : '${sel.length} Übungen: ${sel.join(', ')}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
            ),
            const Icon(Icons.arrow_drop_down),
          ]),
        ),
      ),
      const SizedBox(height: 4),
      Text('Mehrere Übungen ankreuzen, um sie zu vergleichen.', style: TextStyle(fontSize: 12, color: col.mute)),
      const SizedBox(height: 10),
      if (single)
        Row(children: [
          Pictogram(kind: pictogramFor(c.tryExercise(sel.first), sel.first), size: 58),
          const SizedBox(width: 12),
          Expanded(child: Text(sel.first, style: display(context, 26))),
        ]),
      if (machines.length > 1) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [
          for (final x in ['all', ...machines])
            ChoiceChip(
                label: Text(x == 'all' ? 'Alle Geräte' : 'Gerät $x'), selected: m == x, onSelected: (_) => setState(() => machine = x)),
        ]),
      ],
      const SizedBox(height: 10),
      for (final x in all)
        if (x.points.isNotEmpty) _SeriesKpi(x: x, multi: !single, best: single ? logsOf(x.name).map((l) => best1rm(l.log.sets)).fold<double>(0, math.max) : null),
      if (kgSeries.any((x) => x.points.length >= 2)) ...[
        const SizedBox(height: 6),
        Text('Top-Gewicht in kg', style: TextStyle(fontSize: 12, color: col.mute)),
        SizedBox(height: 200, child: CustomPaint(painter: _LineChart(kgSeries, col), size: Size.infinite)),
      ],
      if (repSeries.any((x) => x.points.length >= 2)) ...[
        const SizedBox(height: 6),
        Text('Beste Wiederholungen (Körpergewicht)', style: TextStyle(fontSize: 12, color: col.mute)),
        SizedBox(height: 180, child: CustomPaint(painter: _LineChart(repSeries, col), size: Size.infinite)),
      ],
      SectionTitle('Alle Sätze', trailing: 'letzte ${math.min(12, rows.length)} Einheiten'),
      for (final r in rows.take(12))
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: col.line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (!single) ...[
                Container(width: 10, height: 10, decoration: BoxDecoration(color: color[r.n], shape: BoxShape.circle)),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text('${dayLabel(r.x.date)}${single ? '' : ' · ${r.n}'}',
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              DayTag(r.x.day, suffix: r.x.place == Place.home ? ' · Daheim' : ''),
              const Spacer(),
              MachineBadge(r.x.log.machine),
              const SizedBox(width: 6),
              if (r.x.log.volume > 0) Text(kg(r.x.log.volume), style: TextStyle(fontSize: 13, color: col.mute)),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in r.x.log.sets)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: col.soft, borderRadius: BorderRadius.circular(8)),
                  child: Text(setLabel(c.tryExercise(r.n), s.reps, s.weight), style: display(context, 16, weight: FontWeight.w600)),
                ),
            ]),
            if (r.x.log.note.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(r.x.log.note, style: TextStyle(fontSize: 12, color: col.mute))),
          ]),
        ),
    ];
  }
}

class _Series {
  _Series(this.name, this.color, this.points, this.reps);
  final String name;
  final Color color;
  final List<(DateTime, double)> points;

  /// true = Wiederholungen statt kg.
  final bool reps;
}

class _SeriesKpi extends StatelessWidget {
  const _SeriesKpi({required this.x, required this.multi, this.best});
  final _Series x;
  final bool multi;
  final double? best;

  @override
  Widget build(BuildContext context) {
    final col = AppColors.of(context);
    final first = x.points.first.$2, last = x.points.last.$2, d = last - first;
    String v(double n) => x.reps ? '${n.round()} Wdh.' : '${fmtKg(n)} kg';
    final change = '${d >= 0 ? '+' : ''}${x.reps ? '${d.round()} Wdh.' : '${fmtKg(d)} kg'} in ${x.points.length} Einheiten';
    if (!multi) {
      return Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v(last), style: display(context, 34, color: AppColors.red)),
            Text('${x.reps ? 'Beste Wiederholungen' : 'Top-Gewicht'}, $change', style: TextStyle(fontSize: 13, color: col.mute)),
          ]),
        ),
        if (best != null && !x.reps)
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fmtKg(best!.roundToDouble()), style: display(context, 34)),
              Text('bestes 1RM, geschätzt', style: TextStyle(fontSize: 13, color: col.mute)),
            ]),
          ),
      ]);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: x.color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(x.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
        Text(v(last), style: display(context, 18)),
        const SizedBox(width: 8),
        Text(change.split(' in ').first, style: TextStyle(fontSize: 12, color: d >= 0 ? col.green : col.amber)),
      ]),
    );
  }
}

TextPainter _label(String t, Color c) =>
    TextPainter(text: TextSpan(text: t, style: TextStyle(fontSize: 11, color: c)), textDirection: TextDirection.ltr)..layout();

class _BarChart extends CustomPainter {
  _BarChart(this.sessions, this.col);
  final List<Session> sessions;
  final AppColors col;

  @override
  void paint(Canvas canvas, Size size) {
    if (sessions.isEmpty) return;
    const l = 34.0, r = 4.0, t = 10.0, b = 20.0;
    final vs = sessions.map((s) => s.volume / 1000).toList();
    final hi = math.max(1.0, (vs.reduce(math.max) / 2).ceil() * 2.0);
    double y(double v) => t + (hi - v) * (size.height - t - b) / hi;
    final grid = Paint()..color = col.line;
    for (final v in [0.0, hi / 2, hi]) {
      canvas.drawLine(Offset(l, y(v)), Offset(size.width - r, y(v)), grid);
      final tp = _label('${fmtKg(v)} t', col.mute);
      tp.paint(canvas, Offset(l - 6 - tp.width, y(v) - tp.height / 2));
    }
    final bw = (size.width - l - r) / sessions.length;
    for (var i = 0; i < sessions.length; i++) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(l + i * bw + bw * .15, y(vs[i]), l + (i + 1) * bw - bw * .15, y(0)), const Radius.circular(2)),
          Paint()..color = col.day(sessions[i].day));
    }
    _label(dayLabel(sessions.first.start), col.mute).paint(canvas, Offset(l, size.height - 14));
    final e = _label(dayLabel(sessions.last.start), col.mute);
    e.paint(canvas, Offset(size.width - r - e.width, size.height - 14));
  }

  @override
  bool shouldRepaint(_BarChart o) => true;
}

class _LineChart extends CustomPainter {
  _LineChart(this.series, this.col);
  final List<_Series> series;
  final AppColors col;

  @override
  void paint(Canvas canvas, Size size) {
    const l = 34.0, r = 14.0, t = 16.0, b = 22.0;
    final pts = [for (final s in series) ...s.points];
    if (pts.isEmpty) return;
    final vals = pts.map((p) => p.$2);
    final lo = (vals.reduce(math.min) * .95).floorToDouble(), hi = (vals.reduce(math.max) * 1.03).ceilToDouble();
    final from = pts.map((p) => p.$1).reduce((a, b) => a.isBefore(b) ? a : b);
    final to = pts.map((p) => p.$1).reduce((a, b) => a.isAfter(b) ? a : b);
    final span = math.max(1, to.difference(from).inMinutes);
    double x(DateTime d) => l + d.difference(from).inMinutes / span * (size.width - l - r);
    double y(double v) => t + (hi - v) * (size.height - t - b) / (hi - lo == 0 ? 1 : hi - lo);
    for (final v in [lo, (lo + hi) / 2, hi]) {
      canvas.drawLine(Offset(l, y(v)), Offset(size.width - r, y(v)), Paint()..color = col.line);
      final tp = _label('${v.round()}', col.mute);
      tp.paint(canvas, Offset(l - 6 - tp.width, y(v) - tp.height / 2));
    }
    for (final s in series) {
      if (s.points.isEmpty) continue;
      final line = Path();
      for (var i = 0; i < s.points.length; i++) {
        final p = Offset(x(s.points[i].$1), y(s.points[i].$2));
        i == 0 ? line.moveTo(p.dx, p.dy) : line.lineTo(p.dx, p.dy);
      }
      if (series.length == 1 && s.points.length > 1) {
        final area = Path.from(line)
          ..lineTo(x(s.points.last.$1), size.height - b)
          ..lineTo(x(s.points.first.$1), size.height - b)
          ..close();
        canvas.drawPath(area, Paint()..color = s.color.withValues(alpha: .14));
      }
      canvas.drawPath(
          line,
          Paint()
            ..color = s.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeJoin = StrokeJoin.round);
      for (var i = 0; i < s.points.length; i++) {
        canvas.drawCircle(Offset(x(s.points[i].$1), y(s.points[i].$2)), i == s.points.length - 1 ? 5 : 3, Paint()..color = s.color);
      }
    }
    _label(dayLabel(from), col.mute).paint(canvas, Offset(l, size.height - 14));
    final e = _label(dayLabel(to), col.mute);
    e.paint(canvas, Offset(size.width - r - e.width, size.height - 14));
  }

  @override
  bool shouldRepaint(_LineChart o) => true;
}
