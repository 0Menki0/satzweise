import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import 'theme.dart';

enum _K { body, equip, plate }

sealed class _Op {}

class _Line extends _Op {
  _Line(this.a, this.b, this.k);
  final Offset a, b;
  final _K k;
}

class _Head extends _Op {
  _Head(this.c);
  final Offset c;
}

class _Ring extends _Op {
  _Ring(this.c, this.r, this.k);
  final Offset c;
  final double r;
  final _K k;
}

class _Curve extends _Op {
  _Curve(this.a, this.ctrl, this.b);
  final Offset a, ctrl, b;
}

_Line _l(double a, double b, double c, double d, [_K k = _K.body]) => _Line(Offset(a, b), Offset(c, d), k);
_Head _hd(double x, double y) => _Head(Offset(x, y));
_Line _pl(double x, double y) => _l(x, y - 4.5, x, y + 4.5, _K.plate);
List<_Op> _db(double x, double y) =>
    [_l(x - 3, y, x + 3, y, _K.equip), _l(x - 3, y - 2.5, x - 3, y + 2.5, _K.plate), _l(x + 3, y - 2.5, x + 3, y + 2.5, _K.plate)];
List<_Op> _legs(double x, double y) => [_l(x, y, x - 4, y + 12), _l(x, y, x + 4, y + 12)];
_Curve _q(double ax, double ay, double cx, double cy, double bx, double by) =>
    _Curve(Offset(ax, ay), Offset(cx, cy), Offset(bx, by));
_Ring _ring(double x, double y, double r, [_K k = _K.equip]) => _Ring(Offset(x, y), r, k);

const _eq = _K.equip;

