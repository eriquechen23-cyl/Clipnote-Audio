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

// 自動對位（你之前加的）
import 'package:clipnote_audio/modules/editing/snapping.dart';

class MainEditorService extends ChangeNotifier {
  MainEditorService({PcmDecoder? decoder})
    : _decoder = decoder ?? const FfmpegKitDecoder();

  final PcmDecoder _decoder;

  // 狀態
  final List<SingleTrackService> tracks = [];
  final PlaybackService _pb = PlaybackService.instance;

  Uint8List? _masterPcmBytes; // s16le mono
  int? _masterSampleRate;

  // UI notifiers
  final ValueNotifier<bool> playing = ValueNotifier(false);
  final ValueNotifier<int> playhead = ValueNotifier(0); // ms
  final ValueNotifier<double> meter = ValueNotifier(0); // 0..1

  Listenable get uiTick => Listenable.merge([playing, playhead, meter]);

  // meter 視窗
  static const int _meterWindow = 2048;
  final Int16List _windowBuf = Int16List(_meterWindow);
  final Int32List _accBuf = Int32List(_meterWindow);

  Timer? _uiTicker;
  double get volume01 => _pb.volume;
  int get durationMs => _pb.durationMs;
  int get playheadMs => playhead.value;
  bool get isPlaying => playing.value;
  double get meterPeak01 => meter.value;

  // —— Snapping —— //
  final ValueNotifier<SnapPoint?> snapGuide = ValueNotifier<SnapPoint?>(null);
  late final SnapController snap = SnapController(
    getClipEdgePoints: ({String? excludeId}) =>
        _collectClipEdgePoints(excludeId: excludeId),
    getPlayheadMs: () => _pb.positionMs,
    getDurationMs: () => durationMs,
    config: const SnapConfig(
      thresholdMs: 18,
      gridStepMs: 500,
      toClips: true,
      toPlayhead: true,
      toGrid: true,
    ),
  );

  // NEW: 互動編輯旗標（拖曳中）
  bool _interactiveEditing = false;

  // === 放進 MainEditorService 類別內（任一成員區即可）===

  // 建議把軌道增益限制在 -60 dB ~ 0 dB（0 dB = 1.0）
  static const double _gainDbMin = -60.0;
  static const double _gainDbMax = 0.0;

  // 0..1 線性 → dB；0 代表靜音（取下限 -60 dB）
  double _gain01ToDb(double g) {
    if (g <= 0.0) return _gainDbMin;
    final db = 20.0 * (math.log(g) / math.ln10);
    return db.clamp(_gainDbMin, _gainDbMax);
  }

  // dB → 0..1 線性；<= -60 dB 視為 0
  double _dbToGain01(double db) {
    if (db <= _gainDbMin) return 0.0;
    final g = math.pow(10.0, db / 20.0).toDouble();
    // 極小值視覺上算 0，避免滑桿殘影
    return (g < 1e-3) ? 0.0 : g.clamp(0.0, 1.0);
  }

  // 讀靜音狀態
  bool trackMuted(int i) {
    if (i < 0 || i >= tracks.length) return false;
    return tracks[i].isMuted;
  }

  // 讀增益（0..1 給 UI Slider 用）
  double trackGain(int i) {
    if (i < 0 || i >= tracks.length) return 0.0;
    return _dbToGain01(tracks[i].trackGainDb);
  }

  // ✅ 正確：呼叫 SingleTrackService.setMute()
  Future<void> toggleTrackMute(int i) async {
    if (i < 0 || i >= tracks.length) return;
    final t = tracks[i];
    t.setMute(!t.isMuted);
    await rebuildMaster();
  }

  // ❌ 原本錯誤：tracks[i].trackGainDb = _gain01ToDb(gain01);
  // ✅ 正確：呼叫 SingleTrackService.setTrackGainDb()
  Future<void> setTrackGain(int i, double gain01) async {
    if (i < 0 || i >= tracks.length) return;
    tracks[i].setTrackGainDb(_gain01ToDb(gain01));
    await rebuildMaster();
  }

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

