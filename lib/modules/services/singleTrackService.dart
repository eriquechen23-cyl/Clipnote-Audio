// lib/modules/services/singleTrackService.dart
// Clipnote Audio - SingleTrackService
//
// 內部統一格式：48 kHz, mono, s16le (PCM little-endian).
// 目標：提供「一條音軌」的完整編輯/渲染/取樣能力。
// - 檔案解碼（FFmpeg FFI 注入）＋快取
// - Segment 增刪改排、淡入淡出（線性/等功率）、段音量 gainDb
// - 軌層級參數：trackGainDb、pan（-1..+1；僅參數傳遞給 MixBus）
// - mute/solo 標記
// - 下採樣波形快取、durationMs
// - 取樣（供即時電平/FFT）
// - 渲染合成（debounce 重建 rendered PCM）
// - 事件：isDirty/onChanged
//
// ★ 新增：互動拖曳支援（拖曳中暫停渲染 setRenderSuspended / moveSegmentFast）
// ★ 新增：UI 友善 API（toggleMute / toggleSolo / trackGain01 & setTrackGain01）

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:clipnote_audio/modules/waveform/envelope.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui' show Color;

/// 常數
const int kSampleRate = 48000; // Hz
const int kBytesPerSample = 2; // s16le
const int kMaxRenderSeconds = 60 * 60; // 1 hr
const int kDefaultDownsampleStep = 128; // 波形下採樣步長（樣本）
const Duration kRenderDebounce = Duration(milliseconds: 120);

// 建議的軌增益範圍（dB）
const double kTrackGainDbMin = -60.0;
const double kTrackGainDbMax = 0.0;

/// 等功率淡入淡出 or 線性
enum FadeCurve { equalPower, linear }

/// 電平顯示（即時）
class Meter {
  final double rms; // 0..1
  final double peak; // 0..1
  const Meter(this.rms, this.peak);
}

/// 段資訊（來源區間對應到軌上的目的時間）
class Segment {
  final String id; // ★ 段 id，供排除自身/追蹤使用
  String sourceId; // 對應到快取的解碼結果 key
  int srcStartMs; // 來源起點
  int srcEndMs; // 來源終點（不含）
  int dstOffsetMs; // 放在軌上的偏移（絕對時間）
  int fadeInMs; // 段淡入
  int fadeOutMs; // 段淡出
  double gainDb; // 段音量（dB）
  FadeCurve fadeCurve; // 等功率/線性

  Segment({
    required this.id,
    required this.sourceId,
    required this.srcStartMs,
    required this.srcEndMs,
    required this.dstOffsetMs,
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
    this.gainDb = 0.0,
    this.fadeCurve = FadeCurve.equalPower,
  });

  int get srcDurationMs => math.max(0, srcEndMs - srcStartMs);

  Segment copyWith({
    String? id,
    String? sourceId,
    int? srcStartMs,
    int? srcEndMs,
    int? dstOffsetMs,
    int? fadeInMs,
    int? fadeOutMs,
    double? gainDb,
    FadeCurve? fadeCurve,
  }) {
    return Segment(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      srcStartMs: srcStartMs ?? this.srcStartMs,
      srcEndMs: srcEndMs ?? this.srcEndMs,
      dstOffsetMs: dstOffsetMs ?? this.dstOffsetMs,
      fadeInMs: fadeInMs ?? this.fadeInMs,
      fadeOutMs: fadeOutMs ?? this.fadeOutMs,
      gainDb: gainDb ?? this.gainDb,
      fadeCurve: fadeCurve ?? this.fadeCurve,
    );
  }
}

/// 單軌狀態
class SingleTrack with ChangeNotifier {
  String id; // 方便上層識別
  // ★ 新增：顯示名稱與顏色（供 UI 用）
  String displayName;
  Color color;
  double trackGainDb = 0.0;
  double pan = 0.0; // -1..+1（僅參數）
  bool mute = false;
  bool solo = false;

  final List<Segment> segments = [];

  // UI／上層觀察
  final ValueNotifier<bool> isDirty = ValueNotifier<bool>(false);
  final ValueNotifier<Meter> meter = ValueNotifier<Meter>(const Meter(0, 0));

  // 下採樣波形（給 UI）
  List<int> downsampledPcmPeak = const []; // 絕對峰值序列
  int downsampleStep = kDefaultDownsampleStep;

