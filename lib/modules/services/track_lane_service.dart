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
  // 加在欄位區
  final ValueNotifier<bool> dragging = ValueNotifier<bool>(false);
  bool get isDragging => dragging.value; // 兼容舊用法

  int? get draggingSegDurationMs => _drag?.segment.srcDurationMs;
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

  //（建議）補一個釋放，以免記憶體漏
  void dispose() {
    selectedLaneId.dispose();
    selectedSegmentId.dispose();
    dragging.dispose();
    viewport.dispose();
  }

  // ---- 拖曳狀態 ----
  _DragCtx? _drag;

  /// onPanStart：若尚未選取該段 -> 僅選取、不開拖曳；回傳是否真的開始拖曳
  // panStart：真的開始拖曳時，發通知
  bool panStart({
    required String laneId,
    required SingleTrackService track,
    required Segment segment,
    required double localDx,
  }) {
    if (!(isLaneSelected(laneId) && isSegmentSelected(segment.id))) {
      selectSegment(laneId: laneId, segId: segment.id);
      return false;
    }

    _drag = _DragCtx(
      laneId: laneId,
      track: track,
      segment: segment,
      startDx: localDx,
      startMs: segment.dstOffsetMs,
    );
    dragging.value = true; // ★ 通知：開始拖
    editor.beginInteractiveEdit();
    editor.snap.beginDrag();
    editor.snapGuide.value = null;
    return true;
  }

  /// onPanUpdate：進行快移與磁吸（不做混音重建）
  // lib/modules/UI/ui2/track_lane_service.dart

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
    // 允許拖曳超出原本時限，僅限制不可小於 0
    final rawMs = math.max(0, (ctx.startMs + dx / pxPerMs).round());

    editor.updateInteractiveDrag(
      track: ctx.track,
      segment: ctx.segment,
      rawMs: rawMs,
      excludeId: ctx.segment.id,
      snappingEnabled: snappingEnabled,
      pxPerMs: pxPerMs, // ★ 補上這個參數
      laneMs: laneMs,
    );
  }

  /// onPanEnd：結束拖曳，這裡才觸發混音重建

  // track_lane_service.dart
  // panEnd：結束時關閉拖曳並發通知
  Future<void> panEnd({int? postSeekMs}) async {
    final ctx = _drag;
    if (ctx == null) return;

    ctx.track.setSegmentOffset(
      ctx.segment,
      newDstOffsetMs: ctx.segment.dstOffsetMs,
    );
    _drag = null;
    dragging.value = false; // ★ 通知：結束拖

    await editor.endInteractiveEdit(postSeekMs: postSeekMs);
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

  // ★ 目前視窗（所有 TrackLane/尺標/繪圖共用）
  final ValueNotifier<TimelineViewport> viewport = ValueNotifier(
    const TimelineViewport(scrollMs: 0, pxPerMs: 0.05, windowMs: 60 * 1000),
  );

  // 可視寬度變化時呼叫（由 UI 的 LayoutBuilder 傳入）
  void attachViewportWidth(double widthPx, {int? anchorMs}) {
    final v = viewport.value;
    if (widthPx <= 0) return;
    final newPxPerMs = widthPx / v.windowMs;
    final dur = _projectTotalMs.clamp(v.windowMs, 1 << 31);
    int newScroll = v.scrollMs;
    if (anchorMs != null) {
      final center = anchorMs.clamp(0, dur);
      newScroll = _clampScroll(center - v.windowMs ~/ 2, v.windowMs, dur);
    } else {
      newScroll = _clampScroll(newScroll, v.windowMs, dur);
    }
    viewport.value = v.copyWith(pxPerMs: newPxPerMs, scrollMs: newScroll);
  }

  // 切換固定縮放（30s/1m/5m）
  void setScale(TimelineScale scale, {required double widthPx, int? anchorMs}) {
    final wMs = scale.windowMs;
    final dur = (_projectTotalMs > wMs) ? _projectTotalMs : wMs;
    final pxPerMs = (widthPx <= 0) ? viewport.value.pxPerMs : widthPx / wMs;
    final center = (anchorMs ?? _playheadMs).clamp(0, dur);
    final scroll = _clampScroll(center - wMs ~/ 2, wMs, dur);
    viewport.value = TimelineViewport(
      scrollMs: scroll,
      pxPerMs: pxPerMs,
      windowMs: wMs,
    );
  }

  // 背景拖曳 / 滾輪橫向捲動
  void scrollByPx(double deltaPx) {
    final v = viewport.value;
    if (deltaPx.abs() < 0.5) return;
    final deltaMs = (deltaPx / v.pxPerMs).round();
    final dur = (_projectTotalMs > v.windowMs) ? _projectTotalMs : v.windowMs;
    final newScroll = _clampScroll(v.scrollMs + deltaMs, v.windowMs, dur);
    viewport.value = v.copyWith(scrollMs: newScroll);
  }

  // —— 工具/邊界 ——
  int _clampScroll(int desiredScroll, int windowMs, int durationMs) {
    final maxScroll = math.max(0, durationMs - windowMs);
    return desiredScroll.clamp(0, maxScroll);
  }

  // 專案總長 = 所有軌所有片段的最晚結束時間
  int get _projectTotalMs {
    int ms = editor.durationMs;
    for (final t in editor.tracks) {
      for (final s in t.track.segments) {
        ms = math.max(ms, s.dstOffsetMs + s.srcDurationMs);
      }
      ms = math.max(ms, t.durationMs);
    }
    return ms;
  }

  int get _playheadMs => editor.displayPlayheadMs;
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

// 放在檔案頂端 enum/模型區
class TimelineViewport {
  final int scrollMs; // 視窗左界
  final double pxPerMs; // 每毫秒幾像素
  final int windowMs; // 視窗寬幅(毫秒)
  const TimelineViewport({
    required this.scrollMs,
    required this.pxPerMs,
    required this.windowMs,
  });
  TimelineViewport copyWith({int? scrollMs, double? pxPerMs, int? windowMs}) =>
      TimelineViewport(
        scrollMs: scrollMs ?? this.scrollMs,
        pxPerMs: pxPerMs ?? this.pxPerMs,
        windowMs: windowMs ?? this.windowMs,
      );
}

// 你要的縮放刻度（可先保留 30s/1m/5m，之後再擴充）
// timeline_scale.dart（或 track_lane_service.dart 末尾）
// 8 檔縮放尺度
enum TimelineScale { s5, s15, s30, m1, m3, m10, m15, m30 }

extension TimelineScaleX on TimelineScale {
  int get windowMs => switch (this) {
    TimelineScale.s5 => 5 * 1000,
    TimelineScale.s15 => 15 * 1000,
    TimelineScale.s30 => 30 * 1000,
    TimelineScale.m1 => 60 * 1000,
    TimelineScale.m3 => 3 * 60 * 1000,
    TimelineScale.m10 => 10 * 60 * 1000,
    TimelineScale.m15 => 15 * 60 * 1000,
    TimelineScale.m30 => 30 * 60 * 1000,
  };

  String get label => switch (this) {
    TimelineScale.s5 => '5秒',
    TimelineScale.s15 => '15秒',
    TimelineScale.s30 => '30秒',
    TimelineScale.m1 => '1分',
    TimelineScale.m3 => '3分',
    TimelineScale.m10 => '10分',
    TimelineScale.m15 => '15分',
    TimelineScale.m30 => '30分',
  };
}

// 循環順序（由小到大）
const kTimelineScaleOrder = <TimelineScale>[
  TimelineScale.s5,
  TimelineScale.s15,
  TimelineScale.s30,
  TimelineScale.m1,
  TimelineScale.m3,
  TimelineScale.m10,
  TimelineScale.m15,
  TimelineScale.m30,
];

// 方便「下一段」輪替
extension TimelineScaleCycle on TimelineScale {
  TimelineScale get next {
    final i = kTimelineScaleOrder.indexOf(this);
    return kTimelineScaleOrder[(i + 1) % kTimelineScaleOrder.length];
  }
}

// 給任何地方用：由 windowMs 挑最接近的尺度
TimelineScale nearestScaleForWindowMs(int windowMs) {
  TimelineScale best = kTimelineScaleOrder.first;
  var bestDiff = (windowMs - best.windowMs).abs();
  for (final s in kTimelineScaleOrder.skip(1)) {
    final d = (windowMs - s.windowMs).abs();
    if (d < bestDiff) {
      best = s;
      bestDiff = d;
    }
  }
  return best;
}
