import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../data/catalog.dart';
import '../data/models.dart';
import '../logic/coach.dart';
import '../logic/controller.dart';
import 'pictogram.dart';
import 'theme.dart';
import 'widgets.dart';

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
  String? exercise;
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
                Expanded(child: Text(dayLabel(s.start), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                DayTag(s.day),
              ]),
              Text('${(s.durationSec / 60).round()} min · ${s.items.length} Übungen · ${s.setCount} Sätze · ${kg(s.volume)}',
                  style: TextStyle(fontSize: 13, color: col.mute)),
              if (open == s.id)
                for (final it in s.items)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                          child: Wrap(spacing: 6, children: [Text(it.exercise, style: const TextStyle(fontSize: 13)), MachineBadge(it.machine)])),
                      Flexible(
                        child: Text('${it.sets.map((x) => '${x.reps}×${fmtKg(x.weight)}').join(' · ')} kg',
                            textAlign: TextAlign.right, style: const TextStyle(fontSize: 13)),
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
    widget.c.deleteSession(s.id);
    setState(() => open = null);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Training gelöscht')));
  }

  List<Widget> _exercises(BuildContext context) {
    final c = widget.c, col = AppColors.of(context);
    final names = <String>{for (final e in c.selected) e.name, for (final s in c.sessions) for (final i in s.items) i.exercise}
        .where((n) => c.sessions.any((s) => s.items.any((i) => i.exercise == n)))
        .toList();
    if (names.isEmpty) return [const Hint(Text('Noch keine Übungen im Verlauf.'))];
    final ex = names.contains(exercise) ? exercise! : names.first;
    final full = [
      for (final s in c.sessions)
        for (final it in s.items.where((i) => i.exercise == ex)) (date: s.start, day: s.day, log: it),
    ];
    final machines = {for (final x in full) if (x.log.machine.isNotEmpty) x.log.machine}.toList();
    final m = machines.contains(machine) ? machine : 'all';
    final rows = full.where((x) => m == 'all' || x.log.machine == m).toList();
    final points = rows.reversed.take(12).toList().reversed.toList();
    final first = points.first.log.topSet, last = points.last.log.topSet;
    final best = rows.map((x) => best1rm(x.log.sets)).fold<double>(0, math.max);

    return [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final n in names)
          ChoiceChip(
              label: Text(n),
              selected: n == ex,
              onSelected: (_) => setState(() {
                    exercise = n;
                    machine = 'all';
                  })),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Pictogram(kind: pictogramFor(c.tryExercise(ex), ex), size: 58),
        const SizedBox(width: 12),
        Expanded(child: Text(ex, style: display(context, 26))),
      ]),
      if (machines.length > 1) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [
          for (final x in ['all', ...machines])
            ChoiceChip(
                label: Text(x == 'all' ? 'Alle Geräte' : 'Gerät $x'), selected: m == x, onSelected: (_) => setState(() => machine = x)),
        ]),
      ],
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${fmtKg(last.weight)} kg', style: display(context, 34, color: AppColors.red)),
            Text('Top-Gewicht, ${last.weight >= first.weight ? '+' : ''}${fmtKg(last.weight - first.weight)} kg in ${points.length} Einheiten',
                style: TextStyle(fontSize: 13, color: col.mute)),
          ]),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fmtKg(best.roundToDouble()), style: display(context, 34)),
            Text('bestes 1RM, geschätzt', style: TextStyle(fontSize: 13, color: col.mute)),
          ]),
        ),
      ]),
      if (points.length >= 2)
        SizedBox(
            height: 200,
            child: CustomPaint(
                painter: _LineChart([for (final p in points) p.log.topSet.weight], points.first.date, points.last.date, col),
                size: Size.infinite)),
      SectionTitle('Alle Sätze', trailing: 'letzte ${math.min(8, rows.length)} Einheiten'),
      for (final x in rows.reversed.take(8))
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: col.line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(dayLabel(x.date), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              DayTag(x.day),
              const Spacer(),
              MachineBadge(x.log.machine),
              const SizedBox(width: 6),
              Text(kg(x.log.volume), style: TextStyle(fontSize: 13, color: col.mute)),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in x.log.sets)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: col.soft, borderRadius: BorderRadius.circular(8)),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${s.reps} × ${fmtKg(s.weight)}', style: display(context, 17, weight: FontWeight.w600)),
                    TextSpan(text: ' kg', style: TextStyle(fontSize: 11, color: col.mute)),
                  ])),
                ),
            ]),
            if (x.log.note.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(x.log.note, style: TextStyle(fontSize: 12, color: col.mute))),
          ]),
        ),
    ];
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
  _LineChart(this.values, this.from, this.to, this.col);
  final List<double> values;
  final DateTime from, to;
  final AppColors col;

  @override
  void paint(Canvas canvas, Size size) {
    const l = 34.0, r = 14.0, t = 16.0, b = 22.0;
    final lo = (values.reduce(math.min) * .95).floorToDouble(), hi = (values.reduce(math.max) * 1.03).ceilToDouble();
    double x(int i) => l + i * (size.width - l - r) / (values.length - 1);
    double y(double v) => t + (hi - v) * (size.height - t - b) / (hi - lo == 0 ? 1 : hi - lo);
    for (final v in [lo, (lo + hi) / 2, hi]) {
      canvas.drawLine(Offset(l, y(v)), Offset(size.width - r, y(v)), Paint()..color = col.line);
      final tp = _label('${v.round()}', col.mute);
      tp.paint(canvas, Offset(l - 6 - tp.width, y(v) - tp.height / 2));
    }
    final line = Path(), area = Path()..moveTo(x(0), size.height - b);
    for (var i = 0; i < values.length; i++) {
      final p = Offset(x(i), y(values[i]));
      i == 0 ? line.moveTo(p.dx, p.dy) : line.lineTo(p.dx, p.dy);
      area.lineTo(p.dx, p.dy);
    }
    area
      ..lineTo(x(values.length - 1), size.height - b)
      ..close();
    canvas.drawPath(area, Paint()..color = AppColors.red.withValues(alpha: .14));
    canvas.drawPath(
        line,
        Paint()
          ..color = AppColors.red
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(Offset(x(i), y(values[i])), i == values.length - 1 ? 5 : 3, Paint()..color = AppColors.red);
    }
    _label(dayLabel(from), col.mute).paint(canvas, Offset(l, size.height - 14));
    final e = _label(dayLabel(to), col.mute);
    e.paint(canvas, Offset(size.width - r - e.width, size.height - 14));
  }

  @override
  bool shouldRepaint(_LineChart o) => true;
}
