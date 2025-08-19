// ui2_pages.dart
// ignore_for_file: unnecessary_this

import 'package:clipnote_audio/modules/services/track_lane_service.dart';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:clipnote_audio/modules/UI/ui2/ui2_primitives.dart'; // Glass
import 'package:clipnote_audio/modules/services/mainEditorService.dart';
import 'package:clipnote_audio/modules/services/singleTrackService.dart';
import 'package:clipnote_audio/modules/UI/ui2/ui2_track_lane.dart';

/// 簡易「連動水平卷軸」群組：每條軌有自己的 ScrollController，
/// 任何一支滾動都會同步其他支（避免同一 controller 綁多個 Scrollable 的斷言）。
class _LinkedHScrollGroup {
  final List<ScrollController> _controllers = [];
  bool _syncing = false;

  ScrollController createController() {
    final c = ScrollController();
    c.addListener(() {
      if (_syncing) return;
      _syncing = true;
      final off = c.hasClients ? c.offset : 0.0;
      for (final other in _controllers) {
        if (other == c || !other.hasClients) continue;
        if (other.offset != off) other.jumpTo(off);
      }
      _syncing = false;
    });
    _controllers.add(c);
    return c;
  }

  double get offset => _controllers.isNotEmpty && _controllers.first.hasClients
      ? _controllers.first.offset
      : 0.0;

  void jumpTo(double offset) {
    _syncing = true;
    for (final c in _controllers) {
      if (c.hasClients) c.jumpTo(offset);
    }
    _syncing = false;
  }

  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) async {
    _syncing = true;
    final futures = <Future<void>>[];
    for (final c in _controllers) {
      if (c.hasClients)
        futures.add(c.animateTo(offset, duration: duration, curve: curve));
    }
    await Future.wait(futures);
    _syncing = false;
  }

  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers.clear();
  }

  /// 保持控制器數量與軌數一致；多出的會被釋放。
  void ensureCount(int n) {
    // 加
    while (_controllers.length < n) {
      createController();
    }
    // 減
    while (_controllers.length > n) {
      final last = _controllers.removeLast();
      last.dispose();
    }
  }

  ScrollController controllerAt(int i) => _controllers[i];
}

class TracksPage extends StatefulWidget {
  final List<SingleTrackService> tracks;
  final void Function(int from, int to)? onReorder;
  final void Function(int index) onDeleteTrack;
  final int durationMs;
  final void Function(int ms) onSeekMs; // 保留接口
  final bool canEdit;
  final MainEditorService editor;
  final double pxPerMs;
  // 父層（MainEditorUI2）提供改變縮放的 setter
  final ValueChanged<double> onSetPxPerMs;
  // MiniBar 是否正在拖曳（用於暫停播放追隨並啟用拖曳追隨）
  final bool isScrubbing;
  // 共用的選取/拖曳服務（由父層提供，供剪刀等操作用）
  final TrackLaneService laneSvc;

  const TracksPage({
    super.key,
    required this.tracks,
    this.onReorder,
    required this.onDeleteTrack,
    required this.durationMs,
    required this.onSeekMs,
    required this.canEdit,
    required this.editor,
    required this.pxPerMs,
    required this.onSetPxPerMs,
    this.isScrubbing = false,
    required this.laneSvc,
  });

  @override
  State<TracksPage> createState() => _TracksPageState();
}

class _TracksPageState extends State<TracksPage> {
  // 版面參數
  static const double _listPadL = 12;
  static const double _listPadR = 12;
  static const double _headerW = 280;
  static const double _gutterW = 8;
  static const double _rowHeight = 120; // 縮小音軌列高

  // 連動的水平卷軸群組
  final _LinkedHScrollGroup _hGroup = _LinkedHScrollGroup();

  // 自動追隨控制
  bool _userHScrolling = false;
  double _viewportRightW = 0; // 右側可視寬
  static const double _followBias = 0.35; // 播放頭維持在右側 35% 位置
  static const double _edgeMargin = 120;
  static const Duration _animDur = Duration(milliseconds: 120);
  // 改由父層提供 laneSvc

