import 'package:flutter/material.dart';

class EditorFooterBar extends StatelessWidget {
  final bool isPlaying;
  final int positionMs;
  final int durationMs;

  final VoidCallback onTogglePlay;
  final VoidCallback? onStop;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final ValueChanged<int> onSeek;

  final double speed; // 0.5 ~ 2.0
  final ValueChanged<double> onSpeed; // setPlaybackRate

  final double zoomPxPerMs; // 時間軸縮放
  final double zoomMin;
  final double zoomMax;
  final ValueChanged<double> onZoom;

  final int? selStartMs; // 選區（可為 null）
  final int? selEndMs;

  const EditorFooterBar({
    super.key,
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
    required this.onTogglePlay,
    required this.onSeek,
    required this.speed,
    required this.onSpeed,
    required this.zoomPxPerMs,
    required this.zoomMin,
    required this.zoomMax,
    required this.onZoom,
    this.onStop,
    this.onPrev,
    this.onNext,
    this.selStartMs,
    this.selEndMs,
  });

  @override
  Widget build(BuildContext context) {
    final start = selStartMs ?? positionMs;
    final end = selEndMs ?? positionMs;
    final len = (end - start).clamp(0, 1 << 30);

    return _NeonGlass(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // 速度
          _SpeedChooser(speed: speed, onSpeed: onSpeed),

          const SizedBox(width: 10),
          _DividerV(),

          // 傳輸控制
          _TransportCluster(
            isPlaying: isPlaying,
            onPlayPause: onTogglePlay,
            onStop: onStop,
            onPrev: onPrev,
            onNext: onNext,
          ),

          const SizedBox(width: 10),
          _DividerV(),

          // 當前時間 / 總長
          _TimeReadout(label: '時間', ms: positionMs),
          const SizedBox(width: 14),
          _TimeReadout(label: '總長', ms: durationMs),

          const Spacer(),

          // 選區：開始 / 結束 / 長度
          _TimeReadout(label: '開始', ms: start),
          const SizedBox(width: 12),
          _TimeReadout(label: '結束', ms: end),
          const SizedBox(width: 12),
          _TimeReadout(label: '長度', ms: len),

          const SizedBox(width: 16),
          _DividerV(),
          const SizedBox(width: 12),

          // 縮放 HUD
          _ZoomHud(
            value: zoomPxPerMs,
            min: zoomMin,
            max: zoomMax,
            onChanged: onZoom,
          ),
        ],
      ),
    );
  }
}

class _TransportCluster extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback? onStop;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _TransportCluster({
    required this.isPlaying,
    required this.onPlayPause,
    this.onStop,
    this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _NeonIconButton(icon: Icons.skip_previous_rounded, onTap: onPrev),
        const SizedBox(width: 6),
        _NeonIconButton(icon: Icons.fast_rewind_rounded, onTap: onStop),
        const SizedBox(width: 6),
        _NeonPrimaryButton(
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onTap: onPlayPause,
        ),
        const SizedBox(width: 6),
        _NeonIconButton(icon: Icons.fast_forward_rounded, onTap: onStop),
        const SizedBox(width: 6),
        _NeonIconButton(icon: Icons.skip_next_rounded, onTap: onNext),
      ],
    );
  }
}

class _SpeedChooser extends StatelessWidget {
  final double speed;
  final ValueChanged<double> onSpeed;
  const _SpeedChooser({required this.speed, required this.onSpeed});

  static const List<double> _presets = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    return _NeonGlass(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          const Icon(Icons.speed_rounded, size: 18, color: Colors.white70),
          const SizedBox(width: 6),
          DropdownButton<double>(
            value: _closest(speed),
            dropdownColor: const Color(0xFF0E1420),
            style: const TextStyle(color: Colors.white),
            underline: const SizedBox.shrink(),
            items: _presets
                .map(
                  (v) => DropdownMenuItem(
                    value: v,
                    child: Text(
                      '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)}x',
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => v != null ? onSpeed(v) : null,
          ),
        ],
      ),
    );
  }

  double _closest(double v) {
    double best = _presets.first;
    double err = (v - best).abs();
    for (final k in _presets) {
      final e = (v - k).abs();
      if (e < err) {
        err = e;
        best = k;
      }
    }
    return best;
  }
}

class _TimeReadout extends StatelessWidget {
  final String label;
  final int ms;
  const _TimeReadout({required this.label, required this.ms});

  @override
  Widget build(BuildContext context) {
    return _NeonGlass(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white60),
          ),
          const SizedBox(width: 8),
          Text(
            _fmtMs(ms),
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtMs(int ms) {
    final totalMs = ms.clamp(0, 1 << 30);
    final sec = totalMs ~/ 1000;
    final m = (sec ~/ 60).toString().padLeft(1, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    final cs = (totalMs % 1000).toString().padLeft(3, '0');
    return '$m:$s.$cs';
  }
}

class _ZoomHud extends StatelessWidget {
  final double value, min, max;
  final ValueChanged<double> onChanged;
  const _ZoomHud({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _NeonGlass(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          _NeonIconButton(
            icon: Icons.remove,
            onTap: () =>
                onChanged((value - (max - min) * 0.05).clamp(min, max)),
          ),
          SizedBox(
            width: 160,
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          _NeonIconButton(
            icon: Icons.add,
            onTap: () =>
                onChanged((value + (max - min) * 0.05).clamp(min, max)),
          ),
        ],
      ),
    );
  }
}

// ———— 霓虹 UI 小組件 ————
class _NeonGlass extends StatelessWidget {
  final double height;
  final EdgeInsetsGeometry padding;
  final Widget child;
  const _NeonGlass({
    required this.height,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xCC0B0F15),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Color(0x3326C6FF), blurRadius: 18, spreadRadius: 1),
        ],
        border: Border.all(color: const Color(0x3326C6FF)),
      ),
      child: child,
    );
  }
}

class _NeonIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _NeonIconButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x6600E5FF), blurRadius: 12),
            BoxShadow(color: Color(0x667C4DFF), blurRadius: 16),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

class _NeonPrimaryButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NeonPrimaryButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF7C4DFF),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 8,
        shadowColor: const Color(0x887C4DFF),
      ),
      child: Icon(icon, size: 20),
    );
  }
}

class _DividerV extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 40, color: const Color(0x2233CCFF));
  }
}
