import 'package:material_ui/material_ui.dart';

import '../logic/muscles.dart';

/// Farben der Stufen 0 (nicht beansprucht) bis 4 (sehr stark).
const muscleColors = [Color(0xFFD8D0C5), Color(0xFFF6C7BF), Color(0xFFEE8F80), Color(0xFFDE4636), Color(0xFFA31F15)];

/// Figur von vorn und hinten, Muskeln gefärbt nach Beanspruchung.
class MuscleMap extends StatelessWidget {
  const MuscleMap({super.key, required this.load, this.figureWidth = 118, this.labels = true});
  final Map<Muscle, double> load;
  final double figureWidth;
  final bool labels;

  @override
  Widget build(BuildContext context) {
    Widget side(bool front) => Column(mainAxisSize: MainAxisSize.min, children: [
          BodyFigure(front: front, load: load, width: figureWidth),
          if (labels) ...[
            const SizedBox(height: 2),
            Text(front ? 'Vorne' : 'Hinten', style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
          ],
        ]);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [side(true), SizedBox(width: figureWidth / 16), side(false)]);
  }
}

/// Legende „wenig … stark“.
class MuscleLegend extends StatelessWidget {
  const MuscleLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final st = TextStyle(fontSize: 11, color: Theme.of(context).hintColor);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('wenig', style: st),
      for (final c in muscleColors.skip(1))
        Container(
            width: 18, height: 8, margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
      Text('stark', style: st),
    ]);
  }
}

class BodyFigure extends StatelessWidget {
  const BodyFigure({super.key, required this.front, required this.load, required this.width});
  final bool front;
  final Map<Muscle, double> load;
  final double width;

  @override
  Widget build(BuildContext context) {
    final act = [
      for (final e in load.entries)
        if (loadLevel(e.value) > 0 && (front ? _front : _back).containsKey(e.key)) e.key.label
    ];
    return Semantics(
      label: '${front ? 'Vorderseite' : 'Rückseite'}: ${act.isEmpty ? 'nichts beansprucht' : act.join(', ')}',
      child: CustomPaint(size: Size(width, width * 440 / 200), painter: _BodyPainter(front, load)),
    );
  }
}

class _BodyPainter extends CustomPainter {
  _BodyPainter(this.front, this.load);
  final bool front;
  final Map<Muscle, double> load;

  static final _cache = <String, Path>{};
  static Path _p(String d) => _cache[d] ??= parseSvgPath(d);