  // 渲染後 PCM（mono s16le）
  Int16List _rendered = Int16List(0);
  Int16List get renderedPcm => _rendered;

  // 多層封包（min/max）快取：key = stepSamples
  final Map<int, EnvelopeLevel> envelopes = {};
  // 推薦步階（以 samples 為單位；可依需求調整）
  static const List<int> envelopeSteps = [
    32,
    64,
    128,
    256,
    512,
    1024,
    2048,
    4096,
  ];

  // 建構子：給預設名稱與依 id 穩定取色
  SingleTrack(this.id)
    : displayName = '音軌 ${id.substring(id.length - 4)}',
      color = _colorFromId(id);
}

Color _colorFromId(String id) {
  final h = id.hashCode;
  final r = 110 + (h & 0x5F); // 110..205
  final g = 110 + ((h >> 6) & 0x5F); // 110..205
  final b = 140 + ((h >> 12) & 0x4B); // 140..215
  return Color(0xFF000000 | (r << 16) | (g << 8) | b);
}

/// 解碼結果快取
class DecodedAudio {
  final Int16List pcm; // mono s16le @ 48k
  final int sampleRate; // 應為 48000
  final int durationMs;
  DecodedAudio(this.pcm, this.sampleRate, this.durationMs);
}

/// 抽象解碼器
abstract class PcmDecoder {
  Future<DecodedAudio> decodeToS16leMono48k(String path);
}

class UnimplementedDecoder implements PcmDecoder {
  @override
  Future<DecodedAudio> decodeToS16leMono48k(String path) async {
    throw UnimplementedError('請注入 FFmpeg 解碼器（decodeToS16leMono48k）');
  }
}

/// 分割結果：左段 + 右段
class SplitResult {
  final Segment left;
  final Segment right;
  const SplitResult(this.left, this.right);
}

/// SingleTrackService：管理一條軌的全部行為
class SingleTrackService {
  SingleTrackService({PcmDecoder? decoder, void Function()? onChanged})
    : _decoder = decoder ?? UnimplementedDecoder(),
      _onChanged = onChanged;

  final PcmDecoder _decoder;
  final void Function()? _onChanged;

  // sourceId -> 解碼快取
  final Map<String, DecodedAudio> _decodeCache = {};

  // 軌
  late final SingleTrack track = SingleTrack(_genId());

  // 渲染 debounce
  Timer? _renderTimer;

  // 拖曳期間暫停渲染
  bool _renderSuspended = false;
  void setRenderSuspended(bool v) {
    _renderSuspended = v;
  }

  // ===== 公開屬性 =====
  bool get isMuted => track.mute;
  bool get isSolo => track.solo;
  double get trackGainDb => track.trackGainDb;
  double get pan => track.pan;

  // 方便 UI：0..1 線性增益讀寫
  double get trackGain01 => _dbTo01(track.trackGainDb);
  void setTrackGain01(double g01) => setTrackGainDb(_toDb(g01));

  /// 避免產生 0 長度段的最小切割距離
  static const int kMinSplitMs = 5;

  // Toggle 便利方法
  void toggleMute() => setMute(!isMuted);
  void toggleSolo() => setSolo(!isSolo);

  // 供 UI 使用的快捷屬性
  String get name => track.displayName;
  Color get color => track.color;

  // 如果你要支援重新命名/改色（可選）
  void rename(String newName) {
    track.displayName = newName;
    _markChanged();
  }

  void setColor(Color c) {
    track.color = c;
    _markChanged();
  }

  // 軌總長度（以 segments 覆蓋範圍計）
  int get durationMs {
    int maxEnd = 0;
    for (final s in track.segments) {
      maxEnd = math.max(maxEnd, s.dstOffsetMs + s.srcDurationMs);
    }
    return maxEnd;
  }

  // ===== 檔案解碼/快取 =====
  Future<String> decodeAndCache(String filePath, {String? sourceId}) async {
    final id = sourceId ?? filePath;
    if (_decodeCache.containsKey(id)) return id;
    final decoded = await _decoder.decodeToS16leMono48k(filePath);
    _decodeCache[id] = decoded;
    return id;
  }

  DecodedAudio? getDecoded(String sourceId) => _decodeCache[sourceId];