  // _TracksPageState 內成員
  bool _laneTapCanceled = false; // 被長按/拖曳取消時，父層不做 seek
  // 供播放頭覆蓋層偵測卷軸改變（避免整頁 setState）
  final ValueNotifier<double> _scrollLeftVN = ValueNotifier(0);

  // 兩指縮放狀態
  bool _isPinching = false;
  double _scaleStartPxPerMs = 0.0;
  double _scaleStartScrollLeft = 0.0;
  // 縮放區域 UI 提示/強調
  bool _showZoomHint = true;
  bool _hoverZoom = false;
  Timer? _zoomHintTimer;

  @override
  void initState() {
    super.initState();
    widget.editor.playhead.addListener(_onTick);
    widget.editor.playing.addListener(_maybeAutoFollow);
    // 幾秒後自動隱藏提示
    _zoomHintTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      setState(() => _showZoomHint = false);
    });
  }

  @override
  void didUpdateWidget(covariant TracksPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 軌數改變時，調整控制器數量
    _hGroup.ensureCount(widget.tracks.length);
    if (oldWidget.isScrubbing != widget.isScrubbing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoFollow());
    }
  }

  @override
  void dispose() {
    widget.editor.playhead.removeListener(_onTick);
    widget.editor.playing.removeListener(_maybeAutoFollow);
    _hGroup.dispose();
    _zoomHintTimer?.cancel();
    _scrollLeftVN.dispose();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    // 避免整頁 rebuild，交由覆蓋層 AnimatedBuilder 更新紅線
    _maybeAutoFollow();
  }

  double _ms2x(int ms) => ms * widget.pxPerMs;

  int get _laneMs {
    var ms = widget.durationMs;
    for (final t in widget.tracks) {
      if (t.durationMs > ms) ms = t.durationMs;
    }
    return ms;
  }

  void _maybeAutoFollow() {
    if (!mounted) return;
    // 播放或 MiniBar 拖曳時才追隨
    final shouldFollow = widget.editor.isPlaying || widget.isScrubbing;
    if (!shouldFollow || _viewportRightW <= 0) return;
    if (_isPinching) return; // 縮放中不自動追隨
    if (_userHScrolling) return;

    final contentW = _ms2x(_laneMs) + 40;
    if (contentW <= _viewportRightW) return;

    final phX = _ms2x(widget.editor.playheadMs).toDouble();
    final left = _hGroup.offset;
    final right = left + _viewportRightW;

    final safeLeft = left + _edgeMargin;
    final safeRight = right - _edgeMargin;
    if (phX >= safeLeft && phX <= safeRight) return;

    double targetLeft = phX - _viewportRightW * _followBias;
    final maxScroll = contentW - _viewportRightW;
    if (maxScroll < 0) return;
    targetLeft = targetLeft.clamp(0.0, maxScroll);

    _hGroup.animateTo(targetLeft, duration: _animDur, curve: Curves.easeOut);
  }

  // （移除未用的 _onLaneTapDown，拆成 select/seek 流程）

  // ===== 新增：小工具，從 global 位置換算成 ms =====
  int _globalPositionToMs({
    required BuildContext areaCtx,
    required Offset global,
    required double pxPerMs,
    required double scrollLeft,
    required int laneMs,
  }) {
    final box = areaCtx.findRenderObject() as RenderBox?;
    if (box == null) return 0;
    final local = box.globalToLocal(global);
    final worldX = scrollLeft + local.dx; // 視窗 → 世界座標
    int ms = (worldX / pxPerMs).round();
    return ms.clamp(0, laneMs);
  }

  // ===== 取代原本的 _onLaneTapDown：拆兩個 =====
  void _onLaneTapDownSelect({required String laneId}) {
    final isSelected = widget.laneSvc.selectedLaneId.value == laneId;
    if (!isSelected) widget.laneSvc.selectLane(laneId); // 只有選取，不移動播放頭
  }

  void _onLaneTapUpSeek({
    required String laneId,
    required TapUpDetails details,
    required BuildContext areaCtx,
  }) {
    if (_laneTapCanceled || widget.laneSvc.isDragging) return;
    // 只有「點擊且已選取的 lane」才移動播放頭；長按/拖曳不會觸發 onTapUp
    final isSelected = widget.laneSvc.selectedLaneId.value == laneId;
    if (!isSelected) return;

    final ms = _globalPositionToMs(
      areaCtx: areaCtx,
      global: details.globalPosition,
      pxPerMs: widget.pxPerMs,
      scrollLeft: _hGroup.offset,
      laneMs: _laneMs,
    );

    widget.onSeekMs(ms);

    // 暫停狀態下，順帶把播放頭滾入視窗（沿用你的追隨邏輯）
    if (!widget.editor.isPlaying && _viewportRightW > 0) {
      final contentW = _ms2x(_laneMs) + 40;
      final maxScroll = contentW - _viewportRightW;
      if (maxScroll > 0) {
        double targetLeft =
            (_ms2x(ms).toDouble()) - _viewportRightW * _followBias;
        targetLeft = targetLeft.clamp(0.0, maxScroll);
        _hGroup.animateTo(
          targetLeft,
          duration: _animDur,
          curve: Curves.easeOut,
        );
      }
    }
  }

  // 原本的拖曳浮起動畫已移除

  // （移除未用的舊 _buildTrackRow，現已內嵌 builder 做動畫）

  // ★ 小工具：在指定 x（整頁座標）畫 1px 青色直線
  // （移除未用的 _snapLine）

  @override
  Widget build(BuildContext context) {
    // 確保控制器數量足夠（首次 build / 匯入刪除軌）
    _hGroup.ensureCount(widget.tracks.length);

    return LayoutBuilder(
      builder: (context, c) {
        _viewportRightW =
            c.maxWidth - _listPadL - _listPadR - _headerW - _gutterW;

        // 公共紅線位置（世界座標 → 視窗座標）
        // 避免不必要的中間變數，實際位置於下方 AnimatedBuilder 計算
        // 對齊整數像素，避免半像素造成視覺偏移
        // 紅色播放頭的位置改由下方 AnimatedBuilder 動態計算

        return Stack(
          children: [
            // 收所有子樹的「水平」滾動通知，用來暫停/恢復自動追隨
            NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.axis == Axis.horizontal &&
                    n is UserScrollNotification) {
                  if (n.direction != ScrollDirection.idle) {
                    _userHScrolling = true;
                  } else {
                    Future.delayed(const Duration(milliseconds: 800), () {
                      if (!mounted) return;
                      _userHScrolling = false;
                      _maybeAutoFollow();
                    });
                  }
                }
                // 每次水平捲動都更新覆蓋層的位置（避免整頁 setState）
                _scrollLeftVN.value = _hGroup.offset;
                return false;
              },
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false, // 關閉整列長按
                onReorder: (from, to) {
                  // 把實際換位邏輯丟回你原本的 onReorder（若有）
                  if (widget.onReorder != null) widget.onReorder!(from, to);
                  setState(() {}); // 重建
                },
                padding: const EdgeInsets.fromLTRB(
                  _listPadL,
                  8,
                  _listPadR,
                  140,
                ),
                itemCount: widget.tracks.length,
                itemBuilder: (context, i) {
                  final laneId = 'lane-$i';
                  final trackSvc = widget.tracks[i];

                  return AnimatedBuilder(
                    key: ValueKey(laneId), // ★ Reorderable 需要穩定 key
                    animation: Listenable.merge([
                      widget.laneSvc.selectedLaneId, // 切換選軌時重建
                      widget.laneSvc.dragging, // ★ 拖曳期間重建 → 觸發浮起動畫
                    ]),
                    builder: (_, __) {
                      final isSelectedLane =
                          widget.laneSvc.selectedLaneId.value == laneId;

                      final row = SizedBox(
                        height: _rowHeight,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: isSelectedLane
                                  ? const Color(0x1A22D3EE) // 淡青色高亮
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // 左側控制欄（含把手）
                                SizedBox(
                                  width: _headerW,
                                  child: Row(
                                    children: [
                                      ReorderableDragStartListener(
                                        index: i,
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          child: Icon(
                                            Icons.drag_handle_rounded,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () =>
                                              widget.laneSvc.selectLane(laneId),
                                          child: _TrackHeader(
                                            index: i,
                                            name: trackSvc.name,
                                            color: trackSvc.color,
                                            isMuted: widget.editor.trackMuted(
                                              i,
                                            ),
                                            gain: widget.editor.trackGain(i),
                                            onToggleMute: () => widget.editor
                                                .toggleTrackMute(i),
                                            onDelete: () =>
                                                widget.onDeleteTrack(i),
                                            onGainChanged: (v) => widget.editor
                                                .setTrackGain(i, v),
                                            onSeparateVocal: () async {
                                              await widget.editor
                                                  .separateVocalInstrument(i);
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(width: _gutterW),

                                // 右側：音軌區
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Builder(
                                      builder: (areaCtx) => GestureDetector(
                                        behavior: HitTestBehavior
                                            .deferToChild, // 讓子元件優先處理拖曳/長按
                                        onTapDown: (_) => _onLaneTapDownSelect(
                                          laneId: laneId,
                                        ),
                                        onTapUp: (d) => _onLaneTapUpSeek(
                                          laneId: laneId,
                                          details: d,
                                          areaCtx: areaCtx,
                                        ),
                                        child: TrackLane(
                                          laneId: laneId, // ★ 傳唯一 ID
                                          laneSvc: widget
                                              .laneSvc, // ★ 共用 service（單一選取）
                                          track: trackSvc,
                                          editor: widget.editor,
                                          pxPerMs: widget.pxPerMs,
                                          durationMs: widget.durationMs,
                                          canEdit: widget.canEdit,
                                          scrollController: _hGroup
                                              .controllerAt(i),
                                          showPlayhead: false, // 由父層畫公共紅線
                                          autoFollow: false, // 由父層統一追隨
                                          dragMode:
                                              TrackLaneDragMode.horizontal,
                                          // 父層手勢縮放時自行維持錨點，避免子元件也做錨點調整
                                          maintainPlayheadOnZoom: false,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );

                      // 移除拖曳時整條音軌浮起效果，直接回傳內容
                      return row;
                    },
                  );
                },
              ),
            ),

            // ===== 縮放手勢捕捉層（僅覆蓋右側編輯區，不遮住左側欄位） =====
            Positioned(
              left: _listPadL + _headerW + _gutterW,
              right: _listPadR,
              top: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _hoverZoom
                        ? const Color(0x558BC7FF)
                        : const Color(0x2222D3EE),
                    width: 1.0,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hoverZoom = true),
                  onExit: (_) => setState(() => _hoverZoom = false),
                  child: Listener(
                    onPointerSignal: (event) {
                      // Ctrl + 滑鼠滾輪 → 縮放
                      if (event is! PointerScrollEvent) return;
                      final keys = RawKeyboard.instance.keysPressed;
                      final ctrl =
                          keys.contains(LogicalKeyboardKey.controlLeft) ||
                          keys.contains(LogicalKeyboardKey.controlRight);
                      if (!ctrl) return;

                      // 計算縮放倍率（滑輪上捲放大、下捲縮小）
                      final dy = event.scrollDelta.dy; // Windows 往上多為負值
                      if (dy == 0) return;
                      final scaleFactor = math.exp(-dy * 0.0025); // 平滑指數縮放
                      if (_showZoomHint) setState(() => _showZoomHint = false);

                      final laneMs = _laneMs;
                      final minWindowMs = 50;
                      final maxWindowMs = 1_800_000;
                      final minPxPerMs = _viewportRightW > 0
                          ? (_viewportRightW / maxWindowMs)
                          : 0.001;
                      final maxPxPerMs = _viewportRightW > 0
                          ? (_viewportRightW / minWindowMs)
                          : 10.0;

                      // 轉局部座標（相對於此區塊）
                      final rb = (context.findRenderObject() as RenderBox?);
                      if (rb == null) return;
                      final local = rb.globalToLocal(event.position);
                      final localX = local.dx;

                      final startPxPerMs = widget.pxPerMs;
                      final startScroll = _hGroup.offset;
                      double newPxPerMs = (startPxPerMs * scaleFactor).clamp(
                        minPxPerMs,
                        maxPxPerMs,
                      );

                      // 以指標位置為錨點
                      final msAtFocal = (startScroll + localX) / startPxPerMs;
                      final newLeft = (msAtFocal * newPxPerMs) - localX;
                      final contentW = newPxPerMs * laneMs + 40;
                      final maxScroll = (contentW - _viewportRightW)
                          .clamp(0, double.infinity)
                          .toDouble();
                      final clampedLeft = newLeft
                          .clamp(0.0, maxScroll)
                          .toDouble();

                      _hGroup.jumpTo(clampedLeft);
                      widget.onSetPxPerMs(newPxPerMs);
                    },
                    child: Stack(
                      children: [
                        // 手勢層
                        GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onScaleStart: (d) {
                            // 兩指縮放一開始就取消本次點擊對 lane 的選取/seek 影響
                            _laneTapCanceled = true;
                            _isPinching = true;
                            _scaleStartPxPerMs = widget.pxPerMs;
                            _scaleStartScrollLeft = _hGroup.offset;
                          },
                          onScaleUpdate: (d) {
                            // 僅在雙指以上時進行縮放，避免影響單指拖曳/點擊
                            if (d.pointerCount < 2) return;
                            final scale = d.scale;
                            // 以內容長度給定最小縮放（整段全見），最大縮放（細看）
                            final laneMs = _laneMs;
                            // 對應可見時間窗：最小 50ms、最大 30 分鐘
                            final minWindowMs = 50;
                            final maxWindowMs = 1_800_000;
                            final minPxPerMs = _viewportRightW > 0
                                ? (_viewportRightW / maxWindowMs)
                                : 0.001; // 非 0 保底
                            final maxPxPerMs = _viewportRightW > 0
                                ? (_viewportRightW / minWindowMs)
                                : 10.0;
                            double newPxPerMs = (_scaleStartPxPerMs * scale)
                                .clamp(minPxPerMs, maxPxPerMs);

                            // 以焦點當錨：維持「焦點下的時間」不動
                            final localX = d.localFocalPoint.dx; // 右側區域內的 x
                            final msAtFocal =
                                (_scaleStartScrollLeft + localX) /
                                _scaleStartPxPerMs;
                            final newLeft = (msAtFocal * newPxPerMs) - localX;

                            final contentW = newPxPerMs * laneMs + 40;
                            final maxScroll = (contentW - _viewportRightW)
                                .clamp(0, double.infinity)
                                .toDouble();
                            final clampedLeft = newLeft
                                .clamp(0.0, maxScroll)
                                .toDouble();

                            // 先設定卷軸位置，再更新縮放（或相反順序都可；這裡先設卷軸更平滑）
                            _hGroup.jumpTo(clampedLeft);
                            widget.onSetPxPerMs(newPxPerMs);
                          },
                          onScaleEnd: (d) {
                            _isPinching = false;
                            // 放開後恢復點擊
                            _laneTapCanceled = false;
                            if (_showZoomHint)
                              setState(() => _showZoomHint = false);
                          },
                        ),
                        // 提示層（不攔截事件）
                        if (_showZoomHint)
                          Positioned(
                            right: 12,
                            top: 12,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xCC0F141E),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0x3322D3EE),
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black54,
                                      blurRadius: 10,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(
                                        Icons.zoom_in_map,
                                        size: 16,
                                        color: Colors.white70,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        '縮放區域  •  Ctrl+滾輪 / 雙指縮放',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 紅色播放頭（僅自身重建）：跟隨 playhead 與水平卷軸
            AnimatedBuilder(
              animation: Listenable.merge([
                widget.editor.playhead,
                _scrollLeftVN,
              ]),
              builder: (context, _) {
                final scrollX = _hGroup.offset;
                final worldX = _ms2x(widget.editor.playheadMs).toDouble();
                final localX = worldX - scrollX;
                final left = (_listPadL + _headerW + _gutterW + localX)
                    .roundToDouble();
                return Positioned(
                  left: left,
                  top: 0,
                  bottom: 0,
                  child: const IgnorePointer(
                    child: RepaintBoundary(
                      child: SizedBox(
                        width: 2,
                        child: ColoredBox(color: Colors.redAccent),
                      ),
                    ),
                  ),
                );
              },
            ),

            // === 磁吸導引線（跨所有軌）===
            AnimatedBuilder(
              animation: Listenable.merge([
                widget.editor.snapGuide,
                widget.editor.snapGuideOppositeMs,
              ]),
              builder: (context, _) {
                final guide = widget.editor.snapGuide.value;
                final opp = widget.editor.snapGuideOppositeMs.value;

                // 只在 butt-join 才顯示
                if (guide == null || guide.tag != 'butt') {
                  return const SizedBox.shrink();
                }

                double _msToOverlayLeft(int ms) {
                  final scrollX = _hGroup.offset;
                  final worldX = _ms2x(ms).toDouble();
                  final localX = worldX - scrollX;
                  return (_listPadL + _headerW + _gutterW + localX)
                      .roundToDouble();
                }

                final joinLeft = _msToOverlayLeft(guide.ms);
                final List<Widget> lines = [
                  // 主導引線（接縫）：亮一點
                  Positioned(
                    left: joinLeft,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        width: 1,
                        color: Colors.cyanAccent.withOpacity(0.95),
                      ),
                    ),
                  ),
                ];

                if (opp != null) {
                  final oppLeft = _msToOverlayLeft(opp);
                  lines.add(
                    // 對側線：淡一點
                    Positioned(
                      left: oppLeft,
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Container(
                          width: 1,
                          color: Colors.cyanAccent.withOpacity(0.45),
                        ),
                      ),
                    ),
                  );
                }

                return Stack(children: lines);
              },
            ),
          ],
        );
      },
    );
  }
}

/// 左側「軌道控制欄」（compact 兩行、不溢出）
class _TrackHeader extends StatelessWidget {
  final int index;
  final String name;
  final Color color;
  final bool isMuted;
  final double gain; // 0.0~1.0
  final VoidCallback onToggleMute;
  final VoidCallback onDelete;
  final ValueChanged<double> onGainChanged;
  final Future<void> Function() onSeparateVocal;

  const _TrackHeader({
    required this.index,
    required this.name,
    required this.color,
    required this.isMuted,
    required this.gain,
    required this.onToggleMute,
    required this.onDelete,
    required this.onGainChanged,
    required this.onSeparateVocal,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: '刪除軌道',
                icon: const Icon(Icons.delete_outline, color: Colors.white70),
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                onPressed: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _PillButton(
                label: 'M',
                tooltip: '靜音',
                active: isMuted,
                onTap: onToggleMute,
              ),
              const SizedBox(width: 8),
              _PillButton(
                label: '去人聲',
                tooltip: '中心相消 + 中心保留（產生兩條新軌）',
                active: false,
                onTap: () async {
                  await onSeparateVocal();
                },
              ),
              const SizedBox(width: 10),
              const Icon(Icons.volume_up, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Expanded(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 0,
                      ),
                      minThumbSeparation: 0,
                    ),
                    child: Slider(
                      value: gain.clamp(0.0, 1.0),
                      min: 0.0,
                      max: 1.0,
                      onChanged: onGainChanged,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  (gain * 100).round().toString(),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;
  const _PillButton({
    required this.label,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF22D3EE) : const Color(0xFF2B2F3A),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.black : Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
