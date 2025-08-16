import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

class SpectrumBars extends StatelessWidget {
  final Float32List bins;
  final double barGap;
  final double minBarWidth;
  final BorderRadius borderRadius;

  const SpectrumBars({
    super.key,
    required this.bins,
    this.barGap = 2,
    this.minBarWidth = 2,
    this.borderRadius = const BorderRadius.all(Radius.circular(2)),
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SpectrumPainter(
        bins: bins,
        barGap: barGap,
        minBarWidth: minBarWidth,
        borderRadius: borderRadius,
        colorLo: const Color(0xFF57D5FF), // 低能量色
        colorHi: const Color(0xFF8A7CFF), // 高能量色
        bgLine: Colors.white.withOpacity(0.06),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  final Float32List bins;
  final double barGap;
  final double minBarWidth;
  final BorderRadius borderRadius;
  final Color colorLo, colorHi;
  final Color bgLine;

  _SpectrumPainter({
    required this.bins,
    required this.barGap,
    required this.minBarWidth,
    required this.borderRadius,
    required this.colorLo,
    required this.colorHi,
    required this.bgLine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bins.isEmpty || size.width <= 0 || size.height <= 0) return;

    // 背景細線（提升可讀性）
    final bgPaint = Paint()
      ..color = bgLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final midY = size.height * 0.5;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), bgPaint);

    // 計算柱寬
    final n = bins.length;
    final totalGap = barGap * (n - 1);
    final barW = math.max(minBarWidth, (size.width - totalGap) / n);

    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < n; i++) {
      final x = i * (barW + barGap);
      final v = bins[i].clamp(0.0, 1.0);
      final h = v * size.height;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, size.height - h, barW, h),
        topLeft: borderRadius.topLeft,
        topRight: borderRadius.topRight,
        bottomLeft: borderRadius.bottomLeft,
        bottomRight: borderRadius.bottomRight,
      );

      // 漸層（低→高）
      final shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [colorLo, colorHi],
      ).createShader(rect.outerRect);
      paint.shader = shader;

      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter old) {
    return !identical(old.bins, bins); // bins 物件變了才重畫（效能好）
  }
}