  // ===== Segment 管理 =====
  Segment addSegment({
    required String sourceId,
    required int srcStartMs,
    required int srcEndMs,
    required int dstOffsetMs,
    int fadeInMs = 0,
    int fadeOutMs = 0,
    double gainDb = 0.0,
    FadeCurve fadeCurve = FadeCurve.equalPower,
  }) {
    final seg = Segment(
      id: _genId(),
      sourceId: sourceId,
      srcStartMs: srcStartMs,
      srcEndMs: srcEndMs,
      dstOffsetMs: dstOffsetMs,
      fadeInMs: fadeInMs,
      fadeOutMs: fadeOutMs,
      gainDb: gainDb,
      fadeCurve: fadeCurve,
    );
    track.segments.add(seg);
    _touch();
    return seg;
  }

  void removeSegment(Segment seg) {
    track.segments.remove(seg);
    _touch();
  }

  Segment duplicateSegment(Segment seg, {int? newDstOffsetMs}) {
    final copy = seg.copyWith(
      id: _genId(),
      dstOffsetMs: newDstOffsetMs ?? seg.dstOffsetMs,
    );
    track.segments.add(copy);
    _touch();
    return copy;
  }

  void sortByDstOffset() {
    track.segments.sort((a, b) => a.dstOffsetMs.compareTo(b.dstOffsetMs));
    _touch();
  }

  // ===== 段操作 =====
  void moveSegment(Segment seg, {int? newDstOffsetMs}) {
    final i = track.segments.indexOf(seg);
    if (i < 0) return;
    track.segments[i] = seg.copyWith(
      dstOffsetMs: newDstOffsetMs ?? seg.dstOffsetMs,
    );
    _touch();
  }

  void trimSegment(Segment seg, {int? newSrcStartMs, int? newSrcEndMs}) {
    final i = track.segments.indexOf(seg);
    if (i < 0) return;
    final start = newSrcStartMs ?? seg.srcStartMs;
    final end = newSrcEndMs ?? seg.srcEndMs;
    track.segments[i] = seg.copyWith(
      srcStartMs: math.max(0, math.min(start, end)),
      srcEndMs: math.max(0, math.max(start, end)),
    );
    _touch();
  }

  void quantizeSegmentToGrid(Segment seg, int gridMs) {
    final i = track.segments.indexOf(seg);
    if (i < 0) return;
    final q = ((seg.dstOffsetMs / gridMs).round() * gridMs);
    track.segments[i] = seg.copyWith(dstOffsetMs: q);
    _touch();
  }

  // ===== 段參數 =====
  void setSegmentFades(
    Segment seg, {
    int? fadeInMs,
    int? fadeOutMs,
    FadeCurve? curve,
  }) {
    final i = track.segments.indexOf(seg);
    if (i < 0) return;
    track.segments[i] = seg.copyWith(
      fadeInMs: fadeInMs ?? seg.fadeInMs,
      fadeOutMs: fadeOutMs ?? seg.fadeOutMs,
      fadeCurve: curve ?? seg.fadeCurve,
    );
    _touch();
  }

  void setSegmentGainDb(Segment seg, double gainDb) {
    final i = track.segments.indexOf(seg);
    if (i < 0) return;
    track.segments[i] = seg.copyWith(gainDb: gainDb);
    _touch();
  }

  // ===== 軌層級參數 =====
  void setTrackGainDb(double db) {
    // 夾在建議範圍內
    track.trackGainDb = db.clamp(kTrackGainDbMin, kTrackGainDbMax);
    _touch();
  }

  void setPan(double p) {
    track.pan = p.clamp(-1.0, 1.0);
    _markChanged(); // pan 不影響本軌渲染，但要通知上層 MixBus
  }

  void setMute(bool v) {
    track.mute = v;
    _markChanged();
  }

  void setSolo(bool v) {
    track.solo = v;
    _markChanged();
  }

  // ===== 波形下採樣快取 =====
  void buildDownsampledWaveform({int step = kDefaultDownsampleStep}) {
    track.downsampleStep = math.max(1, step);
    final pcm = track.renderedPcm;
    if (pcm.isEmpty) {
      track.downsampledPcmPeak = const [];
      _markChanged();
      return;
    }

    final peaks = <int>[];
    for (int i = 0; i < pcm.length; i += step) {
      final end = math.min(i + step, pcm.length);
      int peak = 0;
      for (int j = i; j < end; j++) {
        final v = pcm[j].abs();
        if (v > peak) peak = v;
      }
      peaks.add(peak);
    }
    track.downsampledPcmPeak = peaks;
    _markChanged();
  }

