// lib/modules/UI/ui2/ui2_playhead_overlay.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PlayheadOverlay extends StatelessWidget {
  final ValueListenable<int> playheadListenable; // ms
  final double Function(int ms) msToScreenX; // 轉成螢幕座標（需扣水平卷動 offset）

  const PlayheadOverlay({
    super.key,
    required this.playheadListenable,
    required this.msToScreenX,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: playheadListenable,
      builder: (_, ms, __) {
        final x = msToScreenX(ms);
        return CustomPaint(painter: _PlayheadPainter(x), size: Size.infinite);
      },
    );
  }
}

class _PlayheadPainter extends CustomPainter {
  final double x;
  _PlayheadPainter(this.x);

  @override
  void paint(Canvas canvas, Size size) {
    if (x.isNaN || x.isInfinite) return;

    // 垂直紅線
    final p = Paint()
      ..color = const Color(0xFFFF5252)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);

    // 頂部三角（向下）
    const triW = 10.0;
    const triH = 8.0;
    final path = Path()
      ..moveTo(x, 0)
      ..lineTo(x - triW / 2, triH)
      ..lineTo(x + triW / 2, triH)
      ..close();
    final triPaint = Paint()..color = const Color(0xFFFFD54F);
    canvas.drawPath(path, triPaint);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF332B00),
    );
  }

  @override
  bool shouldRepaint(covariant _PlayheadPainter old) => old.x != x;
}