/// Strichfiguren je Bewegungsart, gezeichnet in einem 48×48-Raster.
final Map<String, List<_Op>> _pictograms = {
  'bench': [_l(8, 36, 38, 36, _eq), _l(12, 36, 12, 42, _eq), _l(34, 36, 34, 42, _eq), _l(10, 16, 34, 16, _eq), _pl(12, 16), _pl(32, 16),
    _hd(10, 31), _l(14, 32, 30, 32), _l(30, 32, 36, 34), _l(36, 34, 38, 42), _l(17, 31, 19, 17), _l(23, 31, 25, 17)],
  'squat': [_l(10, 14, 38, 14, _eq), _pl(12, 14), _pl(36, 14), _hd(24, 8), _l(24, 12, 20, 25), _l(20, 25, 31, 27), _l(31, 27, 29, 40),
    _l(29, 40, 33, 40), _l(23, 14, 29, 16)],
  'dead': [_l(8, 36, 36, 36, _eq), _pl(11, 36), _pl(33, 36), _hd(14, 13), _l(17, 15, 30, 24), _l(30, 24, 27, 31), _l(27, 31, 30, 42),
    _l(21, 17, 22, 35)],
  'row': [_l(26, 31, 44, 31, _eq), _l(28, 31, 28, 40, _eq), _l(42, 31, 42, 40, _eq), _hd(10, 17), _l(14, 19, 30, 21), _l(30, 21, 33, 30),
    _l(33, 30, 41, 30), _l(30, 21, 24, 42), _l(19, 20, 19, 30), ..._db(19, 32)],
  'pulldown': [_l(12, 10, 36, 10, _eq), _l(24, 10, 24, 3, _eq), _l(16, 36, 32, 36, _eq), _hd(24, 18), _l(24, 22, 24, 34),
    _l(24, 34, 33, 34), _l(33, 34, 33, 43), _l(24, 23, 15, 11), _l(24, 23, 33, 11)],
  'pullup': [_l(6, 7, 42, 7, _eq), _l(17, 7, 22, 21), _l(31, 7, 26, 21), _hd(24, 15), _l(24, 20, 24, 32), _l(24, 32, 21, 43), _l(24, 32, 28, 42)],
  'press': [_l(9, 8, 39, 8, _eq), _pl(11, 8), _pl(37, 8), _hd(24, 14), _l(24, 18, 24, 30), ..._legs(24, 30), _l(24, 19, 17, 9), _l(24, 19, 31, 9)],
  'curl': [_hd(21, 8), _l(21, 12, 21, 28), ..._legs(21, 28), _l(21, 14, 22, 23), _l(22, 23, 31, 17), ..._db(33, 17)],
  'push': [_l(30, 4, 40, 4, _eq), _l(36, 4, 31, 27, _eq), _hd(20, 8), _l(20, 12, 20, 28), ..._legs(20, 28), _l(20, 14, 23, 22), _l(23, 22, 30, 28)],
  'legpress': [_l(4, 14, 13, 37, _eq), _l(13, 37, 26, 37, _eq), _l(38, 12, 42, 32, _K.plate), _hd(9, 15), _l(10, 20, 15, 33),
    _l(15, 33, 25, 20), _l(25, 20, 38, 22), _l(12, 24, 20, 33)],
  'legext': [_l(10, 33, 28, 33, _eq), _l(10, 33, 7, 16, _eq), _hd(13, 11), _l(13, 15, 14, 31), _l(14, 31, 28, 31), _l(28, 31, 40, 28),
    _l(14, 18, 22, 29), _ring(40, 30, 2.6)],
  'legcurl': [_l(4, 31, 34, 31, _eq), _l(8, 31, 8, 40, _eq), _l(30, 31, 30, 40, _eq), _hd(7, 25), _l(11, 27, 26, 27), _l(26, 27, 34, 27),
    _l(34, 27, 38, 15), _ring(38, 17, 2.6)],
  'lunge': [_hd(22, 7), _l(22, 11, 22, 25), _l(22, 25, 32, 28), _l(32, 28, 32, 41), _l(22, 25, 15, 35), _l(15, 35, 7, 38), _l(22, 13, 20, 24),
    ..._db(20, 27)],
  'calf': [_l(14, 41, 34, 41, _K.plate), _hd(24, 6), _l(24, 10, 24, 25), _l(24, 25, 23, 36), _l(24, 25, 26, 36), _l(23, 36, 26, 39),
    _l(24, 12, 19, 22), _l(24, 12, 29, 22)],
  'lateral': [_hd(24, 9), _l(24, 13, 24, 29), ..._legs(24, 29), _l(24, 15, 11, 16), _l(24, 15, 37, 16), ..._db(8, 16), ..._db(40, 16)],
  'fly': [_l(15, 32, 33, 32, _eq), _hd(24, 13), _l(24, 17, 24, 32), _l(24, 32, 32, 33), _l(32, 33, 32, 43), _q(24, 19, 14, 18, 11, 27),
    _q(24, 19, 34, 18, 37, 27), _ring(11, 28, 2), _ring(37, 28, 2)],
  'crunch': [_l(12, 3, 22, 3, _eq), _l(17, 3, 17, 21, _eq), _l(30, 40, 43, 40), _l(30, 40, 30, 28), _q(30, 28, 27, 17, 18, 21), _hd(15, 25),
    _l(20, 21, 17, 22)],
  'hip': [_l(3, 25, 14, 25, _eq), _l(5, 25, 5, 40, _eq), _hd(8, 21), _l(12, 24, 26, 19), _l(26, 19, 34, 26), _l(34, 26, 35, 39), _ring(26, 13, 4.5)],
  'dips': [_l(10, 22, 38, 22, _eq), _l(14, 22, 14, 43, _eq), _l(34, 22, 34, 43, _eq), _hd(24, 7), _l(24, 11, 24, 25), _l(24, 13, 19, 22),
    _l(24, 13, 29, 22), _l(24, 25, 21, 33), _l(21, 33, 28, 38)],
  'face': [_l(42, 8, 42, 18, _eq), _l(42, 12, 32, 12, _eq), _hd(19, 8), _l(19, 12, 19, 28), ..._legs(19, 28), _l(19, 14, 26, 9), _l(26, 9, 32, 12)],
  'pallof': [_l(42, 11, 42, 23, _eq), _l(42, 17, 33, 17, _eq), _hd(19, 8), _l(19, 12, 19, 28), ..._legs(19, 28), _l(19, 15, 33, 17)],
  'seatrow': [_l(6, 35, 22, 35, _eq), _l(40, 28, 40, 42, _eq), _l(30, 22, 42, 23, _eq), _hd(15, 13), _l(15, 17, 16, 34), _l(16, 34, 28, 32),
    _l(28, 32, 38, 38), _l(15, 20, 22, 25), _l(22, 25, 30, 22)],
};