  // ===== 取樣（供電平/FFT）=====
  Int16List sampleForFft({required int positionMs, required int count}) {
    final pcm = track.renderedPcm;
    if (pcm.isEmpty || count <= 0) return Int16List(count);
    final startIdx = ((positionMs / 1000.0) * kSampleRate).round();
    final out = Int16List(count);
    for (int i = 0; i < count; i++) {
      final idx = startIdx + i;
      out[i] = (idx >= 0 && idx < pcm.length) ? pcm[idx] : 0;
    }
    _updateMeter(out);
    return out;
  }

  // ===== 渲染（把 segments 摺合成 mono PCM）=====
  void rebuildRenderedNow() {
    final totalSamples = _estimateTotalSamples();
    final buf = Int32List(totalSamples); // 先用 32-bit 累加避免溢位
    final double trackGain = _dbToLin(track.trackGainDb);

    for (final seg in track.segments) {
      final src = _decodeCache[seg.sourceId];
      if (src == null) continue;
      final startSmp = _msToSamples(seg.srcStartMs);
      final endSmp = _msToSamples(seg.srcEndMs);
      final dstStart = _msToSamples(seg.dstOffsetMs);

      final len = math.max(0, endSmp - startSmp);
      if (len == 0) continue;

      final segGain = _dbToLin(seg.gainDb) * trackGain;

      // 淡入/淡出區間（樣本）
      final fadeInSmp = math.max(0, _msToSamples(seg.fadeInMs));
      final fadeOutSmp = math.max(0, _msToSamples(seg.fadeOutMs));

      for (int n = 0; n < len; n++) {
        final srcIdx = startSmp + n;
        if (srcIdx < 0 || srcIdx >= src.pcm.length) break;
        final dstIdx = dstStart + n;
        if (dstIdx < 0 || dstIdx >= buf.length) continue;

        // 計算淡入淡出權重
        double w = 1.0;
        if (fadeInSmp > 0 && n < fadeInSmp) {
          final t = n / fadeInSmp;
          w *= _fadeWeight(t, seg.fadeCurve, inPhase: true);
        }
        if (fadeOutSmp > 0 && n >= len - fadeOutSmp) {
          final t = (len - n) / fadeOutSmp; // 0..1
          w *= _fadeWeight(t, seg.fadeCurve, inPhase: false);
        }

        final sample = src.pcm[srcIdx].toDouble();
        final mixed = sample * segGain * w;
        buf[dstIdx] += mixed.toInt();
      }
    }

    // 限幅 + 轉回 Int16
    final out = Int16List(buf.length);
    for (int i = 0; i < buf.length; i++) {
      final v = buf[i].clamp(-32768, 32767);
      out[i] = v;
    }

    track._rendered = out;
    track.downsampledPcmPeak = const []; // 舊峰值可清空或保留
    track.downsampleStep = kDefaultDownsampleStep;
    track.envelopes.clear(); // ★ 失效舊封包

    track.isDirty.value = false;
    _markChanged();
  }

  /// Debounce 重建（編輯時呼叫）
  void rebuildRenderedDebounced() {
    _renderTimer?.cancel();
    _renderTimer = Timer(kRenderDebounce, rebuildRenderedNow);
  }

  // ===== 事件/內務 =====
  void dispose() {
    _renderTimer?.cancel();
  }

  void _touch() {
    track.isDirty.value = true;
    if (_renderSuspended) {
      // 拖曳中：不重建，只通知
      track.notifyListeners();
      _onChanged?.call();
    } else {
      rebuildRenderedDebounced();
    }
  }

  void _markChanged() {
    track.notifyListeners();
    _onChanged?.call();
  }

  int _estimateTotalSamples() {
    final ms = durationMs;
    final maxSamples = kSampleRate * kMaxRenderSeconds;
    return math.min(_msToSamples(ms), maxSamples);
  }

  static int _msToSamples(int ms) => ((ms / 1000.0) * kSampleRate).ceil();
  static double _dbToLin(double db) => math.pow(10.0, db / 20.0).toDouble();

