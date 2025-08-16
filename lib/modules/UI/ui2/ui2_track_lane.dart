// lib/modules/UI/ui2/ui2_track_lane.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:clipnote_audio/modules/services/track_lane_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'; // Alt 切換磁吸（桌面）
import 'package:clipnote_audio/modules/services/singleTrackService.dart';
import 'package:clipnote_audio/modules/services/mainEditorService.dart';

class TrackLane extends StatefulWidget {
  final String laneId; // 唯一 lane ID（例如 "lane-0"）
  final TrackLaneService laneSvc; // 共用 Service（父層傳入）
  final SingleTrackService track;
  final MainEditorService editor;
  final double pxPerMs;
  final int durationMs; // 編輯器總長（用來算寬度）
  final bool canEdit;

  final ScrollController? scrollController; // 共用水平卷軸（可選）
  final bool showPlayhead; // 是否在本 lane 畫播放頭
  final bool autoFollow; // 是否啟用自動追隨

  const TrackLane({
    super.key,
    required this.laneId,
    required this.laneSvc,
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
  bool get _userDraggingSeg => widget.laneSvc.isDragging;
  bool _userScrolling = false;
  double _viewportWidth = 0;

  // 追隨參數
  static const double _followBias = 0.35; // 播放頭落在視窗寬度的 35% 處
  static const double _edgeMargin = 120; // 播放頭距離邊緣 < 這個距離就自動捲
  static const Duration _animDur = Duration(milliseconds: 120);

  // Alt 臨時關閉磁吸 + 鎖捲動
  bool _snapOn = true;
  bool _scrollLocked = false; // ★ 拖曳期間關閉水平滾動，避免手勢被 ScrollView 搶走

  @override
  void initState() {
    super.initState();
    if (widget.autoFollow) {
      widget.editor.playhead.addListener(_maybeAutoFollow);
      widget.editor.playing.addListener(_maybeAutoFollow);
      widget.track.track.addListener(_maybeAutoFollow);
    }
    RawKeyboard.instance.addListener(_onKey); // Alt 切換磁吸
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
    RawKeyboard.instance.removeListener(_onKey);
    _ownSc.dispose();
    super.dispose();
  }

  // === 工具 ===
  int get _laneMs => math.max(widget.durationMs, widget.track.durationMs);
  double ms2x(int ms) => ms * widget.pxPerMs;

  void _onKey(RawKeyEvent e) {
    final altNow =
        RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.altLeft) ||
        RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.altRight);
    final newSnapOn = !altNow;
    if (newSnapOn != _snapOn) setState(() => _snapOn = newSnapOn);
  }

  void _maybeAutoFollow() {
    if (!mounted || !widget.autoFollow) return;
    if (!widget.editor.isPlaying || _userScrolling || _userDraggingSeg) return;
    if (!_sc.hasClients || _viewportWidth <= 0) return;

    final laneWidth = ms2x(_laneMs) + 40;
    if (laneWidth <= _viewportWidth) return;

    final playheadX = ms2x(widget.editor.playheadMs).toDouble();
    final left = _sc.position.pixels;
    final right = left + _viewportWidth;

    final safeLeft = left + _edgeMargin;
    final safeRight = right - _edgeMargin;
    if (playheadX >= safeLeft && playheadX <= safeRight) return;

    double targetLeft = playheadX - _viewportWidth * _followBias;
    final maxScroll = math.max(0.0, laneWidth - _viewportWidth);
    targetLeft = targetLeft.clamp(0.0, maxScroll);

    _sc.animateTo(targetLeft, duration: _animDur, curve: Curves.easeOut);
  }

  // === 背景/片段互動 ===
  void _onBackgroundTapUp(TapUpDetails d) {
    widget.laneSvc.clearSelection(); // 點空白清除選取
    final ms = (d.localPosition.dx / widget.pxPerMs).round().clamp(0, _laneMs);
    widget.editor.seekTo(ms);
  }

