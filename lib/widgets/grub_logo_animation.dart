import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The Grub loading animation:
/// whole G pops in → leaves sprout → cart races in from the left, knocks the
/// bottom of the G off and takes its place → r, u, b drop in → swoosh draws →
/// tagline rises. Built from layer images in assets/branding/anim so it stays
/// sharp on every screen. Same timeline as the logo video.
class GrubLogoAnimation extends StatefulWidget {
  final VoidCallback? onFinished;
  final bool loop;
  /// Returning users: start near the end (logo assembles in under a second).
  final bool quick;
  const GrubLogoAnimation({super.key, this.onFinished, this.loop = false, this.quick = false});

  static const duration = Duration(milliseconds: 4300);

  @override
  State<GrubLogoAnimation> createState() => _GrubLogoAnimationState();
}

class _Layer {
  final String name;
  final double l, t, w, h, cx, cy, bottom, x0, x1;
  const _Layer(this.name, this.l, this.t, this.w, this.h, this.cx, this.cy, this.bottom, this.x0, this.x1);
  String get asset => 'assets/branding/anim/$name.png';
}

// positions in "logo space" (1152 × 768), exported with the layer images
const _gFull = _Layer('Gfull', 162.8, 177.8, 348, 344, 331.3, 344.7, 519.8, 163.5, 509.2);
const _g = _Layer('G', 33.8, 172.5, 485, 351, 364.2, 298.6, 497.2, 163.5, 508.5);
const _piece = _Layer('piece2', 163.5, 305.2, 277, 215, 268.7, 432.0, 519.8, 163.5, 439.5);
const _leaves = _Layer('leaves', 228.8, 47.2, 230, 142, 359.0, 124.2, 187.5, 232.5, 453.0);
const _cart = _Layer('cart', 30.8, 189.0, 453, 332, 255.2, 405.6, 518.2, 34.5, 432.8);
const _r = _Layer('r', 510.0, 270.8, 147, 229, 565.9, 365.1, 487.5, 516.0, 653.2);
const _u = _Layer('u', 657.0, 272.2, 196, 226, 753.6, 383.9, 489.8, 660.0, 848.2);
const _b = _Layer('b', 853.5, 197.2, 260, 313, 965.8, 363.8, 490.5, 858.8, 1109.2);
const _swoosh = _Layer('swoosh', 288.8, 495.0, 720, 62, 651.7, 519.6, 553.5, 291.8, 1005.8);
const _tag = _Layer('tag', 59.2, 563.2, 1066, 205, 579.7, 586.4, 606.0, 63.0, 1089.0);
const _all = [_gFull, _g, _piece, _leaves, _cart, _r, _u, _b, _swoosh, _tag];

const _logoW = 1152.0, _logoH = 768.0;
const _tHit = 1.38;
const _cartHitDx = -267.0;
const _gPivot = Offset(336, 352.5);

double _clamp(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);
double _prog(double t, double s, double d) => _clamp((t - s) / d);
double _outBack(double x, [double k = 1.70158]) {
  final y = x - 1;
  return 1 + (k + 1) * y * y * y + k * y * y;
}

double _out(double x) => 1 - math.pow(1 - x, 3).toDouble();
double _in(double x) => math.pow(x, 2.2).toDouble();
double _io(double x) => 3 * x * x - 2 * x * x * x;

