import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 時間軸尺規，支援拖曳與縮放。
class TimelineRuler extends StatefulWidget {
  final double maxSeconds;
  const TimelineRuler({super.key, this.maxSeconds = 300});

  @override
  State<TimelineRuler> createState() => _TimelineRulerState();
}

class _TimelineRulerState extends State<TimelineRuler> {
  double _scale = 1.0;
  double _offset = 0.0;
  static const double _basePixelsPerSecond = 100;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        setState(() {
          _offset = math.max(0, _offset - d.delta.dx);
        });
      },
      onScaleUpdate: (d) {
        setState(() {
          _scale = (_scale * d.scale).clamp(0.5, 5.0);
        });
      },
      child: CustomPaint(
        size: const Size(double.infinity, 40),
        painter: _RulerPainter(
          offset: _offset,
          scale: _scale,
          maxSeconds: widget.maxSeconds,
          pixelsPerSecond: _basePixelsPerSecond,
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  final double offset;
  final double scale;
  final double maxSeconds;
  final double pixelsPerSecond;
  _RulerPainter({
    required this.offset,
    required this.scale,
    required this.maxSeconds,
    required this.pixelsPerSecond,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pps = pixelsPerSecond * scale;
    final startSec = offset / pps;
    final endSec = math.min(maxSeconds, (offset + size.width) / pps);
    final majorPaint = Paint()..color = Colors.black;
    final minorPaint = Paint()..color = Colors.grey;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (int s = startSec.floor(); s <= endSec.ceil(); s++) {
      final x = s * pps - offset;
      final isMajor = s % 5 == 0;
      final paint = isMajor ? majorPaint : minorPaint;
      final h = isMajor ? size.height : size.height / 2;
      canvas.drawLine(Offset(x, size.height), Offset(x, size.height - h), paint);
      if (isMajor) {
        final span = TextSpan(
          text: _formatTime(s),
          style: const TextStyle(color: Colors.black, fontSize: 10),
        );
        textPainter.text = span;
        textPainter.layout();
        textPainter.paint(canvas, Offset(x + 2, 0));
      }
    }
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) {
    return old.offset != offset || old.scale != scale;
  }
}
