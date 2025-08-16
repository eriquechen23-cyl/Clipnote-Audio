// lib/modules/widgets/timeline.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

class TimelineRuler extends StatelessWidget {
  final int durationMs;
  final ValueChanged<double>? onSeek; // 0.0~1.0 進度（可接 svc.seekTo(比例*duration)）
  final double? pixelsPerSecond; // 可手動指定縮放；不指定則自動
  const TimelineRuler({
    super.key,
    required this.durationMs,
    this.onSeek,
    this.pixelsPerSecond,
  });

  @override
  Widget build(BuildContext context) {
    final dSec = (durationMs / 1000).clamp(0, double.infinity).toDouble();

    return SizedBox(
      height: 56,
      child: LayoutBuilder(
        builder: (context, c) {
          // 自適應縮放：讓短音檔不會太稀疏、長音檔不會超寬
          final autoPps = _autoPixelsPerSecond(dSec, c.maxWidth);
          final pps = pixelsPerSecond ?? autoPps;

          // 內容寬度：至少鋪滿可視區；過長則可水平滾動
          final contentW = math.max(c.maxWidth, (dSec * pps) + 16 * 2);

          // 刻度步進（主要/次要）
          final steps = _pickSteps(pps);

          final painter = _RulerPainter(
            durationSec: dSec,
            pixelsPerSecond: pps,
            majorStepSec: steps.$1,
            minorStepSec: steps.$2,
            textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white.withOpacity(0.9),
            ),
            lineColor: Colors.white.withOpacity(0.26),
            majorColor: Colors.white.withOpacity(0.42),
          );

          final ruler = RepaintBoundary(
            child: CustomPaint(size: Size(contentW, 56), painter: painter),
          );

          // 邊緣淡出（UI2 風格）
          final faded = ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: [0.0, 0.04, 0.96, 1.0],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: ruler,
          );

          final scroll = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: faded,
          );

          // 點擊 Seek（可選）
          if (onSeek == null) return scroll;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              final dx = d.localPosition.dx.clamp(0, contentW);
              final t = (dx - 16) / (contentW - 32); // 扣左右內距
              onSeek!.call(t.clamp(0.0, 1.0));
            },
            child: scroll,
          );
        },
      ),
    );
  }

  double _autoPixelsPerSecond(double durationSec, double maxWidth) {
    if (durationSec <= 0) return 120; // 預設密度
    // 目標讓主要刻度（約每 5~10 秒）有 100~140px 的視覺節奏
    final targetMajorPx = 120.0;
    final approxMajorSec = _pickSteps(100).$1; // 取一個粗略值
    final pps = targetMajorPx / approxMajorSec;
    // 同時別讓總長遠超視口（長檔案仍可滾動，但避免過密）
    final minPps = maxWidth / math.max(durationSec, 1.0) * 0.8;
    return pps.clamp(minPps, 220.0);
  }

  /// 根據密度挑選合適的主要/次要步進（秒）
  (double major, double minor) _pickSteps(double pps) {
    // 每 1 秒有多少像素：越大表示越密，可選較大的 major
    if (pps >= 160) return (5, 1); // 很密：每 5s 標記、每 1s 小刻度
    if (pps >= 100) return (10, 2); // 中：10s / 2s
    if (pps >= 60) return (15, 5); // 稍鬆：15s / 5s
    if (pps >= 30) return (30, 10); // 鬆：30s / 10s
    return (60, 15); // 很鬆：60s / 15s
  }
}

class _RulerPainter extends CustomPainter {
  final double durationSec;
  final double pixelsPerSecond;
  final double majorStepSec;
  final double minorStepSec;
  final TextStyle? textStyle;
  final Color lineColor;
  final Color majorColor;

  _RulerPainter({
    required this.durationSec,
    required this.pixelsPerSecond,
    required this.majorStepSec,
    required this.minorStepSec,
    required this.textStyle,
    required this.lineColor,
    required this.majorColor,
  });

  static const double _h = 56;
  static const double _pad = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final paintMinor = Paint()
      ..color = lineColor
      ..strokeWidth = 1;

    final paintMajor = Paint()
      ..color = majorColor
      ..strokeWidth = 1.2;

    // 底線
    canvas.drawLine(Offset(_pad, 1), Offset(size.width - _pad, 1), paintMinor);

    // 刻度
    final total = durationSec;
    // 次要
    for (double s = 0; s <= total; s += minorStepSec) {
      final x = _pad + s * pixelsPerSecond;
      final y0 = 6.0;
      final y1 = 16.0;
      canvas.drawLine(Offset(x, y0), Offset(x, y1), paintMinor);
    }
    // 主要 + 標籤
    final tp = (textStyle == null)
        ? null
        : TextPainter(textDirection: TextDirection.ltr);
    for (double s = 0; s <= total + 0.0001; s += majorStepSec) {
      final x = _pad + s * pixelsPerSecond;
      final y0 = 6.0;
      final y1 = 22.0;
      canvas.drawLine(Offset(x, y0), Offset(x, y1), paintMajor);

      if (tp != null) {
        final label = _fmtSec(s);
        tp.text = TextSpan(text: label, style: textStyle);
        tp.layout();
        // 避免貼邊
        final tx = (x - tp.width / 2).clamp(_pad, size.width - _pad - tp.width);
        tp.paint(canvas, Offset(tx, 26));
      }
    }
  }

  String _fmtSec(double sec) {
    final s = sec.round();
    final m = (s ~/ 60);
    final r = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(m)}:${two(r)}';
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) {
    return durationSec != old.durationSec ||
        pixelsPerSecond != old.pixelsPerSecond ||
        majorStepSec != old.majorStepSec ||
        minorStepSec != old.minorStepSec ||
        textStyle != old.textStyle ||
        lineColor != old.lineColor ||
        majorColor != old.majorColor;
  }
}