  static double _fadeWeight(
    double t,
    FadeCurve curve, {
    required bool inPhase,
  }) {
    switch (curve) {
      case FadeCurve.linear:
        return t.clamp(0.0, 1.0);
      case FadeCurve.equalPower:
        return math.sin((t.clamp(0.0, 1.0)) * (math.pi / 2));
    }
  }

  void _updateMeter(Int16List window) {
    if (window.isEmpty) {
      track.meter.value = const Meter(0, 0);
      return;
    }
    double sumSq = 0;
    int peak = 0;
    for (final s in window) {
      final v = s.abs();
      if (v > peak) peak = v;
      sumSq += (s.toDouble() * s.toDouble());
    }
    final rms = math.sqrt(sumSq / window.length) / 32768.0;
    final pk = peak / 32768.0;
    track.meter.value = Meter(rms.clamp(0, 1), pk.clamp(0, 1));
  }

  static String _genId() => DateTime.now().microsecondsSinceEpoch.toString();

  // —— 便利接口（可選）——

  int get startMs {
    final segs = track.segments;
    if (segs.isEmpty) return 0;
    var minStart = segs.first.dstOffsetMs;
    for (final s in segs) {
      final st = s.dstOffsetMs;
      if (st < minStart) minStart = st;
    }
    return minStart;
  }

  /// 將此軌所有片段整體平移
  void shiftAllSegmentsBy(int deltaMs) {
    if (deltaMs == 0) return;
    final segs = track.segments;
    for (final s in segs) {
      s.dstOffsetMs = (s.dstOffsetMs) + deltaMs;
      if (s.dstOffsetMs < 0) s.dstOffsetMs = 0;
    }
    rebuildRenderedNow();
    buildDownsampledWaveform(step: 128);
    _onChanged?.call();
  }

  /// 把整條軌對到新的起點
  void setStartMs(int newStartMs) {
    shiftAllSegmentsBy(newStartMs - startMs);
  }

  // ====== 增益 0..1 ↔ dB 轉換 ======
  static double _toDb(double g01) {
    if (g01 <= 0.0) return kTrackGainDbMin;
    final db = 20.0 * (math.log(g01) / math.ln10);
    return db.clamp(kTrackGainDbMin, kTrackGainDbMax);
    // 0 dB = 1.0；-60 dB ≈ 0.001
  }

  static double _dbTo01(double db) {
    if (db <= kTrackGainDbMin) return 0.0;
    final g = math.pow(10.0, db / 20.0).toDouble();
    return (g < 1e-3) ? 0.0 : g.clamp(0.0, 1.0);
  }

  // ★ 拖曳中呼叫：只更新位置 + 輕量通知，千萬別觸發混音
  void moveSegmentFast(Segment seg, {required int newDstOffsetMs}) {
    if (seg.dstOffsetMs == newDstOffsetMs) return;
    seg.dstOffsetMs = newDstOffsetMs;
    _markChanged(); // ← 改這行：通知 track + 通知上層，而不是 notifyListeners()
  }

  // ★ 需要「正式寫回」才用這個（例如拖曳結束時）
  void setSegmentOffset(Segment seg, {required int newDstOffsetMs}) {
    if (seg.dstOffsetMs == newDstOffsetMs) return;
    seg.dstOffsetMs = newDstOffsetMs;
    _markChanged(); // ← 同上
  }

  /// 傳回「某毫秒落在哪一段」；若無則 null
  Segment? segmentAtMs(int ms) {
    for (final s in track.segments) {
      final start = s.dstOffsetMs;
      final end = start + s.srcDurationMs;
      if (ms >= start && ms < end) return s;
    }
    return null;
  }

