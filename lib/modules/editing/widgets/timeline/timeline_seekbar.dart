// =============================================
// Drop-in fix to make TimelineSeekBar move with
// playback using a ValueNotifier<int> positionMs.
// =============================================

// 1) MultiTrackEditor.dart — add a ValueNotifier and wire it
// -----------------------------------------------------------
// Place near other fields in _MultiTrackEditorState:
/*
  final ValueNotifier<int> _posMs = ValueNotifier<int>(0);
  int _durationMs = 0;
*/

// dispose():
/*
  _posMs.dispose();
*/

// In _reloadPlayer(), after await _pb.load(data, sr);
/*
  final samples = _svc.masterPcm!.length ~/ 2; // 16-bit mono
  _durationMs = (samples * 1000) ~/ sr;        // integer milliseconds
  _posMs.value = 0;                            // reset head
*/

// In _startSpectrumTimer(), after computing final posMs = _pb.playheadMs;
/*
  _posMs.value = posMs; // tick the listenable every ~33ms
*/

// When you seek (e.g., after delete/change), also update the notifier:
/*
  await _pb.seekMs(currentMs);
  _posMs.value = currentMs;
*/

// In build(), pass the listenable + duration to TimelineSeekBar:
/*
  TimelineSeekBar(
    height: 28,
    positionMs: _posMs,
    durationMs: _durationMs,
    onSeek: (ms) async {
      await _pb.seekMs(ms);
      _posMs.value = ms;
    },
  ),
*/

// -----------------------------------------------------------
// 2) Replace your TimelineSeekBar with this listenable version
//    (lib/modules/editing/widgets/timeline/timeline_seekbar.dart)
// -----------------------------------------------------------
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class TimelineSeekBar extends StatelessWidget {
  final double height;
  final ValueListenable<int> positionMs; // current playhead in ms
  final int durationMs; // total length in ms
  final ValueChanged<int>? onSeek; // optional scrubbing callback

  const TimelineSeekBar({
    super.key,
    required this.height,
    required this.positionMs,
    required this.durationMs,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ValueListenableBuilder<int>(
            valueListenable: positionMs,
            builder: (_, pos, __) {
              final total = durationMs <= 0 ? 1 : durationMs;
              final clamped = pos.clamp(0, total);
              final progress = clamped / total;
              return _InteractiveBar(
                width: constraints.maxWidth,
                height: height,
                progress: progress,
                durationMs: total,
                onSeek: onSeek,
              );
            },
          );
        },
      ),
    );
  }
}

class _InteractiveBar extends StatelessWidget {
  final double width;
  final double height;
  final double progress; // 0.0..1.0
  final int durationMs;
  final ValueChanged<int>? onSeek;

  const _InteractiveBar({
    required this.width,
    required this.height,
    required this.progress,
    required this.durationMs,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (d) => _handleDrag(d.localPosition.dx),
      onHorizontalDragUpdate: (d) => _handleDrag(d.localPosition.dx),
      onTapDown: (d) => _handleDrag(d.localPosition.dx),
      child: CustomPaint(
        size: Size(width, height),
        painter: _TimelinePainter(progress: progress),
      ),
    );
  }

  void _handleDrag(double x) {
    if (onSeek == null) return;
    final p = x <= 0 ? 0.0 : (x >= width ? 1.0 : (x / width));
    final targetMs = (p * durationMs).round();
    onSeek!(targetMs);
  }
}

class _TimelinePainter extends CustomPainter {
  final double progress; // 0..1
  const _TimelinePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..color = const Color(0x22FFFFFF)
      ..style = PaintingStyle.fill;
    final fg = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF22D3EE), Color(0xFF60A5FA)],
      ).createShader(Offset.zero & size);

    final radius = math.min(10.0, size.height / 2);
    final rect = RRect.fromLTRBR(
      0,
      0,
      size.width,
      size.height,
      Radius.circular(radius),
    );
    canvas.drawRRect(rect, bg);

    // progress bar
    final w = (size.width * progress).clamp(0.0, size.width);
    final prect = RRect.fromLTRBR(
      0,
      0,
      w,
      size.height,
      Radius.circular(radius),
    );
    canvas.drawRRect(prect, fg);

    // playhead
    final x = w;
    final head = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), head);
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      old.progress != progress;
}
