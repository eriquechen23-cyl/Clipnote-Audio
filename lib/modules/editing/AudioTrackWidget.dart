import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'audio_track.dart';

/// 音軌編輯元件，提供拖曳、剪切與淡入淡出控制。
class AudioTrackWidget extends StatefulWidget {
  final AudioTrack track;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  const AudioTrackWidget({
    super.key,
    required this.track,
    required this.onDelete,
    required this.onChanged,
  });

  @override
  State<AudioTrackWidget> createState() => _AudioTrackWidgetState();
}

class _AudioTrackWidgetState extends State<AudioTrackWidget> {
  static const double _pixelsPerSecond = 100;
  double? _selStart;
  double? _selEnd;
  bool _selecting = false;

  double get _samplesPerPixel => widget.track.sampleRate / _pixelsPerSecond;

  @override
  Widget build(BuildContext context) {
    final seg = widget.track.segments.first;
    final width = seg.duration / widget.track.sampleRate * _pixelsPerSecond;
    final fadeInPx = seg.fadeIn / widget.track.sampleRate * _pixelsPerSecond;
    final fadeOutPx = seg.fadeOut / widget.track.sampleRate * _pixelsPerSecond;

    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        final deltaSamples = (d.delta.dx * _samplesPerPixel).round();
        widget.track.segments[0] =
            seg.copyWith(start: seg.start + deltaSamples);
        widget.onChanged();
        setState(() {});
      },
      onLongPressStart: (d) {
        setState(() {
          _selecting = true;
          _selStart = d.localPosition.dx;
          _selEnd = _selStart;
        });
      },
      onLongPressMoveUpdate: (d) {
        setState(() => _selEnd = d.localPosition.dx);
      },
      onLongPressEnd: (d) {
        final left = math.min(_selStart ?? 0, _selEnd ?? 0);
        final right = math.max(_selStart ?? 0, _selEnd ?? 0);
        final srcStart = (left * _samplesPerPixel).round();
        final dur = math.max(1, ((right - left) * _samplesPerPixel).round());
        widget.track.segments[0] =
            seg.copyWith(sourceStart: srcStart, duration: dur);
        _selecting = false;
        widget.onChanged();
        setState(() {});
      },
      child: Container(
        margin: EdgeInsets.fromLTRB(
            12 + seg.start / widget.track.sampleRate * _pixelsPerSecond,
            6,
            12,
            6),
        height: 60,
        width: width,
        color: Colors.grey[200],
        child: Stack(
          children: [
            Row(
              children: [
                const Icon(Icons.music_note),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.delete), onPressed: widget.onDelete),
              ],
            ),
            if (_selecting)
              Positioned(
                left: math.min(_selStart ?? 0, _selEnd ?? 0),
                width: (_selEnd == null || _selStart == null)
                    ? 0
                    : (_selEnd! - _selStart!).abs(),
                top: 0,
                bottom: 0,
                child: Container(color: Colors.blue.withOpacity(0.3)),
              ),
            // Fade-in handle
            Positioned(
              left: fadeInPx - 4,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanUpdate: (d) {
                  final delta = (d.delta.dx * _samplesPerPixel).round();
                  final newFade =
                      (seg.fadeIn + delta).clamp(0, seg.duration - seg.fadeOut);
                  widget.track.segments[0] = seg.copyWith(fadeIn: newFade);
                  widget.onChanged();
                  setState(() {});
                },
                child: Container(width: 8, color: Colors.green),
              ),
            ),
            // Fade-out handle
            Positioned(
              left: width - fadeOutPx - 4,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanUpdate: (d) {
                  final delta = (-d.delta.dx * _samplesPerPixel).round();
                  final newFade =
                      (seg.fadeOut + delta).clamp(0, seg.duration - seg.fadeIn);
                  widget.track.segments[0] = seg.copyWith(fadeOut: newFade);
                  widget.onChanged();
                  setState(() {});
                },
                child: Container(width: 8, color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