class _GrubLogoAnimationState extends State<GrubLogoAnimation> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: GrubLogoAnimation.duration);
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_ready) _precache();
  }

  Future<void> _precache() async {
    await Future.wait(_all.map((l) => precacheImage(AssetImage(l.asset), context)));
    if (!mounted) return;
    setState(() => _ready = true);
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        widget.onFinished?.call();
        if (widget.loop) {
          Future.delayed(const Duration(milliseconds: 900), () {
            if (mounted) _c.forward(from: 0);
          });
        }
      }
    });
    _c.forward(from: widget.quick ? 0.8 : 0.0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.expand();
    return LayoutBuilder(builder: (context, box) {
      return AnimatedBuilder(
        animation: _c,
        builder: (_, __) => _frame(_c.value * GrubLogoAnimation.duration.inMilliseconds / 1000, box.biggest),
      );
    });
  }

  // ------------------------------------------------------------- one frame
  Widget _frame(double t, Size view) {
    final children = <Widget>[];

    // G and leaves pop in
    final g = _prog(t, 0.12, 0.55);
    final gs = g > 0 ? _outBack(g, 2.0) : 0.0;
    var shake = 0.0;
    if (t > _tHit) {
      final u = t - _tHit;
      shake = 10.5 * math.exp(-u / 0.09) * math.sin(2 * math.pi * 16 * u);
    }
    if (t < _tHit) {
      children.add(_place(_gFull, scale: gs, pivot: _gPivot, opacity: _clamp(g * 4)));
    } else {
      children.add(_place(_g, dx: shake, pivot: _gPivot));
    }
    final lf = _prog(t, 0.5, 0.45);
    if (lf > 0) {
      final wig = 10 * math.exp(-lf * 4) * math.sin(lf * 14);
      children.add(_place(_leaves, dx: shake, scale: _outBack(lf, 2.4), rot: wig, pivot: const Offset(339, 178.5), opacity: _clamp(lf * 4)));
    }

    // bottom of the G gets knocked off
    if (t >= _tHit) {
      final u = t - _tHit;
      children.add(_place(_piece,
          dx: 862 * u,
          dy: -487 * u + 0.5 * 3450 * u * u,
          rot: -420 * u,
          pivot: Offset(_piece.cx, _piece.cy),
          opacity: _clamp(1 - u / 0.55)));
    }

    // impact sparks
    if (t >= _tHit && t < _tHit + 0.45) {
      final u = (t - _tHit) / 0.45;
      children.add(Positioned.fill(child: CustomPaint(painter: _Sparks(u))));
    }

    // cart races in from the left
    final cdx = _cartDx(t);
    if (cdx != null) {
      if (t < _tHit + 0.1) {
        for (final (k, a) in [(3, 0.08), (2, 0.15), (1, 0.28)]) {
          children.add(_place(_cart, dx: cdx - 52.5 * k, opacity: a));
        }
      }
      var tilt = 0.0;
      if (t < _tHit) {
        tilt = -4 * _prog(t, 0.95, 0.2);
      } else if (t < _tHit + 0.5) {
        final u = t - _tHit;
        tilt = 6 * math.exp(-u / 0.12) * math.cos(2 * math.pi * 3 * u);
      }
      children.add(_place(_cart, dx: cdx, rot: tilt, pivot: const Offset(300, 495)));
    }

    // r, u, b drop in one by one
    final letters = [_r, _u, _b];
    for (var i = 0; i < 3; i++) {
      final p = _prog(t, 1.9 + i * 0.2, 0.5);
      if (p <= 0) continue;
      final l = letters[i];
      children.add(_place(l,
          dy: -67.5 * (1 - _out(p)),
          scale: 0.35 + 0.65 * _outBack(p, 2.2),
          pivot: Offset(l.cx, l.bottom),
          opacity: _clamp(p * 3)));
    }

    // swoosh wipes in from the left
    final sp = _io(_prog(t, 2.75, 0.6));
    if (sp > 0) {
      children.add(Positioned(
        left: _swoosh.l,
        top: _swoosh.t,
        width: _swoosh.w,
        height: _swoosh.h,
        child: ClipRect(
          child: Align(alignment: Alignment.centerLeft, widthFactor: sp, child: Image.asset(_swoosh.asset, width: _swoosh.w, height: _swoosh.h, fit: BoxFit.fill)),
        ),
      ));
    }

    // tagline rises
    final tp = _prog(t, 3.25, 0.5);
    if (tp > 0) children.add(_place(_tag, dy: 19.5 * (1 - _out(tp)), opacity: _out(tp)));

    // camera: close on the G first, then pull back to the whole logo
    final k = _io(_prog(t, 1.75, 0.9));
    const gC = Offset(322.5, 337.5), fullC = Offset(574, 328);
    const gW = 735.0, fullW = 1208.0;
    final cx = gC.dx + (fullC.dx - gC.dx) * k;
    final cy = gC.dy + (fullC.dy - gC.dy) * k;
    final w = gW + (fullW - gW) * k;
    final s = math.min(view.width, view.height * 1.4) / w;
    final m = Matrix4.identity()
      ..translateByDouble(view.width / 2 - cx * s, view.height / 2 - cy * s, 0, 1)
      ..scaleByDouble(s, s, 1, 1);

    return ClipRect(
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: 0,
          top: 0,
          width: _logoW,
          height: _logoH,
          child: Transform(transform: m, child: Stack(clipBehavior: Clip.none, children: children)),
        ),
      ]),
    );
  }

  double? _cartDx(double t) {
    if (t < 0.95) return null;
    if (t < _tHit) return -862.5 + (_cartHitDx + 862.5) * _in(_prog(t, 0.95, _tHit - 0.95));
    if (t < _tHit + 0.2) return _cartHitDx + (18.7 - _cartHitDx) * _out(_prog(t, _tHit, 0.2));
    final u = t - (_tHit + 0.2);
    return 18.7 * math.exp(-u / 0.09) * math.cos(2 * math.pi * 3.2 * u);
  }

  /// Places a layer in logo space with translate / scale / rotate around a pivot.
  Widget _place(_Layer l, {double dx = 0, double dy = 0, double scale = 1, double rot = 0, Offset? pivot, double opacity = 1}) {
    if (opacity <= 0.003 || scale <= 0.001) return const SizedBox.shrink();
    final p = pivot ?? Offset(l.cx, l.cy);
    final m = Matrix4.identity()
      ..translateByDouble(p.dx + dx, p.dy + dy, 0, 1)
      ..rotateZ(rot * math.pi / 180)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-p.dx, -p.dy, 0, 1);
    Widget img = Image.asset(l.asset, width: l.w, height: l.h, fit: BoxFit.fill, filterQuality: FilterQuality.medium, gaplessPlayback: true);
    if (opacity < 1) img = Opacity(opacity: opacity, child: img);
    return Positioned.fill(
      child: Transform(
        transform: m,
        child: Stack(clipBehavior: Clip.none, children: [Positioned(left: l.l, top: l.t, width: l.w, height: l.h, child: img)]),
      ),
    );
  }
}

class _Sparks extends CustomPainter {
  final double u; // 0..1
  _Sparks(this.u);
  @override
  void paint(Canvas canvas, Size size) {
    for (var k = 0; k < 9; k++) {
      final ang = (-150 + k * 32) * math.pi / 180;
      final dist = 30 + 234 * _out(u);
      final x = 187.5 + math.cos(ang) * dist;
      final y = 375 + math.sin(ang) * dist;
      final r = 7.5 * (1 - u) + 1;
      final c = (k.isOdd ? const Color(0xFFFF8A1C) : const Color(0xFF7CC814)).withValues(alpha: 1 - u);
      canvas.drawCircle(Offset(x, y), r, Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(covariant _Sparks old) => old.u != u;
}
