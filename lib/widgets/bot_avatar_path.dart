import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Parses the SVG path data used by the bot-avatar body outlines into a
/// Flutter [Path].
///
/// Handles the command set those outlines actually use: M L H V C Q A Z, in
/// absolute and relative form. SVG elliptical arcs (A) are converted to cubic
/// beziers, since Flutter's Path has no arc-by-endpoint primitive.
class SvgPathParser {
  SvgPathParser(this.src);

  final String src;
  final Path _p = Path();
  int _i = 0;

  double _cx = 0;
  double _cy = 0;
  double _sx = 0;
  double _sy = 0;
  String _cmd = '';

  static final RegExp _numRe =
      RegExp(r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?');

  Path parse() {
    while (true) {
      _skipSep();
      if (_i >= src.length) break;
      final String c = src[_i];
      if (_isCmd(c)) {
        _cmd = c;
        _i++;
        _exec(c);
      } else {
        if (_cmd.isEmpty) {
          _i++;
          continue;
        }
        final int before = _i;
        _exec(_cmd, implicit: true);
        if (_i == before) break; // no progress -> stop, avoid a hang
      }
    }
    return _p;
  }

  bool _isCmd(String c) => 'MmLlHhVvCcQqAaZz'.contains(c) && c.length == 1;

  void _skipSep() {
    while (_i < src.length) {
      final String c = src[_i];
      if (c == ' ' || c == ',' || c == '\n' || c == '\r' || c == '\t') {
        _i++;
      } else {
        break;
      }
    }
  }

  double? _num() {
    _skipSep();
    final Match? m = _numRe.matchAsPrefix(src, _i);
    if (m == null) return null;
    _i = m.end;
    return double.tryParse(m.group(0)!);
  }

  double _req() => _num() ?? 0;

  void _exec(String c, {bool implicit = false}) {
    switch (c) {
      case 'M':
      case 'm':
        final bool rel = c == 'm';
        final double x = _req(), y = _req();
        final double nx = rel ? _cx + x : x;
        final double ny = rel ? _cy + y : y;
        _p.moveTo(nx, ny);
        _cx = _sx = nx;
        _cy = _sy = ny;
        // Further coordinate pairs after a move are implicit lineTo.
        _cmd = rel ? 'l' : 'L';
        break;
      case 'L':
      case 'l':
        final bool rel = c == 'l';
        final double x = _req(), y = _req();
        _cx = rel ? _cx + x : x;
        _cy = rel ? _cy + y : y;
        _p.lineTo(_cx, _cy);
        break;
      case 'H':
      case 'h':
        final double x = _req();
        _cx = c == 'h' ? _cx + x : x;
        _p.lineTo(_cx, _cy);
        break;
      case 'V':
      case 'v':
        final double y = _req();
        _cy = c == 'v' ? _cy + y : y;
        _p.lineTo(_cx, _cy);
        break;
      case 'C':
      case 'c':
        _cubic(c == 'c');
        break;
      case 'Q':
      case 'q':
        _quad(c == 'q');
        break;
      case 'A':
      case 'a':
        _arc(c == 'a');
        break;
      case 'Z':
      case 'z':
        _p.close();
        _cx = _sx;
        _cy = _sy;
        break;
    }
  }

  void _cubic(bool rel) {
    final double x1 = _req(), y1 = _req();
    final double x2 = _req(), y2 = _req();
    final double x = _req(), y = _req();
    final double c1x = rel ? _cx + x1 : x1;
    final double c1y = rel ? _cy + y1 : y1;
    final double c2x = rel ? _cx + x2 : x2;
    final double c2y = rel ? _cy + y2 : y2;
    final double ex = rel ? _cx + x : x;
    final double ey = rel ? _cy + y : y;
    _p.cubicTo(c1x, c1y, c2x, c2y, ex, ey);
    _cx = ex;
    _cy = ey;
  }

  void _quad(bool rel) {
    final double x1 = _req(), y1 = _req();
    final double x = _req(), y = _req();
    final double qx = rel ? _cx + x1 : x1;
    final double qy = rel ? _cy + y1 : y1;
    final double ex = rel ? _cx + x : x;
    final double ey = rel ? _cy + y : y;
    _p.quadraticBezierTo(qx, qy, ex, ey);
    _cx = ex;
    _cy = ey;
  }

  double _angle(double ux, double uy, double vx, double vy) {
    final double dot = ux * vx + uy * vy;
    final double len = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
    if (len == 0) return 0;
    double a = math.acos((dot / len).clamp(-1.0, 1.0));
    if (ux * vy - uy * vx < 0) a = -a;
    return a;
  }

  void _arc(bool rel) {
    final double rx = _req().abs();
    final double ry = _req().abs();
    final double rotDeg = _req();
    final int largeArc = _req() != 0 ? 1 : 0;
    final int sweep = _req() != 0 ? 1 : 0;
    final double ex0 = _req(), ey0 = _req();
    final double ex = rel ? _cx + ex0 : ex0;
    final double ey = rel ? _cy + ey0 : ey0;

    // Degenerate radii or a zero-length arc is just a line.
    if (rx == 0 || ry == 0 || (_cx == ex && _cy == ey)) {
      _p.lineTo(ex, ey);
      _cx = ex;
      _cy = ey;
      return;
    }

    final double phi = rotDeg * math.pi / 180.0;
    final double cosPhi = math.cos(phi);
    final double sinPhi = math.sin(phi);

    final double dx2 = (_cx - ex) / 2.0;
    final double dy2 = (_cy - ey) / 2.0;
    final double x1p = cosPhi * dx2 + sinPhi * dy2;
    final double y1p = -sinPhi * dx2 + cosPhi * dy2;

    double rx2 = rx * rx;
    double ry2 = ry * ry;
    final double x1p2 = x1p * x1p;
    final double y1p2 = y1p * y1p;

    // Scale up radii that are too small to span the endpoints.
    final double lambda = x1p2 / rx2 + y1p2 / ry2;
    double rxs = rx, rys = ry;
    if (lambda > 1) {
      final double s = math.sqrt(lambda);
      rxs = rx * s;
      rys = ry * s;
      rx2 = rxs * rxs;
      ry2 = rys * rys;
    }

    double num = rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2;
    if (num < 0) num = 0;
    final double den = rx2 * y1p2 + ry2 * x1p2;
    double coef = den == 0 ? 0 : math.sqrt(num / den);
    if (largeArc == sweep) coef = -coef;

    final double cxp = coef * (rxs * y1p / rys);
    final double cyp = coef * -(rys * x1p / rxs);

    final double cx = cosPhi * cxp - sinPhi * cyp + (_cx + ex) / 2.0;
    final double cy = sinPhi * cxp + cosPhi * cyp + (_cy + ey) / 2.0;

    final double theta1 = _angle(1, 0, (x1p - cxp) / rxs, (y1p - cyp) / rys);
    double dTheta = _angle(
      (x1p - cxp) / rxs,
      (y1p - cyp) / rys,
      (-x1p - cxp) / rxs,
      (-y1p - cyp) / rys,
    );
    if (sweep == 0 && dTheta > 0) {
      dTheta -= 2 * math.pi;
    } else if (sweep == 1 && dTheta < 0) {
      dTheta += 2 * math.pi;
    }

    // Split into segments of at most 90 degrees for a faithful bezier fit.
    final int segs = (dTheta.abs() / (math.pi / 2)).ceil().clamp(1, 8);
    final double delta = dTheta / segs;
    final double t = 4.0 / 3.0 * math.tan(delta / 4.0);

    double a1 = theta1;
    double startX = _cx, startY = _cy;
    for (int s = 0; s < segs; s++) {
      final double a2 = a1 + delta;
      final double cosA1 = math.cos(a1), sinA1 = math.sin(a1);
      final double cosA2 = math.cos(a2), sinA2 = math.sin(a2);

      final double e1x = cx + cosPhi * rxs * cosA1 - sinPhi * rys * sinA1;
      final double e1y = cy + sinPhi * rxs * cosA1 + cosPhi * rys * sinA1;
      final double e2x = cx + cosPhi * rxs * cosA2 - sinPhi * rys * sinA2;
      final double e2y = cy + sinPhi * rxs * cosA2 + cosPhi * rys * sinA2;

      final double d1x = -rxs * cosPhi * sinA1 - rys * sinPhi * cosA1;
      final double d1y = -rxs * sinPhi * sinA1 + rys * cosPhi * cosA1;
      final double d2x = -rxs * cosPhi * sinA2 - rys * sinPhi * cosA2;
      final double d2y = -rxs * sinPhi * sinA2 + rys * cosPhi * cosA2;

      if (s == 0) {
        startX = e1x;
        startY = e1y;
      }
      _p.cubicTo(
        startX + t * d1x,
        startY + t * d1y,
        e2x - t * d2x,
        e2y - t * d2y,
        e2x,
        e2y,
      );
      startX = e2x;
      startY = e2y;
      a1 = a2;
    }

    _cx = ex;
    _cy = ey;
  }
}

/// Parses [data] and scales/centres it from the 100x100 design box into
/// a [size] square.
Path botAvatarPath(String data, Size size) {
  final Path raw = SvgPathParser(data).parse();
  final double sx = size.width / 100.0;
  final double sy = size.height / 100.0;
  // 100x100 design box -> target square (uniform when size is square).
  final Float64List m = Float64List.fromList(<double>[
    sx, 0, 0, 0,
    0, sy, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
  ]);
  return raw.transform(m);
}
