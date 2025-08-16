// ===============================
// lib/modules/widgets/spectrum.dart
// ===============================

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

class SpectrumStrip extends StatelessWidget {
  final Int16List window;
  const SpectrumStrip({super.key, required this.window});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: CustomPaint(painter: SpectrumPainter(window)),
    );
  }
}

class SpectrumPainter extends CustomPainter {
  final Int16List w;
  const SpectrumPainter(this.w);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // 超輕量：分成 N 條，取區段峰值當作高度（非真正 FFT，僅 UI 佔位）
    const bars = 48;
    final step = (w.isEmpty ? 1 : (w.length / bars).floor().clamp(1, w.length));
    final barW = size.width / bars;
    for (int i = 0; i < bars; i++) {
      int start = i * step;
      int end = math.min(start + step, w.length);
      int peak = 0;
      for (int j = start; j < end; j++) {
        final v = w[j].abs();
        if (v > peak) peak = v;
      }
      final h = (peak / 32768.0) * size.height;
      paint.color = h > size.height * 0.8
          ? Colors.red
          : (h > size.height * 0.6 ? Colors.orange : Colors.lightBlueAccent);
      final rect = Rect.fromLTWH(i * barW, size.height - h, barW * 0.9, h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
