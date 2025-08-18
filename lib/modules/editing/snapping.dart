// modules/editing/snapping.dart
import 'dart:math' as math;

/// 一個時間點（毫秒）+ 來源標記
class SnapPoint {
  final int ms;
  final String tag; // 'clip-start' | 'clip-end' | 'playhead' | 'grid' ...
  const SnapPoint(this.ms, this.tag);
}

class SnapResult {
  final int snappedMs;
  final SnapPoint target;
  final int deltaAbs;
  const SnapResult(this.snappedMs, this.target, this.deltaAbs);
}

class SnapConfig {
  final bool toClips;
  final bool toPlayhead;
  final bool toGrid;
  final int thresholdMs; // 距離門檻（ms）
  final int gridStepMs; // ★ 網格間距（ms）
  final List<String> priority;
  final int releaseGapMs;

  const SnapConfig({
    this.toClips = true,
    this.toPlayhead = true,
    this.toGrid = true,
    this.thresholdMs = 18,
    this.gridStepMs = 500, // ★ 預設 500ms
    this.priority = const ['clip-start', 'clip-end', 'playhead', 'grid'],
    this.releaseGapMs = 6,
  });

  SnapConfig copyWith({
    bool? toClips,
    bool? toPlayhead,
    bool? toGrid,
    int? thresholdMs,
    int? gridStepMs, // ★ 有這個
    List<String>? priority,
    int? releaseGapMs,
  }) {
    return SnapConfig(
      toClips: toClips ?? this.toClips,
      toPlayhead: toPlayhead ?? this.toPlayhead,
      toGrid: toGrid ?? this.toGrid,
      thresholdMs: thresholdMs ?? this.thresholdMs,
      gridStepMs: gridStepMs ?? this.gridStepMs, // ★ 有這個
      priority: priority ?? this.priority,
      releaseGapMs: releaseGapMs ?? this.releaseGapMs,
    );
  }
}

class SnapController {
  SnapConfig config;

  final List<SnapPoint> Function({String? excludeId}) getClipEdgePoints;
  final int Function() getPlayheadMs;
  final int Function() getDurationMs;

  SnapController({
    required this.getClipEdgePoints,
    required this.getPlayheadMs,
    required this.getDurationMs,
    this.config = const SnapConfig(),
  });

  SnapPoint? _latched;
  final List<SnapPoint> _buf = <SnapPoint>[];

  void beginDrag() => _latched = null;
  void endDrag() => _latched = null;

  SnapResult? snapMs(
    int rawMs, {
    String? excludeId,
    bool snappingEnabled = true,
  }) {
    final total = getDurationMs();
    final clampedRaw = rawMs.clamp(0, total);

    if (!snappingEnabled || config.thresholdMs <= 0) return null;

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

    if (_latched != null) {
      final d = (clampedRaw - _latched!.ms).abs();
      if (d <= config.thresholdMs + config.releaseGapMs) {
        return SnapResult(_latched!.ms, _latched!, d);
      }
    }

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

    if (best != null && bestDelta <= config.thresholdMs) {
      _latched = best;
      final snapped = best.ms.clamp(0, total);
      return SnapResult(snapped, best, bestDelta);
    }

    if (_latched != null &&
        (clampedRaw - _latched!.ms).abs() >
            config.thresholdMs + config.releaseGapMs * 2) {
      _latched = null;
    }
    return null;
  }

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
