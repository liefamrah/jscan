import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';

/// Faithful vector rendition of the updated `assets/jscan_app_icon.svg`
/// (Warm Charcoal #302F2D -> #1D1D1C, Warm Yellow #F7D568, Warm Cream #F5F1E9).
class JScanLogoMark extends StatelessWidget {
  const JScanLogoMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _JScanLogoPainter()),
    );
  }
}

class _JScanLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 512.0;
    canvas.save();
    canvas.scale(s, s);

    // 1. Warm charcoal rounded app tile.
    const tileRect = Rect.fromLTWH(20, 20, 472, 472);
    final tileRRect = RRect.fromRectAndRadius(tileRect, const Radius.circular(112));
    final fieldPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment(-0.8, -0.85),
        end: Alignment(0.8, 0.85),
        colors: [AppColors.charcoalTileTop, AppColors.charcoal],
      ).createShader(const Rect.fromLTRB(54, 38, 456, 474));
    canvas.drawRRect(tileRRect, fieldPaint);

    // 2. Translucent warm yellow paper plane.
    final planePath = Path()
      ..moveTo(112, 104)
      ..lineTo(384, 72)
      ..lineTo(440, 344)
      ..lineTo(168, 440)
      ..lineTo(72, 248)
      ..close();
    final planePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.yellow.withValues(alpha: 0.18),
          AppColors.yellow.withValues(alpha: 0.015),
        ],
      ).createShader(const Rect.fromLTRB(115, 92, 400, 416));
    canvas.drawPath(planePath, planePaint);

    // 3. Four scanner corner brackets in signature warm yellow.
    final bracketPaint = Paint()
      ..color = AppColors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.square;

    final brackets = Path()
      ..moveTo(112, 194)
      ..lineTo(112, 151)
      ..cubicTo(112, 129.461, 129.461, 112, 151, 112)
      ..lineTo(194, 112)
      ..moveTo(318, 112)
      ..lineTo(361, 112)
      ..cubicTo(382.539, 112, 400, 129.461, 400, 151)
      ..lineTo(400, 194)
      ..moveTo(400, 318)
      ..lineTo(400, 361)
      ..cubicTo(400, 382.539, 382.539, 400, 361, 400)
      ..lineTo(318, 400)
      ..moveTo(194, 400)
      ..lineTo(151, 400)
      ..cubicTo(129.461, 400, 112, 382.539, 112, 361)
      ..lineTo(112, 318);
    canvas.drawPath(brackets, bracketPaint);

    // 4. Warm cream "J" monogram stroke.
    final jPath = Path()
      ..moveTo(315, 166)
      ..lineTo(207, 166)
      ..lineTo(207, 199)
      ..lineTo(276, 199)
      ..lineTo(276, 306)
      ..cubicTo(276, 333, 258, 351, 231, 351)
      ..cubicTo(210, 351, 194, 340, 185, 323);
    canvas.drawPath(
      jPath,
      Paint()
        ..color = AppColors.bgLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 27
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.round,
    );

    // 5. Signature warm yellow "S" ribbon crossing the J.
    final sPath = Path()
      ..moveTo(342, 211)
      ..cubicTo(324, 188, 302, 179, 275, 179)
      ..cubicTo(243, 179, 222, 195, 222, 219)
      ..cubicTo(222, 244, 245, 253, 280, 263)
      ..lineTo(303, 270)
      ..cubicTo(335, 280, 351, 294, 351, 318)
      ..cubicTo(351, 346, 325, 365, 289, 365)
      ..cubicTo(261, 365, 238, 355, 219, 336);
    canvas.drawPath(
      sPath,
      Paint()
        ..color = AppColors.yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 25
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.round,
    );

    // 6. Warm cream scan pulse + dot.
    canvas.drawLine(
      const Offset(365, 244),
      const Offset(397, 244),
      Paint()
        ..color = AppColors.bgLight.withValues(alpha: 0.9)
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      const Offset(397, 244),
      6,
      Paint()..color = AppColors.bgLight,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _JScanLogoPainter oldDelegate) => false;
}

