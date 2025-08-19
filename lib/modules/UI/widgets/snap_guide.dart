// modules/UI/widgets/snap_guide.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:clipnote_audio/modules/editing/snapping.dart';

typedef MsToPx = double Function(int ms);

class SnapGuideLayer extends StatelessWidget {
  final ValueListenable<SnapPoint?> guide;
  final MsToPx msToPx;

  const SnapGuideLayer({super.key, required this.guide, required this.msToPx});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SnapPoint?>(
      valueListenable: guide,
      builder: (_, gp, __) {
        if (gp == null) return const SizedBox.shrink();
        final x = msToPx(gp.ms).roundToDouble();
        return IgnorePointer(
          ignoring: true,
          child: CustomPaint(
            painter: _GuidePainter(x: x, label: gp.tag),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

class _GuidePainter extends CustomPainter {
  final double x;
  final String label;
  _GuidePainter({required this.x, required this.label});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF66E3FF).withOpacity(.75)
      ..strokeWidth = 1.5;

    // 垂直線
    // 對齊像素避免模糊
    final xr = x.roundToDouble();
    canvas.drawLine(Offset(xr, 0), Offset(xr, size.height), p);

    // 小標籤
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(fontSize: 10, color: Colors.white),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final ox = (xr + 6 + tp.width < size.width) ? xr + 6 : (xr - 6 - tp.width);
    final oy = 6.0;
    tp.paint(canvas, Offset(ox, oy));
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) =>
      old.x != x || old.label != label;
}
