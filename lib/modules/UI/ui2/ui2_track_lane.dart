// lib/modules/UI/ui2/ui2_track_lane.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:clipnote_audio/modules/services/track_lane_service.dart';
import 'package:clipnote_audio/modules/waveform/envelope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'; // Alt 切換磁吸（桌面）
import 'package:clipnote_audio/modules/services/singleTrackService.dart';
import 'package:clipnote_audio/modules/services/mainEditorService.dart';

// enum
enum TrackLaneDragMode { longPress, horizontal }

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
  // TrackLane 的建構子多一個參數
  final TrackLaneDragMode dragMode; // required this.dragMode,
  // 當縮放變動（pxPerMs 改變）時，是否由本元件自動以「播放頭」作為錨點調整卷軸
  // 若由父層（TracksPage）以手勢縮放並自行計算錨點，請設為 false，避免互相搶卷軸。
  final bool maintainPlayheadOnZoom;

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
    required this.dragMode,
    this.maintainPlayheadOnZoom = true,
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
  final ValueNotifier<double> _scrollLeftPx = ValueNotifier(0);
  @override
  void initState() {
    super.initState();
    // 監聽自動追隨（原本就有的）
    if (widget.autoFollow) {
      widget.editor.playhead.addListener(_maybeAutoFollow);
      widget.editor.playing.addListener(_maybeAutoFollow);
      widget.track.track.addListener(_maybeAutoFollow);
    }
    RawKeyboard.instance.addListener(_onKey);

    // ★ 監聽水平滾動 → 更新 _scrollLeftPx
    _sc.addListener(_onScrollChanged);
    // 初始值
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_sc.hasClients) _scrollLeftPx.value = _sc.position.pixels;
    });
  }

  void _onScrollChanged() {
    if (!_sc.hasClients) return;
    _scrollLeftPx.value = _sc.position.pixels;
  }

  @override
  void dispose() {
    if (widget.autoFollow) {
      widget.editor.playhead.removeListener(_maybeAutoFollow);
      widget.editor.playing.removeListener(_maybeAutoFollow);
      widget.track.track.removeListener(_maybeAutoFollow);
    }
    RawKeyboard.instance.removeListener(_onKey);
    _sc.removeListener(_onScrollChanged); // ★ 解除
    _scrollLeftPx.dispose(); // ★ 釋放
    _ownSc.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TrackLane oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ 當縮放變動（pxPerMs 改變）時，讓視窗仍然對準「原本畫面裡的播放頭位置」
    // 也可以改成「固定讓播放頭落在 35% 視窗處」（下面備註有替代寫法）
    if (widget.maintainPlayheadOnZoom &&
        oldWidget.pxPerMs != widget.pxPerMs &&
        _sc.hasClients &&
        _viewportWidth > 0) {
      final oldLeft = _sc.position.pixels;

      // 播放頭在「舊縮放下」的世界座標（px）
      final phXOld = oldWidget.pxPerMs * widget.editor.playheadMs;
      // 播放頭相對於視窗左側的像素位置（保持這個位置不變）
      final phInViewPx = phXOld - oldLeft;

      // 播放頭在「新縮放下」的世界座標（px）
      final phXNew = widget.pxPerMs * widget.editor.playheadMs;

      // 新內容寬
      final laneWidthNew = widget.pxPerMs * _laneMs + 40;
      final maxScroll = math.max(0.0, laneWidthNew - _viewportWidth);

      // 目標左邊界 = 讓播放頭維持在原畫面相對位置
      double newLeft = phXNew - phInViewPx;
      newLeft = newLeft.clamp(0.0, maxScroll);

      // 立刻套用（避免動畫暈眩；你也能改 animateTo）
      _sc.jumpTo(newLeft);
    }

    // 原本就有的自動追隨排程（保留）
    if (widget.autoFollow &&
        (oldWidget.pxPerMs != widget.pxPerMs ||
            oldWidget.durationMs != widget.durationMs)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoFollow());
    }

    // 由不追隨 → 追隨：補上監聽；反之則移除（保留你原來的）
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
    if (widget.laneSvc.isDragging) return; // 正在或剛結束拖曳，不處理
    widget.laneSvc.clearSelection();
    final ms = (d.localPosition.dx / widget.pxPerMs).round().clamp(0, _laneMs);
    widget.editor.seekTo(ms);
  }

  void _onSegmentTap(Segment seg) {
    widget.laneSvc.selectSegment(laneId: widget.laneId, segId: seg.id);
  }

  // --- 片段拖曳（用 HorizontalDrag，並在 pointer down 鎖滾動） ---
  // （移除未使用的 _onDragDown）

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

    final snapOnNow = widget.editor.snapEnabled.value && _snapOn; // 全域 && Alt
    widget.laneSvc.panUpdate(
      localDx: d.localPosition.dx,
      pxPerMs: widget.pxPerMs,
      laneMs: _laneMs,
      snappingEnabled: snapOnNow,
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

  // 移除長按彈出選單：刪段/切割統一改由 MiniBar 的按鈕操作
  // 保留長按拖曳模式在 dragMode == longPress 時的交互（見下方手勢綁定）

  Widget _buildSegmentGesture({required Segment seg, required Widget child}) {
    // 僅「水平拖曳」當作移動；選擇不定時才給「功能選單」
    if (widget.dragMode == TrackLaneDragMode.horizontal) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onSegmentTap(seg),

        // 拖曳 = 水平拖；被辨識後才鎖捲動
        onHorizontalDragStart: (d) {
          if (!widget.canEdit) return;
          setState(() => _scrollLocked = true); // ← 現在才鎖
          _onHorizontalDragStart(seg, d);
        },
        onHorizontalDragUpdate: (d) => _onHorizontalDragUpdate(seg, d),
        onHorizontalDragEnd: (d) async {
          await _onHorizontalDragEnd(seg, d);
          if (_scrollLocked) setState(() => _scrollLocked = false);
        },
        onHorizontalDragCancel: () async {
          _onDragCancelFor(seg);
          if (_scrollLocked) setState(() => _scrollLocked = false);
        },

        // 移除：不再提供長按/右鍵功能選單
        child: child,
      );
    }

    // === dragMode == longPress：用長按拖曳移動；選單換到右鍵/雙擊 ===
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onSegmentTap(seg),

      // 拖曳 = 長按拖
      onLongPressStart: (d) {
        if (!widget.canEdit) return;
        setState(() => _scrollLocked = true);
        // 用 panStart 啟拖：把 localPosition 丟進去
        widget.laneSvc.panStart(
          laneId: widget.laneId,
          track: widget.track,
          segment: seg,
          localDx: d.localPosition.dx,
        );
        setState(() {}); // 立即刷新選取樣式
      },
      onLongPressMoveUpdate: (d) {
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
        setState(() {});
      },
      onLongPressEnd: (d) async {
        if (!widget.canEdit) return;
        _commitSegment(seg);
        await widget.laneSvc.panEnd(postSeekMs: seg.dstOffsetMs);
        if (_scrollLocked) setState(() => _scrollLocked = false);
      },

      // 移除：不再提供雙擊/右鍵叫出選單
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final listens = Listenable.merge([
      widget.track.track,
      widget.editor.snapGuide,
      widget.laneSvc.selectedLaneId, // 當前被選的 lane
      widget.laneSvc.selectedSegmentId, // 當前被選的 segment
    ]);

    final laneWidth = ms2x(_laneMs) + 40;

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportWidth = constraints.maxWidth;
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoFollow());

        // === 只畫視窗：相關資訊由 ValueNotifier 傳遞給畫家 ===

        // 啟動一次非阻塞的封包確保（避免首次縮放/捲動卡頓）
        unawaited(widget.track.ensureEnvelopeForPxPerMs(widget.pxPerMs));
        // 拿到最接近 1px 一柱的封包層
        // 由 _WaveformWindowPainter 內部自行挑選封包層。
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
                    // 取消音軌上的水平滑動，改由 MiniBar 控制時間軸
                    physics: const NeverScrollableScrollPhysics(),
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
                          // 1) 背景網格（動態刻度 + 只畫可視區間）
                          CustomPaint(
                            size: Size(laneWidth, double.infinity),
                            painter: _GridPainterWindow(
                              pxPerMs: widget.pxPerMs,
                              scrollLeftPx: _scrollLeftPx,
                              viewportWidthPx: _viewportWidth,
                            ),
                          ),

                          // 2) 波形
                          // 2) 波形（只畫可視區間；滾動時自動 repaint）
                          CustomPaint(
                            size: Size(laneWidth, double.infinity),
                            painter: _WaveformWindowPainter(
                              env: widget.track.pickEnvelopeForPxPerMs(
                                widget.pxPerMs,
                              ),
                              fallbackPeaks:
                                  widget.track.track.downsampledPcmPeak,
                              fallbackStepSamples:
                                  widget.track.track.downsampleStep,
                              pxPerMs: widget.pxPerMs,
                              scrollLeftPx: _scrollLeftPx, // ★
                              viewportWidthPx: _viewportWidth, // ★
                            ),
                          ),

                          // 3) 片段
                          ...widget.track.track.segments.map((seg) {
                            final x = ms2x(seg.dstOffsetMs);
                            final w = math.max(32.0, ms2x(seg.srcDurationMs));
                            final selected =
                                widget.laneSvc.isLaneSelected(widget.laneId) &&
                                widget.laneSvc.isSegmentSelected(seg.id);

                            final card = _SegmentCard(
                              name: widget.track.name,
                              color: widget.track.color,
                              fadeInMs: seg.fadeInMs,
                              fadeOutMs: seg.fadeOutMs,
                              durationMs: seg.srcDurationMs,
                              pxPerMs: widget.pxPerMs,
                              selected: selected,
                            );

                            return Positioned(
                              left: x,
                              top: 6,
                              width: w,
                              bottom: 6,
                              child: _buildSegmentGesture(
                                seg: seg,
                                child: card,
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

class _GridPainterWindow extends CustomPainter {
  final double pxPerMs;
  final ValueListenable<double> scrollLeftPx; // ← 用於滑動即時重繪
  final double viewportWidthPx;

  _GridPainterWindow({
    required this.pxPerMs,
    required this.scrollLeftPx,
    required this.viewportWidthPx,
  }) : super(repaint: scrollLeftPx);

  // 推薦的時間刻度（毫秒）
  static const List<int> _niceStepsMs = [
    // 毫秒
    1, 2, 5, 10, 20, 50, 100, 200, 500,
    // 秒
    1000, 2000, 5000, 10000, 15000, 30000,
    // 分
    60000, 120000, 300000, 600000, 1800000,
    // 小時
    3600000,
  ];

  // 依目前縮放挑一個「看起來舒服」的 major 刻度，目標線距 ~ 120px
  static int _pickMajorMs(double pxPerMs, double viewportWidthPx) {
    const desiredPx = 120.0;
    for (final s in _niceStepsMs) {
      if (s * pxPerMs >= desiredPx) return s;
    }
    return _niceStepsMs.last; // 超遠視野，用最大的
  }

  // 挑 minor 刻度，確保線距 ≥ 18px，否則就不要 minor
  static int? _pickMinorMs(int majorMs, double pxPerMs) {
    const minMinorPx = 18.0;
    // 優先 1/6、1/5、1/4、1/2
    for (final div in [6, 5, 4, 2]) {
      if ((majorMs / div) * pxPerMs >= minMinorPx) {
        return (majorMs / div).round();
      }
    }
    return null; // 太擠就不畫 minor
  }

  @override
  void paint(Canvas c, Size s) {
    final leftPx = scrollLeftPx.value;
    final viewMsStart = (leftPx / pxPerMs).floor();
    final viewMsEnd = viewMsStart + (viewportWidthPx / pxPerMs).ceil();

    final majorMs = _pickMajorMs(pxPerMs, viewportWidthPx);
    final minorMs = _pickMinorMs(majorMs, pxPerMs);

    final pMinor = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;
    final pMajor = Paint()
      ..color = const Color(0x44FFFFFF)
      ..strokeWidth = 1.25;

    // 畫 minor（若有）
    if (minorMs != null) {
      final startMinor = (viewMsStart ~/ minorMs) * minorMs;
      for (int t = startMinor; t <= viewMsEnd; t += minorMs) {
        // 避免畫到 major 的位置（讓 major 蓋上去）
        if (t % majorMs == 0) continue;
        final x = t * pxPerMs;
        if (x < leftPx - 2 || x > leftPx + viewportWidthPx + 2) continue;
        c.drawLine(Offset(x, 0), Offset(x, s.height), pMinor);
      }
    }

    // 畫 major
    final startMajor = (viewMsStart ~/ majorMs) * majorMs;
    for (int t = startMajor; t <= viewMsEnd; t += majorMs) {
      final x = t * pxPerMs;
      if (x < leftPx - 2 || x > leftPx + viewportWidthPx + 2) continue;
      c.drawLine(Offset(x, 0), Offset(x, s.height), pMajor);

      // 在上方畫刻度標籤（含單位）
      final label = _fmtTimeUnit(t);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xCCFFFFFF),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final lx = x - tp.width / 2;
      if (lx + tp.width >= leftPx && lx <= leftPx + viewportWidthPx) {
        tp.paint(c, Offset(lx, 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainterWindow old) =>
      old.pxPerMs != pxPerMs ||
      old.viewportWidthPx != viewportWidthPx ||
      old.scrollLeftPx != scrollLeftPx;

  // 將毫秒轉為帶單位的字串（ms / s / m / h）
  static String _fmtTimeUnit(int ms) {
    if (ms < 1000) return '${ms}ms';
    final sec = ms / 1000.0;
    if (sec < 60) {
      // 小於 10 秒顯示 1 位小數
      if (sec < 10) {
        return '${sec.toStringAsFixed(1)}s';
      }
      return '${sec.round()}s';
    }
    final min = sec / 60.0;
    if (min < 60) {
      // 小於 10 分顯示 1 位小數
      if (min < 10) {
        return '${min.toStringAsFixed(1)}m';
      }
      return '${min.round()}m';
    }
    final hour = min / 60.0;
    if (hour < 10) {
      return '${hour.toStringAsFixed(1)}h';
    }
    return '${hour.round()}h';
  }
}

// （移除未使用的舊 _WaveformPainter，現改用視窗化畫家）

class _WaveformWindowPainter extends CustomPainter {
  final EnvelopeLevel? env; // min/max 封包
  final List<int> fallbackPeaks; // 舊峰值
  final int fallbackStepSamples;
  final double pxPerMs;

  // ★ 新增：由畫家直接讀目前滾動位移與視窗寬（像素）
  final ValueListenable<double> scrollLeftPx;
  final double viewportWidthPx;

  _WaveformWindowPainter({
    required this.env,
    required this.fallbackPeaks,
    required this.fallbackStepSamples,
    required this.pxPerMs,
    required this.scrollLeftPx, // <—
    required this.viewportWidthPx, // <—
  }) : super(repaint: scrollLeftPx); // ★ 關鍵：滾動就 repaint

  @override
  void paint(Canvas c, Size s) {
    c.clipRect(Offset.zero & s);

    // 由滾動位移推導目前的可視毫秒區間
    final leftPx = scrollLeftPx.value;
    final int viewMsStart = (leftPx / pxPerMs).floor();
    final int viewMsEnd = viewMsStart + (viewportWidthPx / pxPerMs).ceil();

    final midY = s.height / 2;
    final ampY = (s.height * 0.44);

    if (env != null && env!.length > 0) {
      final e = env!;
      final i0 = e.indexFromMs(viewMsStart);
      final i1 = e.indexFromMs(viewMsEnd);
      final paint = Paint()
        ..strokeWidth = 1.0
        ..color = const Color(0xFF94A3B8);

      for (int i = i0; i <= i1 && i < e.length; i++) {
        final x = e.msAt(i) * pxPerMs; // 絕對座標（不要扣 viewMsStart）
        if (x < leftPx - 2 || x > leftPx + viewportWidthPx + 2) continue; // 小快篩
        final vMin = (e.minVals[i] / 32768.0).clamp(-1.0, 1.0);
        final vMax = (e.maxVals[i] / 32768.0).clamp(-1.0, 1.0);
        final y1 = midY - vMax * ampY;
        final y2 = midY - vMin * ampY;
        c.drawLine(Offset(x, y1), Offset(x, y2), paint);
      }
      return;
    }

    // 回退：舊 peaks
    final step = math.max(1, fallbackStepSamples);
    const sr = 48000;
    int indexFromMs(int ms) => (((ms * sr) ~/ 1000) ~/ step).clamp(
      0,
      math.max(0, fallbackPeaks.length - 1),
    );
    int msAt(int idx) => ((idx * step) * 1000) ~/ sr;

    final i0 = indexFromMs(viewMsStart);
    final i1 = indexFromMs(viewMsEnd);
    final paint = Paint()
      ..strokeWidth = 1.0
      ..color = const Color(0xFF8B9CB8);

    for (int i = i0; i <= i1 && i < fallbackPeaks.length; i++) {
      final x = msAt(i) * pxPerMs; // 絕對座標
      if (x < leftPx - 2 || x > leftPx + viewportWidthPx + 2) continue;
      final p = (fallbackPeaks[i] / 32768.0).clamp(0.0, 1.0);
      final y1 = midY - p * ampY;
      final y2 = midY + p * ampY;
      c.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformWindowPainter old) =>
      old.env != env ||
      old.fallbackPeaks != fallbackPeaks ||
      old.fallbackStepSamples != fallbackStepSamples ||
      old.pxPerMs != pxPerMs ||
      old.viewportWidthPx != viewportWidthPx ||
      old.scrollLeftPx != scrollLeftPx; // repaint 已處理滾動值
}
