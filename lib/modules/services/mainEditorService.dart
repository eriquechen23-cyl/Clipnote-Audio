// lib/modules/services/mainEditorService.dart
// ClipNote — MainEditorService（Lite：移除頻譜功能 + 互動編輯/磁吸）

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

import 'package:clipnote_audio/modules/decoding/ffmpeg_decoder.dart';
import 'package:clipnote_audio/modules/services/singleTrackService.dart';
import 'package:clipnote_audio/modules/merge_mix/mix_bus.dart';
import 'package:clipnote_audio/modules/playback/playbackService.dart';

// 自動對位（磁吸）
import 'package:clipnote_audio/modules/editing/snapping.dart';
import 'package:flutter/services.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

enum AudioExportFormat { mp3, m4a, wav }

class MainEditorService extends ChangeNotifier {
  MainEditorService({PcmDecoder? decoder})
    : _decoder = decoder ?? const FfmpegKitDecoder() {
    snap = SnapController(
      getClipEdgePoints: ({String? excludeId}) =>
          _collectClipEdgePoints(excludeId: excludeId),
      // ★ 用顯示用播放頭（含 A/V 補償），畫面上的紅線一致
      getPlayheadMs: () => displayPlayheadMs,
      // ★ 用時間軸總長，不要用播放器長度
      getDurationMs: () => timelineTotalMs,
    );
  }

  // ★ 新增：時間軸總長（專案視角）
  int get timelineTotalMs {
    int ms = 0;
    for (final t in tracks) {
      // 軌本身預估長度
      ms = math.max(ms, t.durationMs);
      // 每個片段的實際終點
      for (final s in t.track.segments) {
        ms = math.max(ms, s.dstOffsetMs + s.srcDurationMs);
      }
    }
    // 後備：若全空，至少回傳 0
    return ms;
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

  // —— A/V 補償（毫秒）：UI 顯示用「實際聽到」時間 ——
  // 你可依裝置微調，先給 80ms 常見值
  int _avOffsetMs = 80;
  int get avOffsetMs => _avOffsetMs;
  set avOffsetMs(int v) => _avOffsetMs = v.clamp(0, 250);

  // 補償後的播放頭（播放時才減去偏移；暫停就回傳原始位置）
  int get displayPlayheadMs {
    final p = _pb.positionMs; // 或你的播放服務目前時間
    if (!_pb.isPlaying) return p; // 暫停不補償
    final d = p - _avOffsetMs;
    return d < 0 ? 0 : d;
  }

  // 類別 MainEditorService 內：加/覆蓋這些成員
  // 全域磁吸總開關（UI 可綁一個 Toggle）
  final ValueNotifier<bool> snapEnabled = ValueNotifier<bool>(true);

  // 指引線：畫在 TrackLane 的青色細線
  final ValueNotifier<SnapPoint?> snapGuide = ValueNotifier<SnapPoint?>(null);
  // 新增（用來畫「另一端」那條線）
  final ValueNotifier<int?> snapGuideOppositeMs = ValueNotifier<int?>(null);
  // Snapping 控制器（用 modules/editing/snapping.dart 這套）
  late final SnapController snap;

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
    snapGuideOppositeMs.dispose(); // ★ 新增
    super.dispose();
  }