/// Empty-state graphic for the Documents tab: stacked warm sheets + yellow scanner brackets.
class EmptyDocumentsIllustration extends StatelessWidget {
  const EmptyDocumentsIllustration({super.key, this.size = 172});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: size,
      height: size * 0.86,
      child: CustomPaint(
        painter: _EmptyDocsPainter(scheme: scheme, isDark: isDark),
      ),
    );
  }
}

class _EmptyDocsPainter extends CustomPainter {
  const _EmptyDocsPainter({required this.scheme, required this.isDark});

  final ColorScheme scheme;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.54),
        width: w * 0.84,
        height: h * 0.72,
      ),
      Paint()
        ..color = AppColors.yellow.withValues(alpha: isDark ? 0.14 : 0.34),
    );

    // Back charcoal accent sheet.
    canvas.save();
    canvas.translate(w * 0.45, h * 0.53);
    canvas.rotate(-0.12);
    final backRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w * 0.43, height: h * 0.64),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      backRect,
      Paint()..color = isDark ? AppColors.charcoalElevated : AppColors.charcoal,
    );
    canvas.restore();

    // Front crisp paper sheet.
    canvas.save();
    canvas.translate(w * 0.54, h * 0.50);
    canvas.rotate(0.05);
    final pw = w * 0.46;
    final ph = h * 0.68;
    final paperRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: pw, height: ph),
      const Radius.circular(13),
    );
    canvas.drawRRect(
      paperRect.shift(const Offset(0, 6)),
      Paint()..color = Colors.black.withValues(alpha: isDark ? 0.35 : 0.09),
    );
    canvas.drawRRect(paperRect, Paint()..color = scheme.surface);
    canvas.drawRRect(
      paperRect,
      Paint()
        ..color = scheme.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final left = -pw * 0.34;
    final top = -ph * 0.33;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, pw * 0.38, ph * 0.08),
        const Radius.circular(4),
      ),
      Paint()..color = AppColors.yellow,
    );
    final linePaint = Paint()
      ..color = scheme.onSurfaceVariant.withValues(alpha: 0.30)
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final ly = top + ph * (0.21 + i * 0.13);
      final frac = i == 3 ? 0.46 : 0.68;
      canvas.drawLine(Offset(left, ly), Offset(left + pw * frac, ly), linePaint);
    }

    // Warm yellow optical scan beam.
    final beamY = ph * 0.08;
    canvas.drawRect(
      Rect.fromLTWH(-pw * 0.54, beamY - 12, pw * 1.08, 12),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.yellow.withValues(alpha: 0.0),
            AppColors.yellow.withValues(alpha: 0.32),
          ],
        ).createShader(Rect.fromLTWH(-pw * 0.54, beamY - 12, pw * 1.08, 12)),
    );
    canvas.drawLine(
      Offset(-pw * 0.54, beamY),
      Offset(pw * 0.54, beamY),
      Paint()
        ..color = isDark ? AppColors.yellow : AppColors.charcoal
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    // Four bold optical corner brackets.
    final bp = Paint()
      ..color = isDark ? AppColors.yellow : AppColors.charcoal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    final bx0 = w * 0.17;
    final bx1 = w * 0.85;
    final by0 = h * 0.10;
    final by1 = h * 0.90;
    const arm = 15.0;

    final brackets = Path()
      ..moveTo(bx0, by0 + arm)
      ..lineTo(bx0, by0)
      ..lineTo(bx0 + arm, by0)
      ..moveTo(bx1 - arm, by0)
      ..lineTo(bx1, by0)
      ..lineTo(bx1, by0 + arm)
      ..moveTo(bx1, by1 - arm)
      ..lineTo(bx1, by1)
      ..lineTo(bx1 - arm, by1)
      ..moveTo(bx0 + arm, by1)
      ..lineTo(bx0, by1)
      ..lineTo(bx0, by1 - arm);
    canvas.drawPath(brackets, bp);
  }

  @override
  bool shouldRepaint(covariant _EmptyDocsPainter oldDelegate) =>
      oldDelegate.scheme != scheme || oldDelegate.isDark != isDark;
}

