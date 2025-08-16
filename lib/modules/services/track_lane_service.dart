// lib/modules/UI/ui2/track_lane_service.dart
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // for ScrollController
import 'package:clipnote_audio/modules/services/mainEditorService.dart';
import 'package:clipnote_audio/modules/services/singleTrackService.dart';

/// 將 TrackLane 的互動邏輯抽成 Service：
/// - 單一選取：selectedLaneId + selectedSegmentId（全域唯一 lane）
/// - 點擊先選取，再拖曳（未選取不進入拖曳）
/// - 拖曳整合 Snapping（beginDrag/snapMs/endDrag）
/// - 拖曳邊緣自動卷軸
class TrackLaneService {
  TrackLaneService(this.editor);

  final MainEditorService editor;

  /// 全域單一選取：只有一個 lane 可被選到
  final ValueNotifier<String?> selectedLaneId = ValueNotifier<String?>(null);
  final ValueNotifier<String?> selectedSegmentId = ValueNotifier<String?>(null);

  bool isLaneSelected(String laneId) => selectedLaneId.value == laneId;
  bool isSegmentSelected(String segId) => selectedSegmentId.value == segId;

  void selectLane(String laneId) {
    if (selectedLaneId.value != laneId) {
      selectedLaneId.value = laneId;
      selectedSegmentId.value = null; // 換 lane 即清掉 segment 選取
    }
  }

  void selectSegment({required String laneId, required String segId}) {
    if (selectedLaneId.value != laneId) {
      selectedLaneId.value = laneId;
    }
    selectedSegmentId.value = segId;
  }

  void clearSelection() {
    selectedLaneId.value = null;
    selectedSegmentId.value = null;
  }

  // ---- 拖曳狀態 ----
  _DragCtx? _drag;
  bool get isDragging => _drag != null;

  /// onPanStart：若尚未選取該段 -> 僅選取、不開拖曳；回傳是否真的開始拖曳
  bool panStart({
    required String laneId,
    required SingleTrackService track,
    required Segment segment,
    required double localDx, // d.localPosition.dx
  }) {
    // 未選取 -> 只選取，不進入拖曳
    if (!(isLaneSelected(laneId) && isSegmentSelected(segment.id))) {
      selectSegment(laneId: laneId, segId: segment.id);
      return false;
    }

    // 真的開始拖曳
    _drag = _DragCtx(
      laneId: laneId,
      track: track,
      segment: segment,
      startDx: localDx,
      startMs: segment.dstOffsetMs,
    );
    editor.beginInteractiveEdit();
    editor.snap.beginDrag();
    editor.snapGuide.value = null;
    return true;
  }

  /// onPanUpdate：進行快移與磁吸（不做混音重建）
  // lib/modules/UI/ui2/track_lane_service.dart

  void panUpdate({
    required double localDx,
    required double pxPerMs,
    required int laneMs,
    required bool snappingEnabled,
  }) {
    final ctx = _drag;
    if (ctx == null) return;

    final dx = localDx - ctx.startDx;
    final rawMs = (ctx.startMs + dx / pxPerMs).round().clamp(0, laneMs);

    // ✅ 改成透過 Editor，會順便記錄 touchedTracks 與顯示 snap 導引線
    editor.updateInteractiveDrag(
      track: ctx.track,
      segment: ctx.segment,
      rawMs: rawMs,
      excludeId: ctx.segment.id,
      snappingEnabled: snappingEnabled,
    );
  }

  /// onPanEnd：結束拖曳，這裡才觸發混音重建

  // track_lane_service.dart
  Future<void> panEnd({int? postSeekMs}) async {
    final ctx = _drag;
    if (ctx == null) return;

    // 保險：提交最後位置
    ctx.track.setSegmentOffset(
      ctx.segment,
      newDstOffsetMs: ctx.segment.dstOffsetMs,
    );

    _drag = null;
    await editor.endInteractiveEdit(postSeekMs: postSeekMs); // ★ 傳入
  }

  // ---- 拖曳邊緣自動卷軸（節流） ----
  DateTime _lastAutoScroll = DateTime.fromMillisecondsSinceEpoch(0);

  void autoScrollWhileDragging({
    required ScrollController controller,
    required double viewportWidth,
    required double pxPerMs,
    required int laneMs,
    double edgeMargin = 120,
  }) {
    if (_drag == null) return;
    if (!controller.hasClients || viewportWidth <= 0) return;

    final now = DateTime.now();
    if (now.difference(_lastAutoScroll).inMilliseconds < 24) return;
    _lastAutoScroll = now;

    final laneWidth = laneMs * pxPerMs + 40;
    final maxScroll = math.max(0.0, laneWidth - viewportWidth);
    if (maxScroll <= 0) return;

    final ms = _drag!.segment.dstOffsetMs;
    final x = ms * pxPerMs;
    var left = controller.position.pixels;
    final right = left + viewportWidth;

    const step = 32.0; // 每次小步移動（px）
    if (x < left + edgeMargin) {
      left = (left - step).clamp(0.0, maxScroll);
      controller.jumpTo(left);
    } else if (x > right - edgeMargin) {
      left = (left + step).clamp(0.0, maxScroll);
      controller.jumpTo(left);
    }
  }
}

class _DragCtx {
  final String laneId;
  final SingleTrackService track;
  final Segment segment;
  final double startDx;
  final int startMs;
  _DragCtx({
    required this.laneId,
    required this.track,
    required this.segment,
    required this.startDx,
    required this.startMs,
  });
}
