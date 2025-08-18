// ui2_pages.dart
// ignore_for_file: unnecessary_this

import 'package:clipnote_audio/modules/editing/snapping.dart';
import 'package:clipnote_audio/modules/services/track_lane_service.dart';
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
  static const double _rowHeight = 160;

  // 連動的水平卷軸群組
  final _LinkedHScrollGroup _hGroup = _LinkedHScrollGroup();

  // 自動追隨控制
  bool _userHScrolling = false;
  double _viewportRightW = 0; // 右側可視寬
  static const double _followBias = 0.35; // 播放頭維持在右側 35% 位置
  static const double _edgeMargin = 120;
  static const Duration _animDur = Duration(milliseconds: 120);
  late final TrackLaneService _laneSvc; // ★ 共用：一次只選一個 lane

  // _TracksPageState 內成員
  bool _laneTapCanceled = false; // 被長按/拖曳取消時，父層不做 seek

  @override
  void initState() {
    super.initState();
    widget.editor.playhead.addListener(_onTick);
    widget.editor.playing.addListener(_maybeAutoFollow);
    _laneSvc = TrackLaneService(widget.editor); // ★ 父層只建一次
  }

  @override
  void didUpdateWidget(covariant TracksPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 軌數改變時，調整控制器數量
    _hGroup.ensureCount(widget.tracks.length);
  }

  @override
  void dispose() {
    widget.editor.playhead.removeListener(_onTick);
    widget.editor.playing.removeListener(_maybeAutoFollow);
    _laneSvc.dispose(); // ★ 新增：釋放 notifiers
    _hGroup.dispose();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {}); // 讓公共紅線即時更新
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
    if (!widget.editor.isPlaying || _viewportRightW <= 0) return;
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

  void _onLaneTapDown({
    required String laneId,
    required TapDownDetails details,
    required BuildContext areaCtx,
  }) {
    final isSelectedLane = _laneSvc.selectedLaneId.value == laneId;

    // 第一次點：只選取；第二次（已選取）才移動播放頭
    if (!isSelectedLane) {
      _laneSvc.selectLane(laneId);
      return;
    }

    // 取得在「音軌可視區」中的 x（px）
    final box = areaCtx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    final dx = local.dx;

    // 轉成世界座標與時間（毫秒）
    final worldX = _hGroup.offset + dx;
    int ms = (worldX / widget.pxPerMs).round();
    ms = ms.clamp(0, _laneMs); // 不超出長度

    // 移動播放頭（交給父層/服務）
    widget.onSeekMs(ms);

    // 若目前是暫停狀態，順帶把播放頭滾進視窗（與自動追隨一致的邏輯）
    if (!widget.editor.isPlaying && _viewportRightW > 0) {
      final contentW = _ms2x(_laneMs) + 40;
      final maxScroll = contentW - _viewportRightW;
      if (maxScroll > 0) {
        double targetLeft = worldX - _viewportRightW * _followBias;
        targetLeft = targetLeft.clamp(0.0, maxScroll);
        _hGroup.animateTo(
          targetLeft,
          duration: _animDur,
          curve: Curves.easeOut,
        );
      }
    }
  }

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
    final isSelected = _laneSvc.selectedLaneId.value == laneId;
    if (!isSelected) _laneSvc.selectLane(laneId); // 只有選取，不移動播放頭
  }

  void _onLaneTapUpSeek({
    required String laneId,
    required TapUpDetails details,
    required BuildContext areaCtx,
  }) {
    if (_laneTapCanceled || _laneSvc.isDragging) return;
    // 只有「點擊且已選取的 lane」才移動播放頭；長按/拖曳不會觸發 onTapUp
    final isSelected = _laneSvc.selectedLaneId.value == laneId;
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

  // 放在 _TracksPageState 裡，任一方法之上都可
  Widget _liftIfDragging({required Widget child, required bool lift}) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: lift ? 1 : 0),
      builder: (_, t, __) {
        final dy = -10.0 * t; // 位移：-10px
        final scale = 1.0 + 0.03 * t; // 縮放：+3%
        final br = 12.0; // 外框圓角

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.center,
                child: Container(
                  // 外部陰影 + 青色外發光
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.65 * t),
                        blurRadius: 28 * t,
                        spreadRadius: 2 * t,
                        offset: Offset(0, 10 * t),
                      ),
                      BoxShadow(
                        color: const Color(0xFF22D3EE).withOpacity(0.40 * t),
                        blurRadius: 38 * t,
                        spreadRadius: 2 * t,
                      ),
                    ],
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(br),
                      border: Border.all(
                        color: const Color(0xFF22D3EE).withOpacity(0.95 * t),
                        width: 2.0 * t, // 浮起時出現 2px 青色外框
                      ),
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
            if (t > 0)
              // 上緣淡淡高光，讓「浮起」更立體
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(br),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withOpacity(0.06 * t),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTrackRow({
    required int index,
    required String laneId,
    required SingleTrackService trackSvc,
    required bool isSelectedLane,
  }) {
    return SizedBox(
      height: _rowHeight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isSelectedLane
                ? const Color(0x1A22D3EE)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ← 左邊把手 + Header（用把手啟動父層重排）
              SizedBox(
                width: _headerW,
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.drag_handle_rounded,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _laneSvc.selectLane(laneId),
                        child: _TrackHeader(
                          index: index,
                          name: trackSvc.name,
                          color: trackSvc.color,
                          isMuted: widget.editor.trackMuted(index),
                          gain: widget.editor.trackGain(index),
                          onToggleMute: () =>
                              widget.editor.toggleTrackMute(index),
                          onDelete: () => widget.onDeleteTrack(index),
                          onGainChanged: (v) =>
                              widget.editor.setTrackGain(index, v),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: _gutterW),

              // 右側 Lane（維持你原本的 TrackLane）
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Builder(
                    builder: (areaCtx) => GestureDetector(
                      behavior:
                          HitTestBehavior.deferToChild, // 讓子元件優先（長按/拖曳會取消父 tap）
                      onTapDown: (_) {
                        _laneTapCanceled = false; // 新增：預設不取消
                        _onLaneTapDownSelect(laneId: laneId); // 只做「選軌」
                      },
                      onTapCancel: () {
                        // 新增：被長按或拖曳搶走時會進來
                        _laneTapCanceled = true;
                      },
                      onTapUp: (d) => _onLaneTapUpSeek(
                        // 只有沒被取消才會 Seek（見第 3 步）
                        laneId: laneId,
                        details: d,
                        areaCtx: areaCtx,
                      ),
                      child: TrackLane(
                        laneId: laneId,
                        laneSvc: _laneSvc,
                        track: trackSvc,
                        editor: widget.editor,
                        pxPerMs: widget.pxPerMs,
                        durationMs: widget.durationMs,
                        canEdit: widget.canEdit,
                        scrollController: _hGroup.controllerAt(index),
                        showPlayhead: false,
                        autoFollow: false,
                        // ★ 用水平拖移動片段；長按留給切割選單
                        dragMode: TrackLaneDragMode.horizontal,
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
  }

  // ★ 小工具：在指定 x（整頁座標）畫 1px 青色直線
  Widget _snapLine(double left) {
    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Container(width: 1, color: Colors.cyanAccent.withOpacity(0.85)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 確保控制器數量足夠（首次 build / 匯入刪除軌）
    _hGroup.ensureCount(widget.tracks.length);

    return LayoutBuilder(
      builder: (context, c) {
        _viewportRightW =
            c.maxWidth - _listPadL - _listPadR - _headerW - _gutterW;

        // 公共紅線位置（世界座標 → 視窗座標）
        final scrollX = _hGroup.offset;
        final worldX = _ms2x(widget.editor.playheadMs).toDouble();
        final localX = worldX - scrollX;
        final overlayLeft = _listPadL + _headerW + _gutterW + localX;

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
                      _laneSvc.selectedLaneId, // 切換選軌時重建
                      _laneSvc.dragging, // ★ 拖曳期間重建 → 觸發浮起動畫
                    ]),
                    builder: (_, __) {
                      final isSelectedLane =
                          _laneSvc.selectedLaneId.value == laneId;
                      final isFloating = isSelectedLane && _laneSvc.isDragging;

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
                                              _laneSvc.selectLane(laneId),
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
                                          laneSvc:
                                              _laneSvc, // ★ 共用 service（單一選取）
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

                      return _liftIfDragging(child: row, lift: isFloating);
                    },
                  );
                },
              ),
            ),

            // ui2_pages.dart（_TracksPageState.build 裡的 Stack）
            /* 仍保留你的紅色播放頭 */
            Positioned(
              left: overlayLeft,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(width: 2, color: Colors.redAccent),
              ),
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
                  return _listPadL + _headerW + _gutterW + localX;
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

  const _TrackHeader({
    required this.index,
    required this.name,
    required this.color,
    required this.isMuted,
    required this.gain,
    required this.onToggleMute,
    required this.onDelete,
    required this.onGainChanged,
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
