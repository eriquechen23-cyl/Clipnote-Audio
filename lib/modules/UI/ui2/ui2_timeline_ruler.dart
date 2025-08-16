// lib/modules/UI/ui2/ui2_timeline_ruler.dart
import 'package:flutter/material.dart';

class TimelineRuler extends StatelessWidget {
  final int durationMs;
  final double pxPerMs;
  final int majorStepMs; // 主刻度間距（例如 1000ms）

  const TimelineRuler({
    super.key,
    required this.durationMs,
    required this.pxPerMs,
    required this.majorStepMs,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RulerPainter(
        durationMs: durationMs,
        pxPerMs: pxPerMs,
        majorStepMs: majorStepMs,
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  final int durationMs;
  final double pxPerMs;
  final int majorStepMs;

  _RulerPainter({
    required this.durationMs,
    required this.pxPerMs,
    required this.majorStepMs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF1C1F26);
    canvas.drawRect(Offset.zero & size, bg);

    final h = size.height;
    final yBase = h - 1;
    final tickMajor = 16.0;
    final tickMinor = 8.0;

    final line = Paint()
      ..color = const Color(0xFF2B2F38)
      ..strokeWidth = 1;

    // 底線
    canvas.drawLine(Offset(0, yBase), Offset(size.width, yBase), line);

    // 刻度與標籤
    final textStyle = const TextStyle(
      color: Color(0xFFFFD54F), // 暖黃
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
    final minorStepMs = (majorStepMs ~/ 5).clamp(1, majorStepMs);

    for (int ms = 0; ms <= durationMs; ms += minorStepMs) {
      final x = ms * pxPerMs;
      final isMajor = (ms % majorStepMs == 0);
      final len = isMajor ? tickMajor : tickMinor;
      final c = isMajor ? const Color(0xFFFFD54F) : const Color(0xFF9AA4B2);

      final p = Paint()
        ..color = c
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, yBase), Offset(x, yBase - len), p);

      if (isMajor) {
        final label = _fmtMs(ms);
        final tp = TextPainter(
          text: TextSpan(text: label, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 4, 2));
      }
    }
  }

  String _fmtMs(int ms) {
    final totalSec = (ms / 1000).floor();
    final m = (totalSec ~/ 60).toString();
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
    // 如需毫秒：'${(ms % 1000).toString().padLeft(3,'0')}'
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.durationMs != durationMs ||
      old.pxPerMs != pxPerMs ||
      old.majorStepMs != majorStepMs;
}

/// 全域格線（覆蓋整個編輯區）
class TimelineGridOverlay extends StatelessWidget {
  final int durationMs;
  final double pxPerMs;
  final int stepMs;

  const TimelineGridOverlay({
    super.key,
    required this.durationMs,
    required this.pxPerMs,
    required this.stepMs,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GridPainter(
        durationMs: durationMs,
        pxPerMs: pxPerMs,
        stepMs: stepMs,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _GridPainter extends CustomPainter {
  final int durationMs;
  final double pxPerMs;
  final int stepMs;

  _GridPainter({
    required this.durationMs,
    required this.pxPerMs,
    required this.stepMs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final minor = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = const Color(0x33FFD54F)
      ..strokeWidth = 1;

    final minorStepMs = (stepMs ~/ 5).clamp(1, stepMs);

    for (int ms = 0; ms <= durationMs; ms += minorStepMs) {
      final x = ms * pxPerMs;
      final isMajor = (ms % stepMs == 0);
      canvas.drawLine(Offset(x, 0), Offset(x, h), isMajor ? major : minor);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.durationMs != durationMs ||
      old.pxPerMs != pxPerMs ||
      old.stepMs != stepMs;
}
