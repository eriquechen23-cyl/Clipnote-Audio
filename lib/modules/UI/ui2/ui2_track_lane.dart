// lib/modules/UI/ui2/ui2_track_lane.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:clipnote_audio/modules/services/singleTrackService.dart';
import 'package:clipnote_audio/modules/services/mainEditorService.dart';

class TrackLane extends StatefulWidget {
  final SingleTrackService track;
  final MainEditorService editor;
  final double pxPerMs;
  final int durationMs; // 編輯器總長（用來算寬度）
  final bool canEdit;

  // ★ 新增：共用的水平 ScrollController（若未提供就用內建）
  final ScrollController? scrollController;

  // ★ 新增：是否在本 lane 畫播放頭（預設 false；通常由父層統一畫一條）
  final bool showPlayhead;

  // ★ 新增：是否啟用「本 lane 自動追隨播放頭」（父層控卷軸時設 false）
  final bool autoFollow;

  const TrackLane({
    super.key,
    required this.track,
    required this.editor,
    required this.pxPerMs,
    required this.durationMs,
    required this.canEdit,
    this.scrollController,
    this.showPlayhead = false,
    this.autoFollow = true,
  });

  @override
  State<TrackLane> createState() => _TrackLaneState();
}

class _TrackLaneState extends State<TrackLane> {
  final ScrollController _ownSc = ScrollController();
  ScrollController get _sc => widget.scrollController ?? _ownSc;

  // 使用者主動捲動或拖曳時，暫停自動追隨
  bool _userScrolling = false;
  bool _userDraggingSeg = false;
  double _viewportWidth = 0;

  // 追隨參數
  static const double _followBias = 0.35; // 播放頭落在視窗寬度的 35% 處
  static const double _edgeMargin = 120; // 播放頭距離邊緣 < 這個距離就自動捲
  static const Duration _animDur = Duration(milliseconds: 120);

  @override
  void initState() {
    super.initState();
    if (widget.autoFollow) {
      widget.editor.playhead.addListener(_maybeAutoFollow);
      widget.editor.playing.addListener(_maybeAutoFollow);
      widget.track.track.addListener(_maybeAutoFollow);
    }
  }