  void _onSegmentTap(Segment seg) {
    widget.laneSvc.selectSegment(laneId: widget.laneId, segId: seg.id);
  }

  // --- 片段拖曳（用 HorizontalDrag，並在 pointer down 鎖滾動） ---
  void _onDragDown(PointerDownEvent _) {
    // 指針按下就先鎖滾動，避免手勢被 ScrollView 搶走
    if (!_scrollLocked) setState(() => _scrollLocked = true);
  }

  // ★ 提交目前 segment 的最終位置（寫回資料層）
  void _commitSegment(Segment seg) {
    widget.track.setSegmentOffset(seg, newDstOffsetMs: seg.dstOffsetMs);
  }

  void _onHorizontalDragStart(Segment seg, DragStartDetails d) {
    if (!widget.canEdit) return;

    final started = widget.laneSvc.panStart(
      laneId: widget.laneId,
      track: widget.track,
      segment: seg,
      localDx: d.localPosition.dx,
    );

    // 若是「第一次只是選取」，這次拖曳不啟動：解鎖滾動（讓使用者再拖一次就會真的拖）
    if (!started) {
      if (_scrollLocked) setState(() => _scrollLocked = false);
      return;
    }
    // started == true：維持鎖滾動直到拖曳結束
  }

  void _onHorizontalDragUpdate(Segment seg, DragUpdateDetails d) {
    if (!widget.canEdit || !widget.laneSvc.isDragging) return;

    widget.laneSvc.panUpdate(
      localDx: d.localPosition.dx,
      pxPerMs: widget.pxPerMs,
      laneMs: _laneMs,
      snappingEnabled: _snapOn,
    );

    widget.laneSvc.autoScrollWhileDragging(
      controller: _sc,
      viewportWidth: _viewportWidth,
      pxPerMs: widget.pxPerMs,
      laneMs: _laneMs,
      edgeMargin: _edgeMargin,
    );

    setState(() {}); // 僅移動 Positioned
  }

  Future<void> _onHorizontalDragEnd(Segment seg, _) async {
    if (!widget.canEdit) return;
    _commitSegment(seg); // 保險提交
    await widget.laneSvc.panEnd(postSeekMs: seg.dstOffsetMs); // ★ 傳新位置
    if (_scrollLocked) setState(() => _scrollLocked = false);
  }

  void _onDragCancelFor(Segment seg) async {
    if (_scrollLocked) setState(() => _scrollLocked = false);
    if (!widget.canEdit) return;
    _commitSegment(seg); // 保險提交
    await widget.laneSvc.panEnd(postSeekMs: seg.dstOffsetMs); // ★ 傳新位置
  }