/// Empty-search graphic: warm paper sheet + charcoal & yellow magnifier.
class EmptySearchIllustration extends StatelessWidget {
  const EmptySearchIllustration({super.key, this.size = 128});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: size,
      height: size * 0.88,
      child: CustomPaint(
        painter: _EmptySearchPainter(scheme: scheme, isDark: isDark),
      ),
    );
  }
}

class _EmptySearchPainter extends CustomPainter {
  const _EmptySearchPainter({required this.scheme, required this.isDark});

  final ColorScheme scheme;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawCircle(
      Offset(w * 0.5, h * 0.5),
      w * 0.38,
      Paint()..color = AppColors.yellow.withValues(alpha: isDark ? 0.14 : 0.35),
    );

    final sheet = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.44, h * 0.48),
        width: w * 0.44,
        height: h * 0.62,
      ),
      const Radius.circular(10),
    );
    canvas.drawRRect(sheet, Paint()..color = scheme.surface);
    canvas.drawRRect(
      sheet,
      Paint()
        ..color = scheme.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final linePaint = Paint()
      ..color = scheme.onSurfaceVariant.withValues(alpha: 0.30)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = h * (0.34 + i * 0.12);
      canvas.drawLine(
        Offset(w * 0.30, y),
        Offset(w * (i == 2 ? 0.48 : 0.56), y),
        linePaint,
      );
    }

    final c = Offset(w * 0.63, h * 0.58);
    final r = w * 0.16;
    canvas.drawCircle(c, r, Paint()..color = AppColors.yellow);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = AppColors.charcoal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0,
    );
    final angle = math.pi * 0.25;
    canvas.drawLine(
      Offset(c.dx + math.cos(angle) * r, c.dy + math.sin(angle) * r),
      Offset(c.dx + math.cos(angle) * (r + 16), c.dy + math.sin(angle) * (r + 16)),
      Paint()
        ..color = isDark ? AppColors.yellow : AppColors.charcoal
        ..strokeWidth = 4.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _EmptySearchPainter oldDelegate) =>
      oldDelegate.scheme != scheme || oldDelegate.isDark != isDark;
}

/// Warm coffee-cup vector illustration for the Saweria donation panel.
class SaweriaCoffeeIllustration extends StatelessWidget {
  const SaweriaCoffeeIllustration({super.key, this.size = 54});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SaweriaCoffeePainter()),
    );
  }
}

class _SaweriaCoffeePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawCircle(
      Offset(w * 0.5, h * 0.54),
      w * 0.44,
      Paint()..color = AppColors.yellow.withValues(alpha: 0.18),
    );

    final steamPaint = Paint()
      ..color = AppColors.yellow.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    for (final fx in [0.38, 0.50, 0.62]) {
      final x = w * fx;
      final path = Path()
        ..moveTo(x, h * 0.37)
        ..quadraticBezierTo(x - 3, h * 0.29, x, h * 0.22);
      canvas.drawPath(path, steamPaint);
    }

    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w * 0.70, h * 0.57),
        width: w * 0.22,
        height: h * 0.22,
      ),
      -math.pi * 0.45,
      math.pi * 0.9,
      false,
      Paint()
        ..color = AppColors.yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round,
    );

    final cup = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.24, h * 0.43, w * 0.46, h * 0.34),
      topLeft: const Radius.circular(3),
      topRight: const Radius.circular(3),
      bottomLeft: const Radius.circular(11),
      bottomRight: const Radius.circular(11),
    );
    canvas.drawRRect(cup, Paint()..color = AppColors.yellow);

    final hx = w * 0.47;
    final hy = h * 0.60;
    final heart = Path()
      ..moveTo(hx, hy + 5.5)
      ..cubicTo(hx - 8, hy, hx - 7, hy - 6, hx, hy - 2.2)
      ..cubicTo(hx + 7, hy - 6, hx + 8, hy, hx, hy + 5.5)
      ..close();
    canvas.drawPath(heart, Paint()..color = AppColors.charcoal);

    canvas.drawLine(
      Offset(w * 0.20, h * 0.82),
      Offset(w * 0.74, h * 0.82),
      Paint()
        ..color = AppColors.yellow.withValues(alpha: 0.8)
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SaweriaCoffeePainter oldDelegate) => false;
}

