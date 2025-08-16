// lib/modules/services/mainEditorService.dart
// ClipNote — MainEditorService（Lite：移除頻譜功能 + 互動編輯/磁吸）

import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

import 'package:clipnote_audio/modules/decoding/ffmpeg_decoder.dart';
import 'package:clipnote_audio/modules/services/singleTrackService.dart';
import 'package:clipnote_audio/modules/merge_mix/mix_bus.dart';
import 'package:clipnote_audio/modules/playback/playbackService.dart';

// 自動對位（磁吸）
import 'package:clipnote_audio/modules/editing/snapping.dart';

class MainEditorService extends ChangeNotifier {
  MainEditorService({PcmDecoder? decoder})
    : _decoder = decoder ?? const FfmpegKitDecoder() {
    // 初始化磁吸控制器：你提供了 getClipEdgePoints / getPlayheadMs / getDurationMs
    snap = SnapController(
      getClipEdgePoints: ({String? excludeId}) =>
          _collectClipEdgePoints(excludeId: excludeId),
      getPlayheadMs: () => playhead.value,
      getDurationMs: () => durationMs,
    );
  }

  // ===== 基本相依 =====
  final PcmDecoder _decoder;
  final PlaybackService _pb = PlaybackService.instance;

  // ===== 狀態 =====
  final List<SingleTrackService> tracks = [];

  Uint8List? _masterPcmBytes; // s16le mono（給電平/分析）
  int? _masterSampleRate;

  // UI notifiers
  final ValueNotifier<bool> playing = ValueNotifier(false);
  final ValueNotifier<int> playhead = ValueNotifier(0); // ms
  final ValueNotifier<double> meter = ValueNotifier(0); // 0..1
  Listenable get uiTick => Listenable.merge([playing, playhead, meter]);

  // 播放與電平
  Timer? _uiTicker;
  double get volume01 => _pb.volume;
  int get durationMs => _pb.durationMs;
  int get playheadMs => playhead.value;
  bool get isPlaying => playing.value;
  double get meterPeak01 => meter.value;

  // ===== 電平視窗（極簡 Peak）=====
  static const int _meterWindow = 2048;
  final Int16List _windowBuf = Int16List(_meterWindow);
  final Int32List _accBuf = Int32List(_meterWindow);

  // ===== 重建節流 =====
  Timer? _rebuildDebounce;

  // ===== 參考常數 =====
  static const int _kSampleRate = 48000; // 引擎內部採樣率

  // ===== 軌道增益（dB 與 0..1 的互轉）=====
  static const double _gainDbMin = -60.0;
  static const double _gainDbMax = 0.0;

  double _gain01ToDb(double g) {
    if (g <= 0.0) return _gainDbMin;
    final db = 20.0 * (math.log(g) / math.ln10);
    return db.clamp(_gainDbMin, _gainDbMax);
  }

  double _dbToGain01(double db) {
    if (db <= _gainDbMin) return 0.0;
    final g = math.pow(10.0, db / 20.0).toDouble();
    return (g < 1e-3) ? 0.0 : g.clamp(0.0, 1.0);
  }

  bool trackMuted(int i) {
    if (i < 0 || i >= tracks.length) return false;
    return tracks[i].isMuted;
  }

  double trackGain(int i) {
    if (i < 0 || i >= tracks.length) return 0.0;
    return _dbToGain01(tracks[i].trackGainDb);
  }

  Future<void> toggleTrackMute(int i) async {
    if (i < 0 || i >= tracks.length) return;
    final t = tracks[i];
    t.setMute(!t.isMuted);
    _scheduleRebuild();
  }

  Future<void> setTrackGain(int i, double gain01) async {
    if (i < 0 || i >= tracks.length) return;
    tracks[i].setTrackGainDb(_gain01ToDb(gain01));
    _scheduleRebuild();
  }

  // ===== 初始化 / 釋放 =====
  Future<void> initAsync() async {
    if (tracks.isEmpty) {
      tracks.add(
        SingleTrackService(decoder: _decoder, onChanged: _onTrackChanged),
      );
      notifyListeners();
    }
    _pullSampleWindow(); // 預熱電平
  }