  Future<bool> _confirmDeleteSegment(BuildContext context, Segment seg) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('刪除此段？'),
            content: Text(
              '起點 ${seg.dstOffsetMs} ms、長度 ${seg.srcDurationMs} ms',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('刪除'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _onSegmentLongPressStart(
    Segment seg,
    LongPressStartDetails d,
  ) async {
    final pos = d.globalPosition;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: const [
        PopupMenuItem(value: 'here', child: Text('在此處切割')),
        PopupMenuItem(value: 'playhead', child: Text('在播放頭切割')),
        PopupMenuItem(value: 'delete', child: Text('刪除此段')),
      ],
    );
    if (choice == null) return;

    if (choice == 'delete') {
      final ok = await _confirmDeleteSegment(context, seg);
      if (!ok) return;

      // 找到目前索引，刪除後選鄰近
      final segs = widget.track.track.segments;
      final idx = segs.indexOf(seg);

      widget.track.removeSegment(seg);
      // 立即刷新本軌渲染與波形 & 主混音
      widget.track.rebuildRenderedNow();
      widget.track.buildDownsampledWaveform(step: 128);
      await widget.editor.rebuildMaster();

      // 選取鄰近片段（若還有片段）
      if (segs.isNotEmpty) {
        final pick = segs[idx.clamp(0, segs.length - 1)];
        widget.laneSvc.selectSegment(laneId: widget.laneId, segId: pick.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已刪除 1 段')));
        setState(() {});
      }
      return;
    }

    // 其餘：切割
    int splitMs;
    if (choice == 'here') {
      splitMs = (seg.dstOffsetMs + d.localPosition.dx / widget.pxPerMs).round();
    } else {
      splitMs = widget.editor.playheadMs;
    }
    final start = seg.dstOffsetMs;
    final end = start + seg.srcDurationMs;
    splitMs = splitMs.clamp(start + 1, end - 1);

    final res = widget.track.splitSegment(seg, splitMs);
    if (res != null && mounted) {
      widget.track.rebuildRenderedNow();
      widget.track.buildDownsampledWaveform(step: 128);
      await widget.editor.rebuildMaster();
      widget.laneSvc.selectSegment(laneId: widget.laneId, segId: res.right.id);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已分割')));
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final listens = Listenable.merge([
      widget.track.track,
      widget.editor.playhead,
      widget.editor.snapGuide,
      widget.laneSvc.selectedLaneId, // 當前被選的 lane
      widget.laneSvc.selectedSegmentId, // 當前被選的 segment
    ]);

    final laneWidth = ms2x(_laneMs) + 40;

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportWidth = constraints.maxWidth;
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
                    controller: _sc,
                    scrollDirection: Axis.horizontal,
                    physics: _scrollLocked
                        ? const NeverScrollableScrollPhysics() // ★ 拖曳時關閉水平滾動
                        : const ClampingScrollPhysics(),
                    child: SizedBox(
                      width: laneWidth,
                      height: double.infinity,
                      child: Stack(
                        children: [
                          // 0) 背景點擊 Seek（置底）
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.deferToChild,
                              onTapUp: _onBackgroundTapUp,
                              child: const SizedBox.expand(),
                            ),
                          ),
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
                            final selected =
                                widget.laneSvc.isLaneSelected(widget.laneId) &&
                                widget.laneSvc.isSegmentSelected(seg.id);

                            return Positioned(
                              left: x,
                              top: 6,
                              width: w,
                              bottom: 6,
                              child: Listener(
                                // ★ 先攔截 pointerDown 來鎖捲動
                                onPointerDown: _onDragDown,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _onSegmentTap(seg), // 點一下先選取
                                  onHorizontalDragStart: (d) =>
                                      _onHorizontalDragStart(seg, d),
                                  onHorizontalDragUpdate: (d) =>
                                      _onHorizontalDragUpdate(seg, d),
                                  onHorizontalDragEnd: (d) =>
                                      _onHorizontalDragEnd(seg, d), // ★ 傳 seg
                                  onHorizontalDragCancel: () =>
                                      _onDragCancelFor(seg), // ★ 取消也提交
                                  onLongPressStart: (d) =>
                                      _onSegmentLongPressStart(seg, d),
                                  child: _SegmentCard(
                                    name: widget.track.name,
                                    color: widget.track.color,
                                    fadeInMs: seg.fadeInMs,
                                    fadeOutMs: seg.fadeOutMs,
                                    durationMs: seg.srcDurationMs,
                                    pxPerMs: widget.pxPerMs,
                                    selected: selected,
                                  ),
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

// === 以下畫 UI 的小類保持不變（SegmentCard 多一個 selected 參數） ===

class _SegmentCard extends StatelessWidget {
  final String name;
  final Color color;
  final int fadeInMs;
  final int fadeOutMs;
  final int durationMs;
  final double pxPerMs;
  final bool selected;

  const _SegmentCard({
    required this.name,
    required this.color,
    required this.fadeInMs,
    required this.fadeOutMs,
    required this.durationMs,
    required this.pxPerMs,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color.withOpacity(0.18);
    final bd = color.withOpacity(0.85);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? Colors.cyanAccent : bd,
          width: selected ? 2 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(0.25),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : const [],
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
