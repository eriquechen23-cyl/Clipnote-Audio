import 'dart:ui' show FontFeature, ImageFilter;
import 'package:flutter/material.dart';

class MiniFooterBar extends StatelessWidget {
  final bool isPlaying;
  final int positionMs;
  final int durationMs;

  final VoidCallback onPlayPause;
  final ValueChanged<int> onSeekMs; // 拖動短時間軸
  final VoidCallback onImport; // 匯入音檔
  final VoidCallback onExport; // 匯出 MP3

  const MiniFooterBar({
    super.key,
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
    required this.onPlayPause,
    required this.onSeekMs,
    required this.onImport,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final canScrub = durationMs > 0;
    final v = canScrub ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 86),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  // 深色到更深色的小漸層，提對比
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xF0050A12), Color(0xF00B1220)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x3326C6FF)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x3326C6FF),
                      blurRadius: 22,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Color(0x3300E5FF),
                      blurRadius: 30,
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // 匯入
                    NeonButton(
                      icon: Icons.library_music_rounded,
                      label: '匯入',
                      baseColor: const Color(0xFF00E5FF),
                      onPressed: onImport,
                    ),

                    const SizedBox(width: 10),

                    // 播放/暫停（圓形霓虹）
                    NeonRoundButton(
                      onPressed: onPlayPause,
                      icon: isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      colors: const [Color(0xFF7C4DFF), Color(0xFF915CFF)],
                    ),

                    const SizedBox(width: 14),
                    _DividerV(),
                    const SizedBox(width: 12),

                    // —— 短時間軸 —— 高對比滑桿
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 5,
                          activeTrackColor: const Color(0xFF7C4DFF),
                          inactiveTrackColor: const Color(0x33FFFFFF),
                          thumbColor: const Color(0xFFB89AFF),
                          disabledActiveTrackColor: const Color(0x33555555),
                          overlayShape: SliderComponentShape.noOverlay,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 9,
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

                    // 時間 / 總長（高對比資訊晶片）
                    _NeonInfoChip(label: '時間', ms: positionMs),
                    const SizedBox(width: 8),
                    _NeonInfoChip(label: '總長', ms: durationMs),

                    const SizedBox(width: 12),
                    _DividerV(),
                    const SizedBox(width: 12),

                    // 匯出
                    NeonButton(
                      icon: Icons.download_rounded,
                      label: '匯出 MP3',
                      baseColor: const Color(0xFF7C4DFF),
                      onPressed: onExport,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ————— 霓虹按鈕（矩形） —————
class NeonButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color baseColor;
  final VoidCallback onPressed;

  const NeonButton({
    super.key,
    required this.icon,
    required this.label,
    required this.baseColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c1 = baseColor;
    final c2 = _tint(baseColor, 0.18);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [c1, c2]),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: c1.withOpacity(0.45),
                blurRadius: 18,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  shadows: [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 2,
                      offset: Offset(0, 0.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _tint(Color c, double amt) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness + amt).clamp(0, 1)).toColor();
  }
}

/// ————— 霓虹按鈕（圓形） —————
class NeonRoundButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final List<Color> colors;
  const NeonRoundButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkResponse(
        onTap: onPressed,
        radius: 28,
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: colors),
            boxShadow: [
              BoxShadow(
                color: colors.first.withOpacity(0.45),
                blurRadius: 22,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Icon(icon, size: 26, color: Colors.white),
        ),
      ),
    );
  }
}

/// ————— 高對比資訊晶片 —————
class _NeonInfoChip extends StatelessWidget {
  final String label;
  final int ms;
  const _NeonInfoChip({required this.label, required this.ms});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0x330E1420),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x3341D9FF)),
        boxShadow: const [BoxShadow(color: Color(0x2200E5FF), blurRadius: 12)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFFB7D7FF),
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _fmt(ms),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
              shadows: [Shadow(blurRadius: 6, color: Color(0x5500E5FF))],
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
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 44,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x1126C6FF), Color(0x4426C6FF), Color(0x1126C6FF)],
      ),
    ),
  );
}