/// Compact vector illustration for the dark charcoal Tools hero banner.
class ToolsHeroIllustration extends StatelessWidget {
  const ToolsHeroIllustration({super.key, this.size = 66});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ToolsHeroPainter()),
    );
  }
}

class _ToolsHeroPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final back = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.08, h * 0.14, w * 0.48, h * 0.60),
      const Radius.circular(9),
    );
    canvas.drawRRect(back, Paint()..color = AppColors.charcoalTileTop);
    canvas.drawRRect(
      back,
      Paint()
        ..color = AppColors.yellow.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final mtn = Path()
      ..moveTo(w * 0.16, h * 0.56)
      ..lineTo(w * 0.28, h * 0.40)
      ..lineTo(w * 0.38, h * 0.50)
      ..lineTo(w * 0.44, h * 0.44)
      ..lineTo(w * 0.50, h * 0.56)
      ..close();
    canvas.drawPath(mtn, Paint()..color = AppColors.yellow.withValues(alpha: 0.45));

    final front = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.40, h * 0.28, w * 0.52, h * 0.62),
      const Radius.circular(10),
    );
    canvas.drawRRect(front, Paint()..color = AppColors.yellow);

    final barPaint = Paint()
      ..color = AppColors.charcoal.withValues(alpha: 0.85)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.52, h * 0.46), Offset(w * 0.80, h * 0.46), barPaint);
    canvas.drawLine(Offset(w * 0.52, h * 0.58), Offset(w * 0.78, h * 0.58), barPaint);
    canvas.drawLine(Offset(w * 0.52, h * 0.70), Offset(w * 0.68, h * 0.70), barPaint);
  }

  @override
  bool shouldRepaint(covariant _ToolsHeroPainter oldDelegate) => false;
}

/// Onboarding Page 1 illustration: angled document locked by 4 crisp optical corner handles.
class OnboardingScanIllustration extends StatelessWidget {
  const OnboardingScanIllustration({super.key, this.size = 210});

  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: size,
      height: size * 0.88,
      child: CustomPaint(painter: _OnboardingScanPainter(isDark: isDark)),
    );
  }
}

class _OnboardingScanPainter extends CustomPainter {
  const _OnboardingScanPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Subtle geometric dark card frame.
    final stage = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.10, h * 0.08, w * 0.80, h * 0.84),
      const Radius.circular(24),
    );
    canvas.drawRRect(
      stage,
      Paint()..color = isDark ? AppColors.charcoalElevated : AppColors.charcoal,
    );

    // Subtle perspective trapezoid paper inside stage.
    final tl = Offset(w * 0.30, h * 0.22);
    final tr = Offset(w * 0.72, h * 0.19);
    final br = Offset(w * 0.78, h * 0.78);
    final bl = Offset(w * 0.22, h * 0.75);

    final paper = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();
    canvas.drawPath(paper, Paint()..color = AppColors.bgLight);

    // Document lines inside trapezoid.
    final linePaint = Paint()
      ..color = AppColors.charcoal.withValues(alpha: 0.22)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final frac = 0.26 + i * 0.14;
      final lx = tl.dx + (bl.dx - tl.dx) * frac + 16;
      final ly = tl.dy + (bl.dy - tl.dy) * frac;
      final rx = tr.dx + (br.dx - tr.dx) * frac - (i == 3 ? 34 : 18);
      final ry = tr.dy + (br.dy - tr.dy) * frac;
      canvas.drawLine(Offset(lx, ly), Offset(rx, ry), linePaint);
    }

    // Quad outline & 4 bright warm yellow lock dots.
    canvas.drawPath(
      paper,
      Paint()
        ..color = AppColors.yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeJoin = StrokeJoin.round,
    );
    for (final pt in [tl, tr, br, bl]) {
      canvas.drawCircle(pt, 7.5, Paint()..color = AppColors.yellow);
      canvas.drawCircle(
        pt,
        7.5,
        Paint()
          ..color = AppColors.charcoal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OnboardingScanPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// Onboarding Page 2 illustration: split shadow-removal sheet + PDF/ZIP craft badges.
class OnboardingEnhanceIllustration extends StatelessWidget {
  const OnboardingEnhanceIllustration({super.key, this.size = 210});

  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: size,
      height: size * 0.88,
      child: CustomPaint(painter: _OnboardingEnhancePainter(isDark: isDark)),
    );
  }
}

