// modules/editing/snapping.dart
import 'dart:math' as math;

/// 一個時間點（毫秒）+ 來源標記，方便 UI 顯示指引線文字
class SnapPoint {
  final int ms;
  final String tag; // e.g. 'clip-start', 'clip-end', 'playhead', 'grid'
  SnapPoint(this.ms, this.tag);
}

/// 吸附結果（若不在門檻內，return null）
class SnapResult {
  final int snappedMs; // 吸附後的位置
  final SnapPoint target; // 吸附到誰
  final int deltaAbs; // 吸附距離 |raw - snapped|
  SnapResult(this.snappedMs, this.target, this.deltaAbs);
}

/// 設定檔：要不要對齊哪些東西、門檻、網格大小等
class SnapConfig {
  final bool toClips;
  final bool toPlayhead;
  final bool toGrid;
  final int thresholdMs; // 距離門檻（越小越精準）
  final int gridStepMs; // 網格間距（例如 250ms / 500ms / 1000ms）

  const SnapConfig({
    this.toClips = true,
    this.toPlayhead = true,
    this.toGrid = true,
    this.thresholdMs = 18,
    this.gridStepMs = 500,
  });

  SnapConfig copyWith({
    bool? toClips,
    bool? toPlayhead,
    bool? toGrid,
    int? thresholdMs,
    int? gridStepMs,
  }) {
    return SnapConfig(
      toClips: toClips ?? this.toClips,
      toPlayhead: toPlayhead ?? this.toPlayhead,
      toGrid: toGrid ?? this.toGrid,
      thresholdMs: thresholdMs ?? this.thresholdMs,
      gridStepMs: gridStepMs ?? this.gridStepMs,
    );
  }
}

/// 專心做 snapping 的小控制器；外部提供候選點的取得方式
class SnapController {
  SnapConfig config;

  /// 外部注入：每次拖曳時呼叫，回傳「可吸附的時間點」。
  /// excludeId：排除自己（避免吸到自己邊緣）
  final List<SnapPoint> Function({String? excludeId}) getClipEdgePoints;

  /// 播放頭與總時長（for grid/playhead）
  final int Function() getPlayheadMs;
  final int Function() getDurationMs;

  SnapController({
    required this.getClipEdgePoints,
    required this.getPlayheadMs,
    required this.getDurationMs,
    this.config = const SnapConfig(),
  });

  /// 對單一原始位置作吸附；回傳最佳目標或 null（表示不吸）
  SnapResult? snapMs(int rawMs, {String? excludeId}) {
    final candidates = <SnapPoint>[];

    if (config.toClips) {
      candidates.addAll(getClipEdgePoints(excludeId: excludeId));
    }

    if (config.toPlayhead) {
      candidates.add(SnapPoint(getPlayheadMs(), 'playhead'));
    }

    if (config.toGrid) {
      candidates.addAll(
        _gridNeighbors(rawMs, config.gridStepMs, getDurationMs()),
      );
    }

    // 從所有候選找距離最近者
    SnapPoint? best;
    var bestDelta = 1 << 30;
    for (final p in candidates) {
      final d = (p.ms - rawMs).abs();
      if (d < bestDelta) {
        bestDelta = d;
        best = p;
      }
    }
    if (best == null) return null;

    // 只有在門檻內才吸
    if (bestDelta <= config.thresholdMs) {
      return SnapResult(best.ms, best, bestDelta);
    }
    return null;
  }

  /// 一次回兩三個最接近的網格點就好（不掃全局）
  List<SnapPoint> _gridNeighbors(int rawMs, int step, int total) {
    if (step <= 0) return const [];
    final k = (rawMs / step).floor();
    final msA = math.max(0, k * step);
    final msB = math.min(total, (k + 1) * step);
    final out = <SnapPoint>[SnapPoint(msA, 'grid')];
    if (msB != msA) out.add(SnapPoint(msB, 'grid'));
    // 也可加 k-1：
    if (k - 1 >= 0) out.add(SnapPoint(math.max(0, (k - 1) * step), 'grid'));
    return out;
  }
}