  // ===== 播放控制 =====
  Future<void> togglePlay() async {
    if (!_pb.isLoaded) await _rebuildMasterAndLoad();

    if (_pb.isPlaying) {
      await _pb.pause();
      playing.value = false;
    } else {
      // ★ 在結尾就先歸零
      final atEnd =
          (_pb.durationMs > 0) && (_pb.positionMs >= _pb.durationMs - 5);
      if (atEnd) {
        await _pb.seekTo(0);
        playhead.value = 0; // 立刻更新 UI
      }

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
      final pos = _pb.positionMs;
      final dur = _pb.durationMs;
      final ended = dur > 0 && pos >= dur - 5;

      // ★ 播放結束或不是播放狀態
      if (!_pb.isPlaying || ended) {
        _uiTicker?.cancel();

        if (ended) {
          // 自然播完：變回播放鈕並歸零
          playing.value = false;
          playhead.value = 0;
          // fire-and-forget，避免 await 阻塞計時器
          _pb.pause();
          _pb.seekTo(0);
        } else {
          // 使用者按了暫停：停在當前位置
          playing.value = false;
          playhead.value = pos;
        }
        return;
      }

      // 正常播放中：更新位置與電平
      playhead.value = pos;
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
    _masterPcmBytes = mix.pcmS16; // s16le mono
    _masterSampleRate = mix.sampleRate;

    // ✅ 直接把「原始 PCM」交給 PlaybackService（它內部會包 WAV 並等待 ready）
    try {
      await _pb.load(pcmS16: mix.pcmS16, sampleRate: mix.sampleRate);
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

  // ───────────────── 互動編輯（拖曳＋磁吸）─────────────────

  bool _interactiveEditing = false;
  final Set<SingleTrackService> _touchedTracks = {};

  void beginInteractiveEdit() {
    if (_interactiveEditing) return;
    _interactiveEditing = true;
    _touchedTracks.clear();
    snap.beginDrag();
    snapGuide.value = null;
    snapGuideOppositeMs.value = null; // ★ 新增
  }

  /// 拖曳過程：更新該段的目的時間，但【不重建混音】
  // lib/modules/services/mainEditorService.dart（類別 MainEditorService 內）

  void updateInteractiveDrag({
    required SingleTrackService track,
    required Segment segment,
    required int rawMs,
    required bool snappingEnabled,
    required double pxPerMs,
    String? excludeId,
  }) {
    final firstTouch = _touchedTracks.add(track);
    if (firstTouch) track.setRenderSuspended(true);

    // 門檻用像素感知
    final desiredPx = 12.0;
    final thrMs = (desiredPx / pxPerMs).round().clamp(1, 1 << 30);
    if (snap.config.thresholdMs != thrMs) {
      snap.config = snap.config.copyWith(thresholdMs: thrMs);
    }

    final dur = segment.srcDurationMs;

    // ---------- 1) 只看「片段邊緣」的候選（跨所有音軌），優先判斷 butt ----------
    int? nearestClipMs(int targetMs) {
      int bestDelta = 1 << 30;
      int? bestMs;
      for (final p in _collectClipEdgePoints(excludeId: excludeId)) {
        // 只收 clip-start / clip-end
        if (p.tag != 'clip-start' && p.tag != 'clip-end') continue;
        final d = (p.ms - targetMs).abs();
        if (d < bestDelta) {
          bestDelta = d;
          bestMs = p.ms;
        }
      }
      return (bestDelta <= thrMs) ? bestMs : null;
    }

    // 左端（起點）對別人的邊
    final startJoinMs = snappingEnabled && snapEnabled.value
        ? nearestClipMs(rawMs)
        : null;

    // 右端（rawMs + dur）對別人的邊
    final endJoinMs = snappingEnabled && snapEnabled.value
        ? nearestClipMs(rawMs + dur)
        : null;

    int dst = rawMs;

    if (startJoinMs != null || endJoinMs != null) {
      // 兩端都命中就取較近者（避免被網格/播放頭搶走）
      final dStart = (startJoinMs != null)
          ? (startJoinMs - rawMs).abs()
          : 1 << 30;
      final dEnd = (endJoinMs != null)
          ? (endJoinMs - (rawMs + dur)).abs()
          : 1 << 30;

      if (dEnd <= dStart && endJoinMs != null) {
        // 右端貼到別人的邊：接縫=endJoinMs，起點=接縫-長度
        final join = endJoinMs;
        dst = (join - dur).clamp(0, durationMs);
        snapGuide.value = SnapPoint(join, 'butt'); // 畫接縫線（跨軌也會畫）
      } else {
        // 左端貼到別人的邊：接縫=startJoinMs，起點=接縫
        final join = startJoinMs!;
        dst = join.clamp(0, durationMs);
        snapGuide.value = SnapPoint(join, 'butt');
      }
    } else {
      // ---------- 2) 完全沒 butt 命中 → 退回一般吸附（網格/播放頭/片段邊），不畫線 ----------
      final res = snap.snapMs(
        rawMs,
        excludeId: excludeId,
        snappingEnabled: snappingEnabled && snapEnabled.value,
      );
      if (res != null) {
        dst = res.snappedMs;
      } else {
        dst = rawMs;
      }
      snapGuide.value = null;
    }

    // 快移（不重建混音）
    track.moveSegmentFast(segment, newDstOffsetMs: dst);
  }

  /// 放開手指/滑鼠：只重建 touched 軌 → master →（選擇性）seek
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

    snap.endDrag();
    snapGuide.value = null;
    snapGuideOppositeMs.value = null; // ★ 新增
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

  // ===== 離線匯出（產出暫存檔）=====
  Future<String> exportMix({
    required AudioExportFormat format,
    int bitrateKbps = 192,
    String? suggestFileName,
  }) async {
    // 確保 master 重新混音到最新
    await _rebuildMasterAndLoad();
    if (_masterPcmBytes == null || _masterSampleRate == null) {
      throw StateError('沒有可匯出的混音內容。');
    }

    final tmpDir = await getTemporaryDirectory();
    final base = (suggestFileName == null || suggestFileName.trim().isEmpty)
        ? 'clipnote_${DateTime.now().millisecondsSinceEpoch}'
        : suggestFileName.trim();

    final wavPath = '${tmpDir.path}/$base-master.wav';
    final outPath = switch (format) {
      AudioExportFormat.wav => '${tmpDir.path}/$base.wav',
      AudioExportFormat.mp3 => '${tmpDir.path}/$base.mp3',
      AudioExportFormat.m4a => '${tmpDir.path}/$base.m4a',
    };

    // 先寫暫存 WAV（單聲道 s16）
    final wavBytes = _pcmS16MonoToWav(_masterPcmBytes!, _masterSampleRate!);
    await File(wavPath).writeAsBytes(wavBytes, flush: true);

    // WAV 直接用
    if (format == AudioExportFormat.wav) {
      await File(outPath).writeAsBytes(wavBytes, flush: true);
      try {
        await File(wavPath).delete();
      } catch (_) {}
      return outPath;
    }

    // 用 FFmpeg 轉 AAC(M4A) 或 MP3
    final sr = _masterSampleRate!;
    final cmd = (format == AudioExportFormat.m4a)
        ? '-y -i "$wavPath" -vn -ac 1 -ar $sr -c:a aac -b:a ${bitrateKbps}k -movflags +faststart "$outPath"'
        : '-y -i "$wavPath" -vn -ac 1 -ar $sr -c:a libmp3lame -b:a ${bitrateKbps}k "$outPath"';

    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();

    // MP3 可能因缺 libmp3lame 失敗 → 直接提示改用 M4A
    if (!ReturnCode.isSuccess(rc)) {
      final logs = (await session.getAllLogs())
          .map((l) => l.getMessage())
          .join('\n')
          .toLowerCase();
      if (format == AudioExportFormat.mp3 &&
          (logs.contains('unknown encoder \'libmp3lame\'') ||
              logs.contains('encoder (libmp3lame) not found') ||
              logs.contains('invalid audio encoder'))) {
        try {
          await File(wavPath).delete();
        } catch (_) {}
        throw UnsupportedError('此 FFmpeg 變體未內建 MP3 編碼器 (libmp3lame)。請改匯出 M4A。');
      }
      try {
        await File(wavPath).delete();
      } catch (_) {}
      throw Exception('FFmpeg 轉檔失敗：$rc\n$logs');
    }

    try {
      await File(wavPath).delete();
    } catch (_) {}
    return outPath;
  }

  // ===== 存到「下載資料夾」：行動端 FileSaver、桌面 ~/Downloads、後備 FlutterFileDialog =====
  Future<String> exportMixToDownloads({
    required AudioExportFormat format,
    int bitrateKbps = 192,
    String? suggestFileName,
  }) async {
    // 先產出暫存檔（存到 app 暫存）
    final tmpPath = await exportMix(
      format: format,
      bitrateKbps: bitrateKbps,
      suggestFileName: suggestFileName,
    );
    final bytes = await File(tmpPath).readAsBytes();

    final fm = _extAndMime(format); // 你原本的 ext/mime
    final base = (suggestFileName == null || suggestFileName.trim().isEmpty)
        ? 'clipnote_mix'
        : suggestFileName.trim();
    final displayName = '$base.${fm.ext}';

    if (Platform.isAndroid) {
      final sdk = await _androidSdkInt();
      // API 28 以下要舊權限
      if (sdk <= 28) {
        final ok = await Permission.storage.request();
        if (!ok.isGranted) throw Exception('需要儲存權限才能寫入下載資料夾');
      }
      final saved = await _mediaCh.invokeMethod<String>('saveToDownloads', {
        'bytes': bytes,
        'displayName': displayName,
        'mime': fm.mime, // 'audio/mpeg' / 'audio/mp4' / 'audio/wav'
        'subdir': 'ClipNote', // 會到「Download/ClipNote/」
      });
      try {
        await File(tmpPath).delete();
      } catch (_) {}
      if (saved == null) throw Exception('寫入失敗');
      return saved; // Android 10+ 是 content:// URI，舊機是實體路徑
    }

    // 其他平台照你既有流程（桌面 ~/Downloads；iOS 顯示存檔對話框）
    // ...（保留你原本的分支）...
    return tmpPath;
  }

  // 副檔名 + MIME
  ({String ext, String mime}) _extAndMime(AudioExportFormat f) {
    switch (f) {
      case AudioExportFormat.mp3:
        return (ext: 'mp3', mime: 'audio/mpeg');
      case AudioExportFormat.m4a:
        return (ext: 'm4a', mime: 'audio/mp4'); // 部分平台也接受 audio/aac
      case AudioExportFormat.wav:
        return (ext: 'wav', mime: 'audio/wav');
    }
  }

  // 小工具：join
  String _pJoin(String a, String b) {
    if (a.endsWith(Platform.pathSeparator)) return '$a$b';
    return '$a${Platform.pathSeparator}$b';
  }

  static const _mediaCh = MethodChannel('clipnote/media');

  Future<int> _androidSdkInt() async {
    if (!Platform.isAndroid) return 0;
    final info = await DeviceInfoPlugin().androidInfo;
    return info.version.sdkInt;
  }

  // lib/modules/services/mainEditorService.dart（類別裡加入）
  /// 例如 bpm=120, division=4 表示「四分音符」；division=8 是八分音符。
  void setGridByBpm({required double bpm, int division = 4}) {
    if (bpm <= 0) return;
    final msPerBeat = 60000.0 / bpm; // 四分音符毫秒
    final factor = division / 4.0; // 4→1倍；8→2倍；16→4倍...
    final stepMs = (msPerBeat / (1 / factor)).round(); // 換算該分割的毫秒
    snap.config = snap.config.copyWith(
      toGrid: true,
      gridStepMs: stepMs.clamp(1, 1 << 30),
    );
  }

  /// 也給個固定毫秒網格的 API（例如 250ms）
  void setGridMs(int stepMs) {
    snap.config = snap.config.copyWith(
      toGrid: true,
      gridStepMs: stepMs.clamp(1, 1 << 30),
    );
  }

  // ★ 取「某毫秒」附近最近的片段邊緣（不含自己）
  SnapPoint? _nearestClipEdgeAround(int ms, {String? excludeId}) {
    final pts = _collectClipEdgePoints(excludeId: excludeId);
    if (pts.isEmpty) return null;
    SnapPoint? best;
    var bestD = 1 << 30;
    for (final p in pts) {
      final d = (p.ms - ms).abs();
      if (d < bestD) {
        best = p;
        bestD = d;
      }
    }
    return best;
  }
}