const pictogramNames = {
  'bench': 'Bankdrücken', 'squat': 'Kniebeuge', 'dead': 'Kreuzheben', 'row': 'Rudern', 'pulldown': 'Latzug',
  'pullup': 'Klimmzug', 'press': 'Drücken über Kopf', 'curl': 'Curl', 'push': 'Trizeps am Kabel', 'legpress': 'Beinpresse',
  'legext': 'Beinstrecker', 'legcurl': 'Beinbeuger', 'lunge': 'Ausfallschritt', 'calf': 'Wadenheben', 'lateral': 'Seitheben',
  'fly': 'Butterfly', 'crunch': 'Crunch', 'hip': 'Hip Thrust', 'dips': 'Dips', 'face': 'Face Pull', 'pallof': 'Pallof',
  'seatrow': 'Rudern sitzend',
};

const _byName = {
  'Bankdrücken': 'bench', 'Schrägbankdrücken Kurzhantel': 'bench', 'Butterfly Maschine': 'fly', 'Kabelzug Crossover': 'fly',
  'Dips mit Gewicht': 'dips', 'Kreuzheben': 'dead', 'Latzug': 'pulldown', 'Rudern Kurzhantel': 'row', 'Rudern Langhantel': 'row',
  'Klimmzüge mit Gewicht': 'pullup', 'Rudern Kabel sitzend': 'seatrow', 'Kniebeuge': 'squat', 'Beinpresse': 'legpress',
  'Rumänisches Kreuzheben': 'dead', 'Beinstrecker': 'legext', 'Beinbeuger': 'legcurl', 'Ausfallschritte Kurzhantel': 'lunge',
  'Hip Thrust': 'hip', 'Wadenheben': 'calf', 'Schulterdrücken': 'press', 'Military Press': 'press', 'Seitheben': 'lateral',
  'Face Pulls': 'face', 'Reverse Butterfly': 'lateral', 'Bizepscurls': 'curl', 'Hammercurls': 'curl', 'Trizepsdrücken': 'push',
  'French Press': 'press', 'Kabel-Crunch': 'crunch', 'Pallof Press': 'pallof', 'Bauchmaschine': 'crunch',
};

const _byGroup = {
  MuscleGroup.brust: 'bench', MuscleGroup.ruecken: 'row', MuscleGroup.beine: 'squat',
  MuscleGroup.schultern: 'press', MuscleGroup.arme: 'curl', MuscleGroup.rumpf: 'crunch',
};

String pictogramFor(Exercise? e, String name) =>
    e?.pictogram ?? _byName[name] ?? (e == null ? 'press' : _byGroup[e.group]!);

class Pictogram extends StatelessWidget {
  const Pictogram({super.key, required this.kind, this.size = 44, this.dark = false});
  final String kind;
  final double size;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: dark ? Colors.white.withValues(alpha: .1) : c.soft, borderRadius: BorderRadius.circular(size * .26)),
      child: CustomPaint(
          painter: _PictoPainter(_pictograms[kind] ?? _pictograms['press']!, dark ? Colors.white : c.ink, AppColors.red)),
    );
  }
}

class _PictoPainter extends CustomPainter {
  _PictoPainter(this.ops, this.ink, this.accent);
  final List<_Op> ops;
  final Color ink, accent;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 48;
    canvas.scale(s);
    Paint p(_K k) => Paint()
      ..color = k == _K.body ? ink : accent
      ..strokeWidth = k == _K.plate ? 4.5 : 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final op in ops) {
      switch (op) {
        case _Line(:final a, :final b, :final k):
          canvas.drawLine(a, b, p(k));
        case _Head(:final c):
          canvas.drawCircle(c, 3.6, Paint()..color = ink);
        case _Ring(:final c, :final r, :final k):
          canvas.drawCircle(c, r, p(k));
        case _Curve(:final a, :final ctrl, :final b):
          canvas.drawPath(
              Path()
                ..moveTo(a.dx, a.dy)
                ..quadraticBezierTo(ctrl.dx, ctrl.dy, b.dx, b.dy),
              p(_K.body));
      }
    }
  }

  @override
  bool shouldRepaint(_PictoPainter old) => old.ops != ops || old.ink != ink;
}