  @override
  void didUpdateWidget(covariant TrackLane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoFollow &&
        (oldWidget.pxPerMs != widget.pxPerMs ||
            oldWidget.durationMs != widget.durationMs)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoFollow());
    }

    // 由不追隨 → 追隨：補上監聽；反之則移除
    if (!oldWidget.autoFollow && widget.autoFollow) {
      widget.editor.playhead.addListener(_maybeAutoFollow);
      widget.editor.playing.addListener(_maybeAutoFollow);
      widget.track.track.addListener(_maybeAutoFollow);
    } else if (oldWidget.autoFollow && !widget.autoFollow) {
      widget.editor.playhead.removeListener(_maybeAutoFollow);
      widget.editor.playing.removeListener(_maybeAutoFollow);
      widget.track.track.removeListener(_maybeAutoFollow);
    }
  }

  @override
  void dispose() {
    if (widget.autoFollow) {
      widget.editor.playhead.removeListener(_maybeAutoFollow);
      widget.editor.playing.removeListener(_maybeAutoFollow);
      widget.track.track.removeListener(_maybeAutoFollow);
    }
    _ownSc.dispose();
    super.dispose();
  }

  int get _laneMs => math.max(widget.durationMs, widget.track.durationMs);
  double ms2x(int ms) => ms * widget.pxPerMs;

  void _maybeAutoFollow() {
    if (!mounted || !widget.autoFollow) return;
    // 僅在播放且非使用者主動操作時追隨
    if (!widget.editor.isPlaying || _userScrolling || _userDraggingSeg) return;
    if (!_sc.hasClients || _viewportWidth <= 0) return;

    final laneWidth = ms2x(_laneMs) + 40;
    if (laneWidth <= _viewportWidth) return;

    final playheadX = ms2x(widget.editor.playheadMs).toDouble();
    final left = _sc.position.pixels;
    final right = left + _viewportWidth;

    // 播放頭已經在安全區域內就不動
    final safeLeft = left + _edgeMargin;
    final safeRight = right - _edgeMargin;
    if (playheadX >= safeLeft && playheadX <= safeRight) return;

    // 目標：把播放頭放在視窗寬度的 _followBias 處
    double targetLeft = playheadX - _viewportWidth * _followBias;
    final maxScroll = math.max(0.0, laneWidth - _viewportWidth);
    targetLeft = targetLeft.clamp(0.0, maxScroll);

    _sc.animateTo(targetLeft, duration: _animDur, curve: Curves.easeOut);
  }

  // === 片段拖曳 ===
  Segment? _dragging;
  int _dragStartMs = 0;
  double _dragStartDx = 0;

  void _onPanStart(Segment seg, DragStartDetails d) {
    if (!widget.canEdit) return;
    _dragging = seg;
    _dragStartDx = d.localPosition.dx;
    _dragStartMs = seg.dstOffsetMs;
    _userDraggingSeg = true;
    widget.editor.beginInteractiveEdit();
  }

  void _onPanUpdate(Segment seg, DragUpdateDetails d) {
    if (!widget.canEdit || _dragging == null) return;
    final dx = d.localPosition.dx - _dragStartDx;
    final rawMs = (_dragStartMs + dx / widget.pxPerMs).round();
    widget.editor.updateInteractiveDrag(
      track: widget.track,
      segment: seg,
      rawMs: rawMs.clamp(0, _laneMs),
      excludeId: seg.id,
    );
    setState(() {}); // 讓 UI 跟著動
  }

  void _onPanEnd(_) async {
    if (!widget.canEdit) return;
    _dragging = null;
    _userDraggingSeg = false;
    await widget.editor.endInteractiveEdit();
  }

  void _onTapDown(TapDownDetails d) {
    final ms = (d.localPosition.dx / widget.pxPerMs).round().clamp(0, _laneMs);
    widget.editor.seekTo(ms);
  }

  @override
  Widget build(BuildContext context) {
    final listens = Listenable.merge([
      widget.track.track,
      widget.editor.playhead,
      widget.editor.snapGuide,
    ]);

    final laneWidth = ms2x(_laneMs) + 40;

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportWidth = constraints.maxWidth;
        // 每次版面改變時嘗試自動追隨一次
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoFollow());

        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            color: const Color(0xFF0F1218),
            child: AnimatedBuilder(
              animation: listens,
              builder: (_, __) {
                return NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is UserScrollNotification &&
                        n.metrics.axis == Axis.horizontal) {
                      // 使用者主動滾動 → 暫停追隨；停止 800ms 後恢復
                      if (n.direction != ScrollDirection.idle) {
                        _userScrolling = true;
                      } else {
                        Future.delayed(const Duration(milliseconds: 800), () {
                          if (!mounted) return;
                          _userScrolling = false;
                          _maybeAutoFollow();
                        });
                      }
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _sc, // ★ 使用共用 controller
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: laneWidth,
                      height: double.infinity,
                      child: Stack(
                        children: [
                          // 1) 背景網格
                          CustomPaint(
                            size: Size(laneWidth, double.infinity),
                            painter: _GridPainter(pxPerMs: widget.pxPerMs),
                          ),
                          // 2) 波形
                          CustomPaint(
                            size: Size(laneWidth, double.infinity),
                            painter: _WaveformPainter(
                              peaks: widget.track.track.downsampledPcmPeak,
                              stepSamples: widget.track.track.downsampleStep,
                              pxPerMs: widget.pxPerMs,
                            ),
                          ),
                          // 3) 片段
                          ...widget.track.track.segments.map((seg) {
                            final x = ms2x(seg.dstOffsetMs);
                            final w = math.max(32.0, ms2x(seg.srcDurationMs));
                            return Positioned(
                              left: x,
                              top: 6,
                              width: w,
                              bottom: 6,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: (d) => _onPanStart(seg, d),
                                onPanUpdate: (d) => _onPanUpdate(seg, d),
                                onPanEnd: _onPanEnd,
                                child: _SegmentCard(
                                  name: widget.track.name,
                                  color: widget.track.color,
                                  fadeInMs: seg.fadeInMs,
                                  fadeOutMs: seg.fadeOutMs,
                                  durationMs: seg.srcDurationMs,
                                  pxPerMs: widget.pxPerMs,
                                ),
                              ),
                            );
                          }),
                          // 4) 播放頭（通常關閉，由父層統一畫一條）
                          if (widget.showPlayhead)
                            Positioned(
                              left: ms2x(widget.editor.playheadMs).toDouble(),
                              top: 0,
                              bottom: 0,
                              child: IgnorePointer(
                                child: Container(
                                  width: 2,
                                  color: Colors.redAccent,
                                ),
                              ),
                            ),
                          // 5) 磁吸指引線
                          if (widget.editor.snapGuide.value != null)
                            Positioned(
                              left: ms2x(
                                widget.editor.snapGuide.value!.ms,
                              ).toDouble(),
                              top: 0,
                              bottom: 0,
                              child: IgnorePointer(
                                child: Container(
                                  width: 1,
                                  color: Colors.cyanAccent.withOpacity(0.7),
                                ),
                              ),
                            ),
                          // 6) 點擊 Seek
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: _onTapDown,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// === 以下畫 UI 的小類保持不變 ===

class _SegmentCard extends StatelessWidget {
  final String name;
  final Color color;
  final int fadeInMs;
  final int fadeOutMs;
  final int durationMs;
  final double pxPerMs;

  const _SegmentCard({
    required this.name,
    required this.color,
    required this.fadeInMs,
    required this.fadeOutMs,
    required this.durationMs,
    required this.pxPerMs,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color.withOpacity(0.18);
    final bd = color.withOpacity(0.85);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: bd, width: 1),
      ),
      child: Stack(
        children: [
          if (fadeInMs > 0)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: CustomPaint(
                size: Size(fadeInMs * pxPerMs, double.infinity),
                painter: _FadeTrianglePainter(color: bd, leftToRight: true),
              ),
            ),
          if (fadeOutMs > 0)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: CustomPaint(
                size: Size(fadeOutMs * pxPerMs, double.infinity),
                painter: _FadeTrianglePainter(color: bd, leftToRight: false),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FadeTrianglePainter extends CustomPainter {
  final Color color;
  final bool leftToRight;
  _FadeTrianglePainter({required this.color, required this.leftToRight});

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = color.withOpacity(0.35);
    final path = Path();
    if (leftToRight) {
      path
        ..moveTo(0, s.height)
        ..lineTo(s.width, s.height)
        ..lineTo(0, 0);
    } else {
      path
        ..moveTo(s.width, s.height)
        ..lineTo(0, s.height)
        ..lineTo(s.width, 0);
    }
    path.close();
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _FadeTrianglePainter old) =>
      old.color != color || old.leftToRight != leftToRight;
}

class _GridPainter extends CustomPainter {
  final double pxPerMs;
  _GridPainter({required this.pxPerMs});

  @override
  void paint(Canvas c, Size s) {
    final pMinor = Paint()..color = const Color(0x22FFFFFF);
    final pMajor = Paint()..color = const Color(0x44FFFFFF);
    for (double x = 0; x < s.width; x += 100 * pxPerMs) {
      c.drawLine(Offset(x, 0), Offset(x, s.height), pMinor);
    }
    for (double x = 0; x < s.width; x += 1000 * pxPerMs) {
      c.drawLine(Offset(x, 0), Offset(x, s.height), pMajor);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.pxPerMs != pxPerMs;
}

class _WaveformPainter extends CustomPainter {
  final List<int> peaks; // downsampled peak values (0..32767)
  final int stepSamples; // 每個 peak 代表的樣本數
  final double pxPerMs;

  _WaveformPainter({
    required this.peaks,
    required this.stepSamples,
    required this.pxPerMs,
  });

  @override
  void paint(Canvas c, Size s) {
    if (peaks.isEmpty || stepSamples <= 0) return;

    final midY = s.height / 2;
    final paintFill = Paint()
      ..color = const Color(0xFF25D3EE).withOpacity(0.28)
      ..style = PaintingStyle.fill;
    final paintStroke = Paint()
      ..color = const Color(0xFF25D3EE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final stepMs =
        stepSamples / kSampleRate * 1000.0; // kSampleRate 來自 SingleTrackService
    final dx = stepMs * pxPerMs;

    final pathFill = Path()..moveTo(0, midY);
    final pathStrokeTop = Path();
    final pathStrokeBot = Path();

    for (int i = 0; i < peaks.length; i++) {
      final x = i * dx;
      final a = (peaks[i] / 32768.0) * (s.height * 0.45);
      final yTop = midY - a;
      final yBot = midY + a;
      if (i == 0) {
        pathStrokeTop.moveTo(x, yTop);
        pathStrokeBot.moveTo(x, yBot);
      } else {
        pathStrokeTop.lineTo(x, yTop);
        pathStrokeBot.lineTo(x, yBot);
      }
      pathFill.lineTo(x, yTop);
    }
    final lastX = (peaks.length - 1) * dx;
    pathFill
      ..lineTo(lastX, midY)
      ..lineTo(0, midY)
      ..close();

    c.drawPath(pathFill, paintFill);
    c.drawPath(pathStrokeTop, paintStroke);
    c.drawPath(
      pathStrokeBot,
      paintStroke..color = paintStroke.color.withOpacity(0.6),
    );
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.peaks != peaks ||
      old.stepSamples != stepSamples ||
      old.pxPerMs != pxPerMs;
}
