// MiniFooterBar (compact v2)
// 修正：大幅縮減高度/間距；窄寬度自動隱藏次要文字；圖示-only；時間單行。

import 'dart:ui' show FontFeature, ImageFilter;
import 'package:flutter/material.dart';
import 'package:clipnote_audio/modules/services/track_lane_service.dart'
    show TimelineScale, kTimelineScaleOrder, TimelineScaleX;
// MiniFooterBar — draggable scrub
import 'dart:ui' show FontFeature, ImageFilter;
import 'package:flutter/material.dart';
import 'package:clipnote_audio/modules/services/track_lane_service.dart'
    show TimelineScale, kTimelineScaleOrder;

class MiniFooterBar extends StatefulWidget {
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
  final VoidCallback onPlayPause;
  final ValueChanged<int> onSeekMs;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final TimelineScale currentScale;
  final ValueChanged<TimelineScale> onSetScale;
  final bool compact;

  const MiniFooterBar({
    super.key,
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
    required this.onPlayPause,
    required this.onSeekMs,
    required this.onImport,
    required this.onExport,
    required this.currentScale,
    required this.onSetScale,
    this.compact = true,
  });

  @override
  State<MiniFooterBar> createState() => _MiniFooterBarState();
}

class _MiniFooterBarState extends State<MiniFooterBar> {
  // 拖曳暫存（0..1）
  double? _dragV;

