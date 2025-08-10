import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'audio_track.dart';
import 'fft/fft.dart';
import 'fft/fft_util.dart';

/// 音軌編輯元件（霓虹玻璃 + 波形 + 人聲熱度）
/// - 拖曳：移動整段
/// - 長按框選：重設 sourceStart/duration（剪裁）
/// - 左右手把：淡入/淡出
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
  static const double _height = 88;
  static const double _radius = 14;

  // 預覽資料（與寬度相關）
  List<double>? _env; // 0..1 波形包絡
  List<double>? _voice; // 0..1 人聲熱度
  int _previewPx = 0;
  bool _computing = false;

  double? _selStart;
  double? _selEnd;
  bool _selecting = false;

  double get _samplesPerPixel => widget.track.sampleRate / _pixelsPerSecond;

  @override
  Widget build(BuildContext context) {
    final seg = widget.track.segments.first;

    final width = (seg.duration / widget.track.sampleRate) * _pixelsPerSecond;
    final marginLeft = math.max(
      0.0,
      seg.start / widget.track.sampleRate * _pixelsPerSecond,
    );

    // 手把位置（px）
    final fadeInPx = seg.fadeIn / widget.track.sampleRate * _pixelsPerSecond;
    final fadeOutPx = seg.fadeOut / widget.track.sampleRate * _pixelsPerSecond;

    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        final deltaSamples = (d.delta.dx * _samplesPerPixel).round();
        widget.track.segments[0] = seg.copyWith(
          start: seg.start + deltaSamples,
        );
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
      onLongPressMoveUpdate: (d) =>
          setState(() => _selEnd = d.localPosition.dx),
      onLongPressEnd: (d) {
        final left = math.min(_selStart ?? 0, _selEnd ?? 0);
        final right = math.max(_selStart ?? 0, _selEnd ?? 0);
        final srcStart = (left * _samplesPerPixel).round();
        final dur = math.max(1, ((right - left) * _samplesPerPixel).round());
        widget.track.segments[0] = seg.copyWith(
          sourceStart: srcStart,
          duration: dur,
        );
        _selecting = false;
        widget.onChanged();
        setState(() {
          // 重新計算預覽（剪裁後）
          _env = null;
          _voice = null;
        });
      },
      child: LayoutBuilder(
        builder: (context, cons) {
          final targetPx = math.max(48, width).ceil();
          // 需要時才重算
          if (!_computing && (_env == null || _previewPx != targetPx)) {
            _previewPx = targetPx;
            _computePreview(targetPx);
          }

          return Container(
            margin: EdgeInsets.fromLTRB(12 + marginLeft, 8, 12, 8),
            height: _height,
            width: math.max(48, width),
            decoration: BoxDecoration(
              color: const Color(0x1018273A),
              borderRadius: BorderRadius.circular(_radius),
              border: Border.all(color: const Color(0x22FFFFFF)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x3306B6D4),
                  blurRadius: 18,
                  spreadRadius: 1,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                // 波形 + 人聲熱度繪圖
                Positioned.fill(
                  child: CustomPaint(
                    painter: _WaveVoicePainter(
                      env: _env,
                      voice: _voice,
                      neon: const [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                    ),
                  ),
                ),

                // 左側霓虹邊條
                Positioned.fill(
                  left: 0,
                  right: null,
                  child: Container(
                    width: 6,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF06B6D4), Color(0x803B82F6)],
                      ),
                    ),
                  ),
                ),

                // 標頭列：檔名 + 刪除
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.music_note, color: Colors.white70),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.track.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '刪除此音軌',
                          icon: const Icon(Icons.delete, color: Colors.white70),
                          onPressed: widget.onDelete,
                          splashRadius: 20,
                        ),
                      ],
                    ),
                  ),
                ),

                // 選取區（長按拖曳）
                if (_selecting)
                  Positioned(
                    left: math.min(_selStart ?? 0, _selEnd ?? 0),
                    width: (_selEnd == null || _selStart == null)
                        ? 0
                        : (_selEnd! - _selStart!).abs(),
                    top: 0,
                    bottom: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0x4422D3EE),
                        border: Border.all(color: const Color(0x6622D3EE)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),

                // Fade-in handle（左）
                Positioned(
                  left: math.max(0, fadeInPx - 6),
                  top: 8,
                  bottom: 8,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanUpdate: (d) {
                      final delta = (d.delta.dx * _samplesPerPixel).round();
                      final newFade = (seg.fadeIn + delta).clamp(
                        0,
                        seg.duration - seg.fadeOut,
                      );
                      widget.track.segments[0] = seg.copyWith(fadeIn: newFade);
                      widget.onChanged();
                      setState(() {});
                    },
                    child: _Handle(
                      color1: const Color(0xFF22C55E),
                      color2: const Color(0x8822C55E),
                    ),
                  ),
                ),

                // Fade-out handle（右）
                Positioned(
                  left: math.max(0, width - fadeOutPx - 6),
                  top: 8,
                  bottom: 8,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanUpdate: (d) {
                      final delta = (-d.delta.dx * _samplesPerPixel).round();
                      final newFade = (seg.fadeOut + delta).clamp(
                        0,
                        seg.duration - seg.fadeIn,
                      );
                      widget.track.segments[0] = seg.copyWith(fadeOut: newFade);
                      widget.onChanged();
                      setState(() {});
                    },
                    child: _Handle(
                      color1: const Color(0x88EF4444),
                      color2: const Color(0xFFEF4444),
                    ),
                  ),
                ),

                // 計算中淡淡遮罩（避免空白誤會）
                if (_env == null || _voice == null)
                  Positioned.fill(
                    child: Container(
                      color: const Color(0x05000000),
                      alignment: Alignment.bottomRight,
                      padding: const EdgeInsets.all(6),
                      child: const Text(
                        '解析中…',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 依寬度計算波形包絡與人聲熱度（輕量 downsample + 少量 FFT）
  Future<void> _computePreview(int pixelWidth) async {
    final seg = widget.track.segments.first;
    final samples = widget.track.samples; // Int16List
    if (samples.isEmpty) return;

    _computing = true;

    // 取剪裁後的片段
    final srcStart = seg.sourceStart.clamp(0, samples.length - 1);
    final srcEnd = (seg.sourceStart + seg.duration).clamp(0, samples.length);
    final slice = samples.sublist(srcStart, srcEnd);

    // 欄數上限（避免超大音檔卡 UI）
    final bars = math.min(900, math.max(100, pixelWidth));
    final step = slice.length / bars;

    final env = List<double>.filled(bars, 0);
    final voice = List<double>.filled(bars, 0);

    // 預計做至多 ~600 次 FFT（其餘插值）
    final maxFfts = 600;
    final fftEvery = math.max(1, (bars / maxFfts).floor());

    // 預先決定人聲頻帶的 bin 範圍（300–3400 Hz）
    final fs = widget.track.sampleRate;
    final N = fftSize;
    final k1 = (300 * N / fs).floor().clamp(1, N ~/ 2 - 1);
    final k2 = (3400 * N / fs).ceil().clamp(k1 + 1, N ~/ 2 - 1);

    for (int i = 0; i < bars; i++) {
      final a = (i * step).floor();
      final b = ((i + 1) * step).floor().clamp(a + 1, slice.length);
      // 包絡：區段最大絕對值
      int maxAbs = 0;
      // 次取樣避免 O(n^2)
      final stride = math.max(1, ((b - a) / 200).floor());
      for (int s = a; s < b; s += stride) {
        final v = slice[s].abs();
        if (v > maxAbs) maxAbs = v;
      }
      env[i] = maxAbs / 32768.0;

      // 人聲熱度：每隔 fftEvery 算一次 FFT，其餘線性補
      if (i % fftEvery == 0) {
        final center = (a + b) ~/ 2;
        final half = N ~/ 2;
        final wStart = (center - half).clamp(0, slice.length - N);
        final window = slice
            .sublist(wStart, wStart + N)
            .map((e) => e.toDouble())
            .toList();

        final bins = await FFTUtil.computeSpectrum(samples: window);
        double band = 0, total = 1e-6;
        for (int k = 1; k < bins.length; k++) {
          final v = bins[k];
          total += v;
          if (k >= k1 && k <= k2) band += v;
        }
        voice[i] = (band / total).clamp(0, 1);
      }
    }

    // 將 voice 缺的點插值
    int lastIdx = -1;
    double lastVal = 0;
    for (int i = 0; i < bars; i++) {
      if (i % fftEvery == 0) {
        if (lastIdx >= 0 && i - lastIdx > 1) {
          final gap = i - lastIdx;
          for (int t = 1; t < gap; t++) {
            final r = t / gap;
            voice[lastIdx + t] = lastVal * (1 - r) + voice[i] * r;
          }
        }
        lastIdx = i;
        lastVal = voice[i];
      }
    }
    // 末端補齊
    for (int i = lastIdx + 1; i < bars; i++) voice[i] = lastVal;

    if (!mounted) return;
    setState(() {
      _env = env;
      _voice = voice;
      _computing = false;
    });
  }
}

/// 漂亮的把手
class _Handle extends StatelessWidget {
  final Color color1, color2;
  const _Handle({required this.color1, required this.color2});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [color1, color2],
        ),
        boxShadow: [
          BoxShadow(
            color: color1.withOpacity(0.25),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

/// 繪製：底層人聲熱度、其上波形包絡（上下對稱填滿）
class _WaveVoicePainter extends CustomPainter {
  final List<double>? env; // 0..1
  final List<double>? voice; // 0..1
  final List<Color> neon;

  _WaveVoicePainter({
    required this.env,
    required this.voice,
    required this.neon,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (env == null || voice == null || env!.isEmpty || size.width <= 0) return;

    final n = env!.length;
    // 每柱寬 + 間距
    const gap = 1.0;
    final barW = (size.width - gap * (n - 1)) / n;

    // 人聲熱度底色：由藍 -> 青 -> 黃橘（高表示更可能有人聲）
    Color heat(double t) {
      t = t.clamp(0, 1);
      // 三段插值：0..0.5 藍->青；0.5..1 青->橘
      if (t < 0.5) {
        final r = t / 0.5;
        return Color.lerp(const Color(0xFF0EA5E9), const Color(0xFF22D3EE), r)!;
      } else {
        final r = (t - 0.5) / 0.5;
        return Color.lerp(const Color(0xFF22D3EE), const Color(0xFFF59E0B), r)!;
      }
    }

    // 畫熱度條（半透明鋪底）
    double x = 0;
    for (int i = 0; i < n; i++) {
      final c = heat(voice![i]).withOpacity(0.20 + 0.30 * voice![i]);
      final h = size.height;
      final rect = Rect.fromLTWH(x, 0, barW, h);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2));
      final paint = Paint()..color = c;
      canvas.drawRRect(rrect, paint);
      x += barW + gap;
    }

    // 波形包絡（上下對稱填滿）
    final path = Path();
    final midY = size.height / 2;
    x = 0;
    for (int i = 0; i < n; i++) {
      final amp = env![i].clamp(0, 1);
      final h = amp * (size.height * 0.95) / 2;
      final left = x;
      final right = x + barW;
      path.addRect(Rect.fromLTRB(left, midY - h, right, midY + h));
      x += barW + gap;
    }

    final grad = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: neon,
    ).createShader(Offset.zero & size);

    final wavePaint = Paint()
      ..shader = grad
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 2);
    canvas.drawPath(path, wavePaint);
  }

  @override
  bool shouldRepaint(covariant _WaveVoicePainter old) =>
      old.env != env || old.voice != voice || old.neon != neon;
}
