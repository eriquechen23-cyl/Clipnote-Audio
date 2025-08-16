// modules/editing/snapping.dart
import 'dart:math' as math;

/// 一個時間點（毫秒）+ 來源標記，方便 UI 顯示指引線文字
class SnapPoint {
  final int ms;
  final String tag; // e.g. 'clip-start', 'clip-end', 'playhead', 'grid'
  const SnapPoint(this.ms, this.tag);
}

/// 吸附結果（若不在門檻內，return null）
class SnapResult {
  final int snappedMs; // 吸附後的位置（已 clamp）
  final SnapPoint target; // 吸附到誰
  final int deltaAbs; // 吸附距離 |raw - snapped|
  const SnapResult(this.snappedMs, this.target, this.deltaAbs);
}

/// 設定檔：要不要對齊哪些東西、門檻、網格大小與優先順序
class SnapConfig {
  final bool toClips;
  final bool toPlayhead;
  final bool toGrid;
  final int thresholdMs; // 距離門檻（越小越精準）
  final int gridStepMs; // 網格間距（例如 250/500/1000）
  /// 同距離/臨界時的優先順序（越前越優先）
  final List<String>
  priority; // e.g. ['clip-start','clip-end','playhead','grid']
  /// 黏滯釋放額外容差（避免在臨界值附近閃爍）
  final int releaseGapMs;

  const SnapConfig({
    this.toClips = true,
    this.toPlayhead = true,
    this.toGrid = true,
    this.thresholdMs = 18,
    this.gridStepMs = 500,
    this.priority = const ['clip-start', 'clip-end', 'playhead', 'grid'],
    this.releaseGapMs = 6,
  });

  SnapConfig copyWith({
    bool? toClips,
    bool? toPlayhead,
    bool? toGrid,
    int? thresholdMs,
    int? gridStepMs,
    List<String>? priority,
    int? releaseGapMs,
  }) {
    return SnapConfig(
      toClips: toClips ?? this.toClips,
      toPlayhead: toPlayhead ?? this.toPlayhead,
      toGrid: toGrid ?? this.toGrid,
      thresholdMs: thresholdMs ?? this.thresholdMs,
      gridStepMs: gridStepMs ?? this.gridStepMs,
      priority: priority ?? this.priority,
      releaseGapMs: releaseGapMs ?? this.releaseGapMs,
    );
  }
}

/// 專心做 snapping 的小控制器；外部提供候選點的取得方式
class SnapController {
  SnapConfig config;

  /// 外部注入：每次拖曳時呼叫，回傳「可吸附的時間點」。
  /// excludeId：排除自己（避免吸到自己邊緣）
  final List<SnapPoint> Function({String? excludeId}) getClipEdgePoints;

  /// 播放頭與總時長（for grid/playhead/clamp）
  final int Function() getPlayheadMs;
  final int Function() getDurationMs;

  SnapController({
    required this.getClipEdgePoints,
    required this.getPlayheadMs,
    required this.getDurationMs,
    this.config = const SnapConfig(),
  });

  // ---- 內部狀態：黏滯 & buffer（效能） ----
  SnapPoint? _latched; // 已咬住的目標
  final List<SnapPoint> _buf = <SnapPoint>[]; // 重用，避免反覆配置

  /// 建議在 onPanStart 時呼叫
  void beginDrag() => _latched = null;

  /// 建議在 onPanEnd 時呼叫
  void endDrag() => _latched = null;

  /// 對單一原始位置作吸附；回傳最佳目標或 null（表示不吸）。
  /// 可用 snappingEnabled 在 UI 端快速關閉（例如按住 Alt）。
  SnapResult? snapMs(
    int rawMs, {
    String? excludeId,
    bool snappingEnabled = true,
  }) {
    final total = getDurationMs();
    final clampedRaw = rawMs.clamp(0, total);

    if (!snappingEnabled || config.thresholdMs <= 0) return null;

    // 收集候選點（順序不重要，後面會依優先權挑）
    _buf.clear();
    if (config.toClips) {
      _buf.addAll(getClipEdgePoints(excludeId: excludeId));
    }
    if (config.toPlayhead) {
      _buf.add(SnapPoint(getPlayheadMs(), 'playhead'));
    }
    if (config.toGrid) {
      _buf.addAll(_gridNeighbors(clampedRaw as int, config.gridStepMs, total));
    }
    if (_buf.isEmpty) return null;

    // 黏滯：若已咬住，且仍在門檻 + releaseGap 內，就直接用它
    if (_latched != null) {
      final d = (clampedRaw - _latched!.ms).abs();
      if (d <= config.thresholdMs + config.releaseGapMs) {
        return SnapResult(_latched!.ms, _latched!, d);
      }
    }

    // 依優先權 + 距離選擇最佳點（先比 priority，再比距離，再比較小的 ms）
    SnapPoint? best;
    var bestDelta = 1 << 30;
    var bestRank = 999;

    for (final p in _buf) {
      final d = (p.ms - clampedRaw).abs();
      final rank = _tagRank(p.tag);
      final better =
          (rank < bestRank) ||
          (rank == bestRank && d < bestDelta) ||
          (rank == bestRank && d == bestDelta && p.ms < (best?.ms ?? 1 << 30));
      if (better) {
        best = p;
        bestDelta = d;
        bestRank = rank;
      }
    }

    // 只有在門檻內才吸；並「咬住」它
    if (best != null && bestDelta <= config.thresholdMs) {
      _latched = best;
      final snapped = best.ms.clamp(0, total);
      return SnapResult(snapped, best, bestDelta);
    }

    // 太遠：若離原先 latched 很遠，乾脆釋放
    if (_latched != null &&
        (clampedRaw - _latched!.ms).abs() >
            config.thresholdMs + config.releaseGapMs * 2) {
      _latched = null;
    }
    return null;
  }

  // 一次回 k-1、k、k+1 這三個最接近的網格點（含邊界）
  List<SnapPoint> _gridNeighbors(int rawMs, int step, int total) {
    if (step <= 0) return const [];
    final out = <SnapPoint>[];
    final k = (rawMs / step).floor();

    int at(int idx) => (idx * step).clamp(0, total);
    void push(int ms) {
      if (out.isEmpty || out.last.ms != ms) out.add(SnapPoint(ms, 'grid'));
    }

    push(at(k - 1));
    push(at(k));
    push(at(k + 1));
    return out;
  }

  int _tagRank(String tag) {
    final idx = config.priority.indexOf(tag);
    return idx >= 0 ? idx : 99;
  }
}
