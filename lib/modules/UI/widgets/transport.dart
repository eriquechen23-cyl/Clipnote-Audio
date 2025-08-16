// lib/modules/UI/widgets/transport.dart
import 'package:flutter/material.dart';

class TransportBar extends StatelessWidget {
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
  final VoidCallback onTogglePlay;
  final ValueChanged<int> onSeek;
  final double meterValue;

  const TransportBar({
    super.key,
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
    required this.onTogglePlay,
    required this.onSeek,
    required this.meterValue,
  });

  String _fmt(int ms) {
    final d = Duration(milliseconds: ms);
    String two(int n) => n.toString().padLeft(2, '0');
    final mm = two(d.inMinutes.remainder(60));
    final ss = two(d.inSeconds.remainder(60));
    final cs = two((d.inMilliseconds.remainder(1000) / 10).floor());
    return '$mm:$ss.$cs';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = durationMs <= 0 ? 0.0 : (positionMs / durationMs).clamp(0.0, 1.0);

    // UI2 色票（可調）
    const playBg = Color(0xFF232531);
    const knob = Color(0xFF7C63D3);
    final trackBg = Colors.white.withOpacity(0.30);
    final timeStyle = theme.textTheme.labelMedium?.copyWith(
      color: Colors.black.withOpacity(0.65),
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return Row(
      children: [
        // 大圓形播放鍵
        _CircleBtn(isPlaying: isPlaying, onPressed: onTogglePlay, bg: playBg),
        const SizedBox(width: 12),

        // 位置滑桿
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: knob,
              inactiveTrackColor: trackBg,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9.0),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: t,
              onChanged: (v) => onSeek((v * durationMs).round()),
            ),
          ),
        ),

        const SizedBox(width: 10),

        // 時間碼
        Text(_fmt(positionMs), style: timeStyle),

        const SizedBox(width: 12),

        // 右側電平條（迷你）
        _MiniMeter(value: meterValue),
      ],
    );
  }
}

/// 播放/暫停圓形按鍵
class _CircleBtn extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPressed;
  final Color bg;

  const _CircleBtn({
    required this.isPlaying,
    required this.onPressed,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            size: 22,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// 右側迷你電平條
class _MiniMeter extends StatelessWidget {
  final double value; // 0..1
  const _MiniMeter({required this.value});

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(100),
      child: Container(
        width: 86,
        height: 10,
        color: Colors.black.withOpacity(0.36),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: v,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF60646C), Color(0xFF2B2E35)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
