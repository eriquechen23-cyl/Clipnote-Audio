import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'ui2_primitives.dart';
import 'package:clipnote_audio/modules/UI/widgets/spectrum.dart';
import 'package:clipnote_audio/modules/UI/widgets/timeline.dart';

/// 頻譜概覽 Glass 面板
class SpectrumOverviewPanel extends StatelessWidget {
  final Int16List window;
  const SpectrumOverviewPanel({super.key, required this.window});

  @override
  Widget build(BuildContext context) {
    return Glass(
      height: 82,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          Row(
            children: [
              Icon(Icons.equalizer_rounded, size: 16),
              SizedBox(width: 6),
              Text(
                '頻譜概覽',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 時間軸（外層帶 SoftCard，並把 0..1 的 onSeek 轉成毫秒）
class TimelinePanel extends StatelessWidget {
  final int durationMs;
  final ValueChanged<int> onSeekMs;
  const TimelinePanel({
    super.key,
    required this.durationMs,
    required this.onSeekMs,
  });

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        height: 56,
        child: TimelineRuler(
          durationMs: durationMs,
          onSeek: (t) => onSeekMs((t * durationMs).round()),
        ),
      ),
    );
  }
}
