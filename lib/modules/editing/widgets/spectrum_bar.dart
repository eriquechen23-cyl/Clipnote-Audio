import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class SpectrumBar extends StatelessWidget {
  final List<double> spectrum;
  final double height;
  final Gradient? gradient;
  const SpectrumBar({
    super.key,
    required this.spectrum,
    this.height = 60,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SpectrumBarPainter(
          spectrum,
          gradient ??
              const LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
              ),
        ),
      ),
    );
  }
}

class _SpectrumBarPainter extends CustomPainter {
  final List<double> spec;
  final Gradient grad;
  _SpectrumBarPainter(this.spec, this.grad);

  @override
  void paint(Canvas canvas, Size size) {
    if (spec.isEmpty || size.width <= 0 || size.height <= 0) return;

    const gap = 1.0; // 欄間距
    final maxBars = math.max(8, (size.width / (1 + gap)).floor());

    List<double> bins = spec;
    if (spec.length > maxBars) {
      final f = (spec.length / maxBars).ceil();
      final reduced = <double>[];
      for (int i = 0; i < spec.length; i += f) {
        double m = 0;
        for (int j = i; j < math.min(i + f, spec.length); j++) {
          if (spec[j] > m) m = spec[j];
        }
        reduced.add(m);
      }
      bins = reduced;
    }

    final n = bins.length;
    final barW = (size.width - gap * (n - 1)) / n;
    final paint = Paint()
      ..isAntiAlias = false
      ..shader = grad.createShader(Offset.zero & size);

    final maxVal = bins.reduce((a, b) => a > b ? a : b);
    final denom = maxVal <= 0 ? 1.0 : maxVal;

    double x = 0;
    for (int i = 0; i < n; i++) {
      final h = (bins[i] / denom) * size.height;
      canvas.drawRect(Rect.fromLTWH(x, size.height - h, barW, h), paint);
      x += barW + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumBarPainter old) =>
      !listEquals(old.spec, spec) || old.grad != grad;
}
