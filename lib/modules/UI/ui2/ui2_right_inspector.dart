import 'package:flutter/material.dart';
import 'ui2_primitives.dart';

class RightInspector extends StatelessWidget {
  final int durationMs;
  final bool isPlaying;

  // 新增：音量（0..1）與回呼
  final double volume01;
  final ValueChanged<double> onVolume;

  // 顯示資訊（可保留預設）
  final int sampleRateHz;
  final int bitDepth;

  final VoidCallback? onExport;

  const RightInspector({
    super.key,
    required this.durationMs,
    required this.isPlaying,
    required this.volume01,
    required this.onVolume,
    this.sampleRateHz = 48000,
    this.bitDepth = 16,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    // 格式化長度
    final d = Duration(milliseconds: durationMs);
    String two(int n) => n.toString().padLeft(2, '0');
    final mm = two(d.inMinutes.remainder(60));
    final ss = two(d.inSeconds.remainder(60));
    final cs = (d.inMilliseconds.remainder(1000) / 10)
        .floor()
        .toString()
        .padLeft(2, '0');
    final mmssMS = '$mm:$ss.$cs';

    final statusText = isPlaying ? '播放中' : '已暫停';
    final srText = '${(sampleRateHz / 1000).toStringAsFixed(0)} kHz';
    final bdText = '$bitDepth-bit';

    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth.clamp(200.0, 320.0);
        return SizedBox(
          width: maxW,
          child: Glass(
            padding: const EdgeInsets.all(12),
            child: _InspectorBody(
              status: statusText,
              lengthText: mmssMS,
              sampleRateText: srText,
              bitDepthText: bdText,
              volume01: volume01,
              onVolume: onVolume,
              onExport: onExport,
            ),
          ),
        );
      },
    );
  }
}

class _InspectorBody extends StatelessWidget {
  final String status;
  final String lengthText;
  final String sampleRateText;
  final String bitDepthText;
  final double volume01;
  final ValueChanged<double> onVolume;
  final VoidCallback? onExport;

  const _InspectorBody({
    required this.status,
    required this.lengthText,
    required this.sampleRateText,
    required this.bitDepthText,
    required this.volume01,
    required this.onVolume,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune_rounded, size: 16),
              SizedBox(width: 6),
              Text(
                'Inspector',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          KV(label: '狀態', value: status),
          KV(label: '總長度', value: lengthText),
          KV(label: '取樣率', value: sampleRateText),
          KV(label: '位元深度', value: bitDepthText),
          const SizedBox(height: 10),
          const Divider(height: 16, thickness: 0.4),
          const SizedBox(height: 10),
          const Text(
            '效果 / Effects',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          // 真正連到音量
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('音量 / Gain', style: TextStyle(fontSize: 11)),
              Slider(
                value: volume01.clamp(0.0, 1.0),
                min: 0,
                max: 1,
                onChanged: onVolume,
              ),
            ],
          ),

          // 先保留占位（未實作 DSP 時）
          const SliderTile(label: '混響 / Reverb', value: 0.20),
          const SliderTile(label: '高通 / HPF', value: 0.10),

          const SizedBox(height: 12),
          PrimaryBtn(
            icon: Icons.file_download_done_rounded,
            label: '匯出 WAV',
            onPressed: onExport,
          ),
        ],
      ),
    );
  }
}