  bool get _isScrubbing => _dragV != null;
  bool _resumeAfterScrub = false; // 拖曳前正在播？結束後要續播
  DateTime _lastSeekSentAt = DateTime.fromMillisecondsSinceEpoch(0); // 節流時間戳
  @override
  Widget build(BuildContext context) {
    final canScrub = widget.durationMs > 0;

    // 目前顯示的時間（拖曳時顯示預覽）
    final v = !canScrub
        ? 0.0
        : (_dragV ?? (widget.positionMs / widget.durationMs)).clamp(0.0, 1.0);
    final displayMs = (v * (widget.durationMs > 0 ? widget.durationMs : 1))
        .round();

    // 尺寸參數（compact 與一般）
    final hBar = widget.compact ? 56.0 : 86.0;
    final rad = widget.compact ? 12.0 : 16.0;
    final vPad = widget.compact ? 8.0 : 12.0;
    final playDia = widget.compact ? 44.0 : 54.0;
    final iconSz = widget.compact ? 18.0 : 20.0;
    final sliderTh = widget.compact ? 3.0 : 5.0;
    final thumbR = widget.compact ? 7.0 : 9.0;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: hBar),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(rad),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: vPad),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xE0050A12), Color(0xE00B1220)],
                  ),
                  borderRadius: BorderRadius.circular(rad),
                  border: Border.all(color: const Color(0x2226C6FF)),
                  boxShadow: const [
                    BoxShadow(color: Color(0x2216B6FF), blurRadius: 14),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final narrow = c.maxWidth < 720;
                    return Row(
                      children: [
                        NeonButton(
                          icon: Icons.library_music_rounded,
                          label: narrow ? null : '匯入',
                          baseColor: const Color(0xFF00E5FF),
                          dense: true,
                          onPressed: widget.onImport,
                          iconSize: iconSz,
                        ),
                        const SizedBox(width: 8),
                        NeonRoundButton(
                          onPressed: widget.onPlayPause,
                          icon: widget.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          colors: const [Color(0xFF7C4DFF), Color(0xFF915CFF)],
                          diameter: playDia,
                          iconSize: widget.compact ? 22 : 26,
                        ),
                        const SizedBox(width: 10),
                        _DividerV(height: widget.compact ? 36 : 44),
                        const SizedBox(width: 10),

                        // —— 可拖曳短時間軸 ——
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: sliderTh,
                              activeTrackColor: const Color(0xFF7C4DFF),
                              inactiveTrackColor: const Color(0x33FFFFFF),
                              thumbColor: const Color(0xFFB89AFF),
                              overlayShape: SliderComponentShape.noOverlay,
                              thumbShape: RoundSliderThumbShape(
                                enabledThumbRadius: thumbR,
                              ),
                            ),
                            child: Slider(
                              value: v, // v 仍是 (_dragV ?? position/duration)
                              min: 0,
                              max: 1,

                              // 開始拖曳：記錄狀態，若正在播放則先暫停
                              onChangeStart: canScrub
                                  ? (nv) {
                                      setState(() => _dragV = nv);
                                      if (widget.isPlaying) {
                                        _resumeAfterScrub = true;
                                        widget.onPlayPause(); // 暫停
                                      } else {
                                        _resumeAfterScrub = false;
                                      }
                                    }
                                  : null,

                              // 拖曳中：更新 UI，並以 33ms 節流觸發 onSeekMs（邊拖邊跳轉）
                              onChanged: canScrub
                                  ? (nv) {
                                      setState(() => _dragV = nv);

                                      final now = DateTime.now();
                                      if (now
                                              .difference(_lastSeekSentAt)
                                              .inMilliseconds >=
                                          33) {
                                        _lastSeekSentAt = now;
                                        final ms = (nv * widget.durationMs)
                                            .round();
                                        widget.onSeekMs(ms);
                                      }
                                    }
                                  : null,

                              // 放開：送最後一次 seek，必要時恢復播放
                              onChangeEnd: canScrub
                                  ? (nv) {
                                      setState(() => _dragV = null);

                                      final ms = (nv * widget.durationMs)
                                          .round();
                                      widget.onSeekMs(ms); // 收尾保險一次

                                      if (_resumeAfterScrub) {
                                        _resumeAfterScrub = false;
                                        widget.onPlayPause(); // 續播
                                      }
                                    }
                                  : null,
                            ),
                          ),
                        ),

                        const SizedBox(width: 10),

                        _TimeLine(
                          positionMs: displayMs, // 拖曳時顯示預覽時間
                          durationMs: widget.durationMs,
                          showTotal: !(c.maxWidth < 720),
                          compact: widget.compact,
                        ),

                        const SizedBox(width: 10),
                        _DividerV(height: widget.compact ? 36 : 44),
                        const SizedBox(width: 10),

                        _ScaleMenuButton(
                          current: widget.currentScale,
                          onSelected: widget.onSetScale,
                          size: widget.compact ? 32 : 36,
                          iconSize: widget.compact ? 18 : 18,
                        ),
                        const SizedBox(width: 8),

                        NeonButton(
                          icon: Icons.download_rounded,
                          label: narrow ? null : '匯出 MP3',
                          baseColor: const Color(0xFF7C4DFF),
                          dense: true,
                          onPressed: widget.onExport,
                          iconSize: iconSz,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// —— 單行時間（例：時間 00:00.000 · 總長 05:05.536）——
class _TimeLine extends StatelessWidget {
  final int positionMs, durationMs;
  final bool showTotal, compact;
  const _TimeLine({
    required this.positionMs,
    required this.durationMs,
    required this.showTotal,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final txt = TextStyle(
      fontSize: compact ? 12 : 13,
      color: Colors.white,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
      shadows: const [Shadow(blurRadius: 4, color: Color(0x3300E5FF))],
    );
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x220E1420),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x2241D9FF)),
      ),
      child: Text(
        showTotal
            ? '時間 ${_fmt(positionMs)} · 總長 ${_fmt(durationMs)}'
            : '時間 ${_fmt(positionMs)}',
        style: txt,
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

class _ScaleMenuButton extends StatelessWidget {
  final TimelineScale current;
  final ValueChanged<TimelineScale> onSelected;
  final double size;
  final double iconSize;
  const _ScaleMenuButton({
    required this.current,
    required this.onSelected,
    this.size = 36,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TimelineScale>(
      tooltip: '時間軸縮放',
      offset: const Offset(0, -8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: const Color(0xFF151A22),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final s in kTimelineScaleOrder) _item(s, s.label, current),
      ],
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0x3322D3EE),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x3341D9FF)),
        ),
        child: Icon(
          Icons.zoom_in_map_rounded,
          color: Colors.white,
          size: iconSize,
        ),
      ),
    );
  }

  PopupMenuItem<TimelineScale> _item(
    TimelineScale v,
    String label,
    TimelineScale cur,
  ) {
    final selected = v == cur;
    return PopupMenuItem<TimelineScale>(
      value: v,
      child: Row(
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 18,
            color: selected ? const Color(0xFF22D3EE) : Colors.white70,
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}

/// ————— 霓虹按鈕（矩形，可緊湊） —————
class NeonButton extends StatelessWidget {
  final IconData icon;
  final String? label; // 允許 null：圖示-only
  final Color baseColor;
  final VoidCallback onPressed;
  final bool dense;
  final double iconSize;

  const NeonButton({
    super.key,
    required this.icon,
    required this.baseColor,
    required this.onPressed,
    this.label,
    this.dense = false,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final c1 = baseColor;
    final c2 = _tint(baseColor, 0.18);
    final padH = dense ? 10.0 : 16.0;
    final padV = dense ? 8.0 : 12.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [c1, c2]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: c1.withOpacity(0.35), blurRadius: 14)],
          ),
          child: Row(
            children: [
              Icon(icon, size: iconSize, color: Colors.white),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label!,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    fontSize: dense ? 12 : 13,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 2),
                    ],
                  ),
                ),
              ],
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

/// ————— 霓虹按鈕（圓形，支援縮小） —————
class NeonRoundButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final List<Color> colors;
  final double diameter;
  final double iconSize;

  const NeonRoundButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.colors,
    this.diameter = 54,
    this.iconSize = 26,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkResponse(
        onTap: onPressed,
        radius: diameter / 2 + 4,
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: colors),
            boxShadow: [
              BoxShadow(color: colors.first.withOpacity(0.40), blurRadius: 18),
            ],
          ),
          child: Icon(icon, size: iconSize, color: Colors.white),
        ),
      ),
    );
  }
}

class _DividerV extends StatelessWidget {
  final double height;
  const _DividerV({this.height = 44});

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: height,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x1126C6FF), Color(0x4426C6FF), Color(0x1126C6FF)],
      ),
    ),
  );
}