  Future<void> initAsync() async {
    // 預設兩條空軌（可直接拖片段進來）
    if (tracks.isEmpty) {
      tracks.add(
        SingleTrackService(decoder: _decoder, onChanged: _onTrackChanged),
      );
      notifyListeners();
    }
    _pullSampleWindow(); // 預熱電平
  }

  void _onTrackChanged() {
    // 若正在互動編輯，不主動重建 master；結束時統一重建
    if (!_interactiveEditing) {
      rebuildMaster();
    }
  }

  @override
  void dispose() {
    _uiTicker?.cancel();
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
        debugPrint('Playback play failed: $e'); // 避免未處理例外
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

  // ===== 電平（略） =====
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
      if (v > 32767)
        v = 32767;
      else if (v < -32768)
        v = -32768;
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

  // ===== 混音／載入播放器 =====
  // 替換整個 _rebuildMasterAndLoad()
  Future<void> _rebuildMasterAndLoad() async {
    if (tracks.isEmpty) {
      _masterPcmBytes = null;
      _masterSampleRate = null;
      await _pb.unload();
      playing.value = false;
      playhead.value = 0;
      return;
    }

    final pcmList = <Uint8List>[];
    final gainsDb = <double>[];
    final mutes = <bool>[];
    final solos = <bool>[];
    const sr = kSampleRate;

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

    final mix = await MixBus.mixAsync(
      tracksS16: pcmList,
      gainsDb: gainsDb,
      mutes: mutes,
      solos: solos,
      sampleRate: sr,
    );

    // 1) 電平/分析用：保留裸 PCM
    _masterPcmBytes = mix.pcmS16;
    _masterSampleRate = mix.sampleRate;

    // 2) 播放器用：包成 WAV
    final wavBytes = _pcmS16MonoToWav(mix.pcmS16, mix.sampleRate);

    try {
      await _pb.load(bytes: wavBytes, sampleRate: mix.sampleRate);
    } catch (e) {
      debugPrint('Playback load failed: $e');
      rethrow;
    }

    if (_pb.isPlaying) {
      await _pb.play();
      playing.value = true;
      _startUiTicker();
    } else {
      playing.value = false;
    }
    playhead.value = _pb.positionMs;
  }

  Uint8List _i16ToBytes(Int16List i16) {
    final out = Uint8List(i16.length * 2);
    final bd = ByteData.sublistView(out);
    for (int i = 0; i < i16.length; i++) {
      bd.setInt16(i << 1, i16[i], Endian.little);
    }
    return out;
  }

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

  // ====== 互動編輯 API（給 Waveform 手勢用） ======
  void beginInteractiveEdit() {
    _interactiveEditing = true;
    for (final t in tracks) {
      t.setRenderSuspended(true);
    }
    // 清掉暫存指引線
    snapGuide.value = null;
  }

  /// 拖曳中：回傳吸附後的位置（毫秒），同時只更新 UI，不重建
  int updateInteractiveDrag({
    required SingleTrackService track,
    required Segment segment,
    required int rawMs,
    String? excludeId,
  }) {
    final res = snap.snapMs(rawMs, excludeId: excludeId);
    final snapMs = res?.snappedMs ?? rawMs;
    if (res != null) snapGuide.value = res.target;
    track.moveSegmentFast(segment, newDstOffsetMs: snapMs); // 不渲染
    return snapMs;
  }

  /// 結束拖曳：清指引線、恢復渲染，然後一次重建/混音
  Future<void> endInteractiveEdit() async {
    snapGuide.value = null;
    for (final t in tracks) {
      t.setRenderSuspended(false);
      t.rebuildRenderedNow();
      t.buildDownsampledWaveform(step: 128);
    }
    _interactiveEditing = false;
    await rebuildMaster();
  }

  // —— 供磁吸掃描 —— //
  List<SnapPoint> _collectClipEdgePoints({String? excludeId}) {
    final points = <SnapPoint>[];
    for (final t in tracks) {
      final segs = t.track.segments;
      for (final s in segs) {
        final sid = (s.id ?? '').toString();
        if (excludeId != null && sid == excludeId) continue;
        final start = s.dstOffsetMs;
        final end = start + s.srcDurationMs;
        points.add(SnapPoint(start, 'clip-start'));
        points.add(SnapPoint(end, 'clip-end'));
      }
    }
    return points;
  }
}