  /// 在指定段 seg 的 splitMs（絕對時間）處切割。
  /// clearFadesAtCut=true 會把切點處的左右段淡出/淡入清零，避免切點音量凹陷。
  SplitResult? splitSegment(
    Segment seg,
    int splitMs, {
    bool clearFadesAtCut = true,
  }) {
    final segStart = seg.dstOffsetMs;
    final segEnd = segStart + seg.srcDurationMs;
    if (segEnd <= segStart) return null;

    // 夾限切點在段內
    final cut = splitMs.clamp(segStart, segEnd);

    // 靠太近邊界就不切，避免 0 長度
    if (cut - segStart < kMinSplitMs) return null;
    if (segEnd - cut < kMinSplitMs) return null;

    // 左段長度 = cut - segStart；對應到來源的 newSrcEndLeft
    final leftDurMs = cut - segStart;
    final newSrcEndLeft = seg.srcStartMs + leftDurMs;
    final newSrcStartRight = newSrcEndLeft;

    // 生成左右段（先複製，再調整）
    final left = seg.copyWith(
      id: _genId(),
      srcEndMs: newSrcEndLeft,
      // right 從 cut 起接上
      // 保留 dstOffsetMs 不變（左段起點仍在 segStart）
      fadeOutMs: clearFadesAtCut ? 0 : seg.fadeOutMs,
    );
    final right = seg.copyWith(
      id: _genId(),
      srcStartMs: newSrcStartRight,
      dstOffsetMs: cut,
      fadeInMs: clearFadesAtCut ? 0 : seg.fadeInMs,
    );

    // 夾限淡入/淡出不可超過新段長
    Segment clampFades(Segment s) {
      final len = s.srcDurationMs;
      return s.copyWith(
        fadeInMs: math.min(s.fadeInMs, len),
        fadeOutMs: math.min(s.fadeOutMs, len),
      );
    }

    final leftFixed = clampFades(left);
    final rightFixed = clampFades(right);

    // 用左右兩段取代原段，維持時間順序
    final idx = track.segments.indexOf(seg);
    if (idx < 0) return null;
    track.segments
      ..removeAt(idx)
      ..insertAll(idx, [leftFixed, rightFixed]);

    _touch(); // 標髒並觸發 debounce 渲染
    return SplitResult(leftFixed, rightFixed);
  }

  /// 以絕對時間 ms 找段並切割（例如播放頭）
  SplitResult? splitAtMs(int ms, {bool clearFadesAtCut = true}) {
    final seg = segmentAtMs(ms);
    if (seg == null) return null;
    return splitSegment(seg, ms, clearFadesAtCut: clearFadesAtCut);
  }

  // 依 pxPerMs 選一層最接近「1px 寬」的封包（stepMs * pxPerMs ≈ 1）
  EnvelopeLevel? pickEnvelopeForPxPerMs(double pxPerMs) {
    final sr = 48000; // 你專案內部統一 48k
    if (track.envelopes.isEmpty) return null;
    EnvelopeLevel? best;
    double bestDiff = 1e9;
    for (final e in track.envelopes.values) {
      final px = e.stepMs * pxPerMs;
      final d = (px - 1.0).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = e;
      }
    }
    return best;
  }

  // 確保指定 stepSamples 的封包存在；沒有就建（Isolate）
  Future<void> ensureEnvelopeLevel(int stepSamples) async {
    if (track.envelopes.containsKey(stepSamples)) return;
    final pcm = track.renderedPcm;
    if (pcm.isEmpty) {
      track.envelopes[stepSamples] = EnvelopeLevel(
        sampleRate: 48000,
        stepSamples: 1,
        minVals: Int16List(0),
        maxVals: Int16List(0),
      );
      _markChanged();
      return;
    }
    final env = await buildEnvelopeLevelIsolate(
      pcm: pcm,
      sampleRate: 48000,
      stepSamples: stepSamples,
    );
    track.envelopes[stepSamples] = env;
    _markChanged();
  }

  // 預熱幾個常用層
  Future<void> prewarmEnvelopes() async {
    for (final s in SingleTrack.envelopeSteps) {
      // 依序建，避免同時太多 Isolate（你也可併發 2~3 個）
      await ensureEnvelopeLevel(s);
    }
  }

  // 當渲染後 PCM 改變時，清空舊封包
  void _invalidateEnvelopes() {
    track.envelopes.clear();
  }

  // 根據當前縮放預先建一層（避免首次放大時卡頓）
  Future<void> ensureEnvelopeForPxPerMs(double pxPerMs) async {
    // 算出目標 stepSamples
    final sr = 48000;
    // 讓 stepMs ≈ 1/pxPerMs（每 1px 一個 bucket）
    final targetStepMs = (1.0 / pxPerMs).clamp(1.0, 5000.0); // 1ms ~ 5s
    int best = SingleTrack.envelopeSteps.first;
    double bestDiff = 1e9;
    for (final s in SingleTrack.envelopeSteps) {
      final stepMs = (s * 1000.0) / sr;
      final d = (stepMs - targetStepMs).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = s;
      }
    }
    await ensureEnvelopeLevel(best);
  }
}
