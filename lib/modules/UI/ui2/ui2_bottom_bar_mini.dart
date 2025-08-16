import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';

class MiniFooterBar extends StatelessWidget {
  final bool isPlaying;
  final int positionMs;
  final int durationMs;

  final VoidCallback onPlayPause;
  final ValueChanged<int> onSeekMs; // 拖動短時間軸
  final VoidCallback onImport; // 匯入音檔
  final VoidCallback onExportMp3; // 匯出 MP3

  const MiniFooterBar({
    super.key,
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
    required this.onPlayPause,
    required this.onSeekMs,
    required this.onImport,
    required this.onExportMp3,
  });

  @override
  Widget build(BuildContext context) {
    final canScrub = durationMs > 0;
    final v = canScrub ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 78),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xCC0B0F15),
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(color: Color(0x3326C6FF), blurRadius: 18),
            ],
            border: Border.all(color: const Color(0x3326C6FF)),
          ),
          child: Row(
            children: [
              // 匯入
              ElevatedButton.icon(
                onPressed: onImport,
                style: _btnStyle(const Color(0xFF2EC6FF)),
                icon: const Icon(Icons.library_music_rounded, size: 18),
                label: const Text(
                  '匯入',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),

              const SizedBox(width: 12),

              // 播放/暫停
              ElevatedButton(
                onPressed: onPlayPause,
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: const Color(0xFF7C4DFF),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 8,
                  shadowColor: const Color(0x887C4DFF),
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 22,
                ),
              ),

              const SizedBox(width: 14),
              _DividerV(),
              const SizedBox(width: 12),

              // —— 短時間軸（置中，避免重疊）——
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    overlayShape: SliderComponentShape.noOverlay,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                  ),
                  child: Slider(
                    value: v,
                    min: 0,
                    max: 1,
                    onChanged: canScrub ? (_) {} : null,
                    onChangeEnd: canScrub
                        ? (nv) => onSeekMs((nv * durationMs).round())
                        : null,
                  ),
                ),
              ),

              const SizedBox(width: 12),
              // 時間/總長
              _TimeBox(label: '時間', ms: positionMs),
              const SizedBox(width: 8),
              _TimeBox(label: '總長', ms: durationMs),

              const SizedBox(width: 12),
              _DividerV(),
              const SizedBox(width: 12),

              // 匯出 MP3
              ElevatedButton.icon(
                onPressed: onExportMp3,
                style: _btnStyle(const Color(0xFF6C63FF)),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text(
                  '匯出 MP3',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ButtonStyle _btnStyle(Color bg) => ElevatedButton.styleFrom(
    foregroundColor: Colors.white,
    backgroundColor: bg,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    elevation: 8,
    shadowColor: bg.withOpacity(0.5),
  );
}

class _TimeBox extends StatelessWidget {
  final String label;
  final int ms;
  const _TimeBox({required this.label, required this.ms});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0x220E1420),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x2233CCFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white60),
          ),
          const SizedBox(width: 8),
          Text(
            _fmt(ms),
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(int ms) {
    final msec = ms.clamp(0, 1 << 30);
    final sec = msec ~/ 1000;
    final m = (sec ~/ 60).toString().padLeft(1, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    final cs = (msec % 1000).toString().padLeft(3, '0');
    return '$m:$s.$cs';
  }
}

class _DividerV extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 40, color: const Color(0x2233CCFF));
}