class _OnboardingEnhancePainter extends CustomPainter {
  const _OnboardingEnhancePainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final sheet = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.50),
        width: w * 0.54,
        height: h * 0.78,
      ),
      const Radius.circular(18),
    );
    canvas.drawRRect(
      sheet.shift(const Offset(0, 6)),
      Paint()..color = Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
    );
    canvas.drawRRect(sheet, Paint()..color = Colors.white);

    // Left half shadowed before-enhancement tone.
    canvas.save();
    canvas.clipRRect(sheet);
    canvas.drawRect(
      Rect.fromLTWH(w * 0.23, h * 0.11, w * 0.27, h * 0.78),
      Paint()..color = const Color(0xFFD9D3C7),
    );

    // Text lines across both halves (dim on shadowed left, crisp dark on cleaned right).
    for (var i = 0; i < 5; i++) {
      final y = h * (0.26 + i * 0.115);
      canvas.drawLine(
        Offset(w * 0.30, y),
        Offset(w * 0.50, y),
        Paint()
          ..color = const Color(0xFF78736A)
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset(w * 0.50, y),
        Offset(w * (i == 4 ? 0.62 : 0.70), y),
        Paint()
          ..color = AppColors.charcoal
          ..strokeWidth = 3.8
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();

    // Vertical divider slider bar in warm yellow.
    canvas.drawLine(
      Offset(w * 0.50, h * 0.08),
      Offset(w * 0.50, h * 0.92),
      Paint()
        ..color = AppColors.charcoal
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(w * 0.50, h * 0.50),
      13,
      Paint()..color = AppColors.yellow,
    );
    canvas.drawCircle(
      Offset(w * 0.50, h * 0.50),
      13,
      Paint()
        ..color = AppColors.charcoal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );

    // Floating dark PDF pill on top-right.
    final pill = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.66, h * 0.16, w * 0.24, h * 0.16),
      const Radius.circular(10),
    );
    canvas.drawRRect(pill, Paint()..color = AppColors.charcoal);
    canvas.drawCircle(
      Offset(w * 0.72, h * 0.24),
      4,
      Paint()..color = AppColors.yellow,
    );
    canvas.drawLine(
      Offset(w * 0.77, h * 0.24),
      Offset(w * 0.85, h * 0.24),
      Paint()
        ..color = AppColors.bgLight
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _OnboardingEnhancePainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// Onboarding Page 3 illustration: JScan brand emblem framed by warm privacy rings.
class OnboardingOfflineIllustration extends StatelessWidget {
  const OnboardingOfflineIllustration({super.key, this.size = 210});

  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: size,
      height: size * 0.88,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size * 0.88),
            painter: _OnboardingRingsPainter(isDark: isDark),
          ),
          const JScanLogoMark(size: 92),
          Positioned(
            right: size * 0.18,
            bottom: size * 0.12,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.yellow,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? AppColors.bgDark : AppColors.bgLight,
                  width: 3,
                ),
              ),
              child: const Icon(
                Icons.verified_user_rounded,
                size: 18,
                color: AppColors.charcoal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingRingsPainter extends CustomPainter {
  const _OnboardingRingsPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.5, size.height * 0.5);
    canvas.drawCircle(
      c,
      size.height * 0.44,
      Paint()
        ..color = AppColors.yellow.withValues(alpha: isDark ? 0.12 : 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.drawCircle(
      c,
      size.height * 0.34,
      Paint()..color = AppColors.yellow.withValues(alpha: isDark ? 0.10 : 0.24),
    );
  }

  @override
  bool shouldRepaint(covariant _OnboardingRingsPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