  @override
  void dispose() {
    _uiTicker?.cancel();
    _rebuildDebounce?.cancel();
    for (final t in tracks) {
      t.dispose();
    }
    _pb.dispose();
    playing.dispose();
    playhead.dispose();
    meter.dispose();
    snapGuide.dispose();
    super.dispose();
  }

  // ===== 播放控制 =====
  Future<void> togglePlay() async {
    if (!_pb.isLoaded) await _rebuildMasterAndLoad();
    if (_pb.isPlaying) {
      await _pb.pause();
      playing.value = false;
    } else {
      try {
        await _pb.play();
        playing.value = true;
        _startUiTicker();
      } catch (e) {
        debugPrint('Playback play failed: $e');
        playing.value = false;
      }
    }
  }

  Future<void> setVolume(double v) async => _pb.setVolume(v);

  void _startUiTicker() {
    _uiTicker?.cancel();
    _uiTicker = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!_pb.isPlaying) {
        _uiTicker?.cancel();
        return;
      }
      playhead.value = _pb.positionMs;
      _pullSampleWindow();
    });
  }

  // ===== 電平（簡化：取峰值）=====
  void _pullSampleWindow() {
    if (_masterPcmBytes != null && _masterSampleRate != null) {
      final startSample = ((_pb.positionMs / 1000.0) * _masterSampleRate!)
          .floor();
      final startByte = startSample << 1;
      final endByte = math.min(
        startByte + (_meterWindow << 1),
        _masterPcmBytes!.length,
      );

      final view = ByteData.sublistView(_masterPcmBytes!);
      var peak = 0, o = 0;
      for (
        int i = startByte;
        i + 1 < endByte && o < _meterWindow;
        i += 2, o++
      ) {
        final v = view.getInt16(i, Endian.little);
        _windowBuf[o] = v;
        final a = v >= 0 ? v : -v;
        if (a > peak) peak = a;
      }
      for (; o < _meterWindow; o++) _windowBuf[o] = 0;
      meter.value = (peak / 32768.0).clamp(0.0, 1.0);
      return;
    }

    _accBuf.fillRange(0, _meterWindow, 0);
    if (tracks.isEmpty) {
      for (int i = 0; i < _meterWindow; i++) _windowBuf[i] = 0;
      meter.value = 0;
      return;
    }
    for (final t in tracks) {
      final w = t.sampleForFft(positionMs: _pb.positionMs, count: _meterWindow);
      for (int i = 0; i < _meterWindow; i++) {
        _accBuf[i] += w[i];
      }
    }
    var peak = 0;
    for (int i = 0; i < _meterWindow; i++) {
      int v = _accBuf[i];
      if (v > 32767) {
        v = 32767;
      } else if (v < -32768) {
        v = -32768;
      }
      _windowBuf[i] = v;
      final a = v >= 0 ? v : -v;
      if (a > peak) peak = a;
    }
    meter.value = (peak / 32768.0).clamp(0.0, 1.0);
  }

  // ===== 匯入 =====
  Future<void> pickAndImportAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'aac', 'wav'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    await importFromPath(path);
  }

  Future<void> importFromPath(String path) async {
    final st = SingleTrackService(
      decoder: _decoder,
      onChanged: _onTrackChanged,
    );
    final sourceId = await st.decodeAndCache(path);
    final decoded = st.getDecoded(sourceId)!;

    st.addSegment(
      sourceId: sourceId,
      srcStartMs: 0,
      srcEndMs: decoded.durationMs,
      dstOffsetMs: 0,
    );
    st.rebuildRenderedNow();
    st.buildDownsampledWaveform(step: 128);

    tracks.add(st);
    await _rebuildMasterAndLoad();
    _pullSampleWindow();
    notifyListeners();
  }

  void removeTrackAt(int index) {
    if (index < 0 || index >= tracks.length) return;
    final t = tracks.removeAt(index);
    t.dispose();
    _rebuildMasterAndLoad();
    _pullSampleWindow();
    notifyListeners();
  }

  void reorderTracks(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final t = tracks.removeAt(oldIndex);
    tracks.insert(newIndex, t);
    _rebuildMasterAndLoad();
    notifyListeners();
  }

  // ===== 混音／載入播放器（保留播放位置與狀態）=====
  Future<void> _rebuildMasterAndLoad() async {
    final wasPlaying = _pb.isPlaying;
    final keepPosMs = _pb.isLoaded ? _pb.positionMs : playhead.value;

    if (tracks.isEmpty) {
      _masterPcmBytes = null;
      _masterSampleRate = null;
      await _pb.unload();
      playing.value = false;
      playhead.value = 0;
      return;
    }

    // 準備每軌資料
    final pcmList = <Uint8List>[];
    final gainsDb = <double>[];
    final mutes = <bool>[];
    final solos = <bool>[];
    const sr = _kSampleRate;

    for (final t in tracks) {
      final i16 = t.track.renderedPcm;
      if (i16.isEmpty) continue;
      pcmList.add(_i16ToBytes(i16));
      gainsDb.add(t.trackGainDb);
      mutes.add(t.isMuted);
      solos.add(t.isSolo);
    }

    if (pcmList.isEmpty) {
      _masterPcmBytes = null;
      _masterSampleRate = null;
      await _pb.unload();
      playing.value = false;
      playhead.value = 0;
      return;
    }

    // 混音（非同步）
    final mix = await MixBus.mixAsync(
      tracksS16: pcmList,
      gainsDb: gainsDb,
      mutes: mutes,
      solos: solos,
      sampleRate: sr,
    );

    // 給電平用的裸 PCM
    _masterPcmBytes = mix.pcmS16;
    _masterSampleRate = mix.sampleRate;

    // 播放用 WAV
    final wavBytes = _pcmS16MonoToWav(mix.pcmS16, mix.sampleRate);

    try {
      await _pb.load(bytes: wavBytes, sampleRate: mix.sampleRate);
    } catch (e) {
      debugPrint('Playback load failed: $e');
      rethrow;
    }

    // 還原播放位置（夾在新時長範圍內）
    final newDurMs = _pb.durationMs;
    final targetMs = (keepPosMs.clamp(0, newDurMs)) as int;
    await _pb.seekTo(targetMs);
    playhead.value = _pb.positionMs;

    // 還原播放狀態
    if (wasPlaying) {
      await _pb.play();
      playing.value = true;
      _startUiTicker();
    } else {
      playing.value = false;
    }
  }

  Uint8List _i16ToBytes(Int16List i16) {
    final out = Uint8List(i16.length * 2);
    final bd = ByteData.sublistView(out);
    for (int i = 0; i < i16.length; i++) {
      bd.setInt16(i << 1, i16[i], Endian.little);
    }
    return out;
  }

  // 對外 API
  Future<void> seekTo(int ms) async {
    if (!_pb.isLoaded) await _rebuildMasterAndLoad();
    await _pb.seekTo(ms);
    playhead.value = _pb.positionMs;
    _pullSampleWindow();
  }

  Future<void> rebuildMaster() async {
    await _rebuildMasterAndLoad();
    _pullSampleWindow();
    notifyListeners();
  }

  // ===== 內部：節流重建 =====
  void _scheduleRebuild([Duration delay = const Duration(milliseconds: 120)]) {
    if (_interactiveEditing) return; // 拖曳互動期間不重建
    _rebuildDebounce?.cancel();
    _rebuildDebounce = Timer(delay, () async {
      await rebuildMaster();
    });
  }

  void _onTrackChanged() {
    if (_interactiveEditing) return; // 拖曳中只動 UI
    _scheduleRebuild();
  }

  // --------------------------------------------------------------------------
  // 互動編輯（拖曳＋磁吸）
  // --------------------------------------------------------------------------

  bool _interactiveEditing = false;
  final Set<SingleTrackService> _touchedTracks = {};

  // 導引線（UI 畫高亮）
  final ValueNotifier<SnapPoint?> snapGuide = ValueNotifier<SnapPoint?>(null);

  late final SnapController snap;

  void beginInteractiveEdit() {
    if (_interactiveEditing) return;
    _interactiveEditing = true;
    _touchedTracks.clear();
    snap.beginDrag();
    snapGuide.value = null;
  }

  /// 拖曳過程：更新該段的目的時間，但【不重建混音】
  void updateInteractiveDrag({
    required SingleTrackService track,
    required Segment segment,
    required int rawMs,
    required bool snappingEnabled,
    String? excludeId,
  }) {
    // 第一次觸碰：暫停該軌渲染，避免每 1px 都重算
    final firstTouch = _touchedTracks.add(track);
    if (firstTouch) track.setRenderSuspended(true);

    // 磁吸
    int dst = rawMs;
    final res = snap.snapMs(
      rawMs,
      excludeId: excludeId,
      snappingEnabled: snappingEnabled,
    );
    if (res != null) {
      dst = res.snappedMs;
      snapGuide.value = res.target; // UI 畫導引線
    } else {
      snapGuide.value = null;
    }

    // 輕量位移（只改 segment.dstOffsetMs 與 UI）
    track.moveSegmentFast(segment, newDstOffsetMs: dst);
  }

  /// 放開手指/滑鼠：只重建 touched 軌 → 重建 master →（選擇性）seek
  Future<void> endInteractiveEdit({int? postSeekMs}) async {
    snap.endDrag();
    final touched = List<SingleTrackService>.from(_touchedTracks);
    _touchedTracks.clear();
    _interactiveEditing = false;
    snapGuide.value = null;

    // 解除渲染暫停並同步重建這些軌
    for (final t in touched) {
      t.setRenderSuspended(false);
      t.rebuildRenderedNow();
      t.buildDownsampledWaveform(step: 128);
    }

    // 重建 master，保留原播放狀態/位置
    await _rebuildMasterAndLoad();

    // 如指定，跳到新的位置（例：段落新起點）
    if (postSeekMs != null) {
      final ms = (postSeekMs.clamp(0, durationMs)) as int;
      await seekTo(ms);
    }
  }

  // 收集可磁吸的片段邊緣
  List<SnapPoint> _collectClipEdgePoints({String? excludeId}) {
    final points = <SnapPoint>[];
    for (final t in tracks) {
      for (final s in t.track.segments) {
        if (excludeId != null && s.id == excludeId) continue;
        final start = s.dstOffsetMs;
        final end = start + s.srcDurationMs;
        points.add(SnapPoint(start, 'clip-start'));
        points.add(SnapPoint(end, 'clip-end'));
      }
    }
    return points;
  }

  // ===== WAV 封裝 =====
  Uint8List _pcmS16MonoToWav(Uint8List pcmS16le, int sampleRate) {
    const int numChannels = 1;
    const int bitsPerSample = 16;
    final int byteRate = sampleRate * numChannels * (bitsPerSample >> 3);
    final int blockAlign = numChannels * (bitsPerSample >> 3);
    final int dataLen = pcmS16le.lengthInBytes;
    final int totalLen = 44 + dataLen; // WAV header 44 bytes

    final out = Uint8List(totalLen);
    final bd = ByteData.sublistView(out);

    // 'RIFF'
    out.setAll(0, [0x52, 0x49, 0x46, 0x46]);
    bd.setUint32(4, 36 + dataLen, Endian.little);
    // 'WAVE'
    out.setAll(8, [0x57, 0x41, 0x56, 0x45]);
    // 'fmt '
    out.setAll(12, [0x66, 0x6D, 0x74, 0x20]);
    bd.setUint32(16, 16, Endian.little); // Subchunk1Size
    bd.setUint16(20, 1, Endian.little); // AudioFormat=PCM
    bd.setUint16(22, numChannels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, byteRate, Endian.little);
    bd.setUint16(32, blockAlign, Endian.little);
    bd.setUint16(34, bitsPerSample, Endian.little);
    // 'data'
    out.setAll(36, [0x64, 0x61, 0x74, 0x61]);
    bd.setUint32(40, dataLen, Endian.little);

    // PCM payload
    out.setRange(44, 44 + dataLen, pcmS16le);
    return out;
  }
}
