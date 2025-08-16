// ===============================
// lib/modules/widgets/waveform.dart
// ===============================

import 'package:flutter/material.dart';
import 'package:clipnote_audio/modules/services/singleTrackService.dart';

class WaveformPreview extends StatelessWidget {
  final SingleTrackService service;
  const WaveformPreview({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    final peaks = service.track.downsampledPcmPeak;
    return Container(
      height: 64,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(8),
      ),
      child: peaks.isEmpty
          ? const Center(child: Text('（尚無波形，請匯入檔案）'))
          : CustomPaint(painter: WaveformPainter(peaks)),
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<int> peaks;
  const WaveformPainter(this.peaks);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    final len = peaks.length;
    if (len == 0) return;
    final stepX = size.width / len;
    for (int i = 0; i < len; i++) {
      final norm = peaks[i] / 32768.0;
      final h = norm * size.height;
      final x = i * stepX;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