  static final Path _silhouette = () {
    const pts = [Offset(90, 62), Offset(88, 80), Offset(72, 86), Offset(58, 90), Offset(47, 96), Offset(41, 110), Offset(40, 124), Offset(37, 150), Offset(35, 174), Offset(31, 204), Offset(28, 232), Offset(23, 248), Offset(24, 266), Offset(31, 272), Offset(36, 262), Offset(38, 246), Offset(41, 232), Offset(46, 204), Offset(51, 178), Offset(55, 152), Offset(60, 128), Offset(63, 150), Offset(67, 180), Offset(64, 206), Offset(59, 240), Offset(61, 290), Offset(66, 316), Offset(63, 346), Offset(67, 382), Offset(72, 410), Offset(64, 426), Offset(70, 432), Offset(90, 432), Offset(89, 410), Offset(91, 372), Offset(93, 334), Offset(92, 314), Offset(96, 262), Offset(100, 238)];
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final o in pts.skip(1)) {
      p.lineTo(o.dx, o.dy);
    }
    for (final o in pts.reversed) {
      p.lineTo(200 - o.dx, o.dy);
    }
    return p..close();
  }();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 200);
    final skin = Paint()..color = const Color(0xFFECE7E0);
    final edge = Paint()
      ..color = const Color(0xFFCFC7BC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(_silhouette, skin);
    canvas.drawPath(_silhouette, edge);
    final head = Rect.fromCenter(center: const Offset(100, 36), width: 40, height: 50);
    canvas.drawOval(head, skin);
    canvas.drawOval(head, edge);
    final gap = Paint()
      ..color = const Color(0xFFFBF9F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round;
    final muscles = front ? _front : _back;
    for (final mirror in [false, true]) {
      canvas.save();
      if (mirror) {
        canvas.translate(200, 0);
        canvas.scale(-1, 1);
      }
      for (final e in muscles.entries) {
        final fill = Paint()..color = muscleColors[loadLevel(load[e.key] ?? 0)];
        for (final d in e.value) {
          final path = _p(d);
          canvas.drawPath(path, fill);
          canvas.drawPath(path, gap);
        }
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BodyPainter old) => old.front != front || old.load != load;
}

/// Liest die einfachen Pfade unten (absolute M, L, C, Z).
Path parseSvgPath(String d) {
  final p = Path();
  final tok = RegExp(r'[MLCZ]|-?\d+(?:\.\d+)?').allMatches(d).map((m) => m[0]!).toList();
  var i = 0;
  double n() => double.parse(tok[i++]);
  var cmd = 'M';
  while (i < tok.length) {
    final t = tok[i];
    if (RegExp('[MLCZ]').hasMatch(t)) {
      cmd = t;
      i++;
      if (cmd == 'Z') {
        p.close();
        continue;
      }
    }
    switch (cmd) {
      case 'M':
        p.moveTo(n(), n());
        cmd = 'L';
      case 'L':
        p.lineTo(n(), n());
      case 'C':
        p.cubicTo(n(), n(), n(), n(), n(), n());
    }
  }
  return p;
}

// Linke Körperhälfte, Mitte bei x = 100; die rechte wird gespiegelt.
const Map<Muscle, List<String>> _front = {
    Muscle.traps: ['M89,78 C80,84 70,88 60,90 L67,97 C77,93 88,92 97,92 L95,80Z'],
    Muscle.shoulders: ['M58,91 C48,93 42,101 41,115 C41,124 44,130 47,134 C52,124 58,112 66,100 C64,95 62,92 58,91Z'],
    Muscle.chest: ['M67,99 C62,105 59,114 59,124 C63,134 75,138 87,136 C94,134 98,130 98,124 L98,96 C88,92 77,93 67,99Z'],
    Muscle.biceps: ['M46,137 C42,147 40,160 42,172 C46,176 50,174 52,168 C55,156 56,144 55,132 C51,130 48,132 46,137Z'],
    Muscle.forearms: ['M41,179 C36,191 32,207 31,226 L39,229 C42,213 46,197 50,181 C47,177 44,177 41,179Z'],
    Muscle.abs: ['M87,141 L98,141 L98,157 L87,157 C86,151 86,146 87,141Z', 'M87,160 L98,160 L98,176 L87,176Z', 'M87,179 L98,179 L98,195 L88,195Z', 'M88,198 L98,198 L98,228 C94,224 91,214 88,198Z'],
    Muscle.obliques: ['M65,140 C67,160 69,180 71,198 C76,205 81,209 85,213 L84,143 C78,140 71,138 65,140Z'],
    Muscle.quads: ['M65,214 C59,240 59,270 65,300 C71,308 80,308 85,298 C91,280 95,256 96,238 C88,227 77,219 65,214Z', 'M85,284 C91,286 94,294 92,305 C86,307 82,300 85,284Z'],
    Muscle.adductors: ['M97,240 C96,256 94,270 90,280 C95,270 99,256 99,240Z'],
    Muscle.calves: ['M68,322 C64,340 66,366 72,394 L78,394 C78,368 76,342 74,322Z', 'M84,320 C90,336 90,360 86,388 L82,388 C82,362 81,340 84,320Z'],
  };

const Map<Muscle, List<String>> _back = {
    Muscle.traps: ['M93,66 C91,77 79,85 61,90 C71,96 81,106 88,124 C92,140 96,152 99,162 L99,66Z'],
    Muscle.shoulders: ['M58,91 C48,93 42,101 41,115 C41,124 44,130 47,134 C52,124 58,112 64,101 C63,95 61,92 58,91Z'],
    Muscle.upperback: ['M66,101 C72,105 78,111 84,121 C76,119 68,117 62,117 C62,111 63,105 66,101Z'],
    Muscle.triceps: ['M46,135 C42,147 40,160 42,172 C46,176 52,172 54,166 C56,154 56,142 55,130 C52,128 48,130 46,135Z'],
    Muscle.forearms: ['M41,179 C36,191 32,207 31,226 L39,229 C42,213 46,197 50,181 C47,177 44,177 41,179Z'],
    Muscle.lats: ['M62,121 C62,142 66,166 74,190 C82,196 92,194 97,186 L97,168 C91,153 86,138 81,123 C75,117 67,117 62,121Z'],
    Muscle.lowerback: ['M89,166 C87,182 87,197 89,210 L98,214 L98,168Z'],
    Muscle.glutes: ['M66,207 C60,221 60,240 68,252 C78,260 90,258 98,250 L98,216 C88,209 76,205 66,207Z'],
    Muscle.hamstrings: ['M64,259 C62,282 64,300 70,312 C78,316 86,316 90,312 C94,296 96,276 96,257 C86,263 74,263 64,259Z'],
    Muscle.calves: ['M66,322 C60,337 62,357 70,371 C74,367 78,355 80,341 C78,331 72,323 66,322Z', 'M82,322 C88,330 92,346 88,366 C84,371 80,361 80,347 C80,337 80,329 82,322Z'],
  };
