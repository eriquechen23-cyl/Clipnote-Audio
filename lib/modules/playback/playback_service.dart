import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:clipnote_audio/modules/decoding/pcm_player.dart';

/// 統一播放管理（單例）：load / play / pause / seek / 播放頭推進
class PlaybackService extends ChangeNotifier {
  PlaybackService._();
  static final PlaybackService instance = PlaybackService._();

  PcmPlayer? _player;
  Timer? _ticker;
  int _epoch = 0;

  bool _isPlaying = false;
  bool _isScrubbing = false;
  int _playheadMs = 0;
  int _durationMs = 0;

  // 以秒錶為主，避免部分平台 position 不更新
  final Stopwatch _sw = Stopwatch();
  int _baseMs = 0;

  bool get isReady => _player != null;
  bool get isPlaying => _isPlaying;
  bool get isScrubbing => _isScrubbing;
  int get playheadMs => _playheadMs;
  int get durationMs => _durationMs;

  /// 提供給 UI 使用的「即時位置」
  /// 播放中直接用 _baseMs + 秒錶，確保每次讀取都會前進
  int get uiPositionMs {
    if (_isPlaying && !_isScrubbing) {
      final ms = _baseMs + _sw.elapsedMilliseconds;
      return ms.clamp(0, _durationMs);
    }
    return _playheadMs.clamp(0, _durationMs);
  }

  /// 載入 PCM（16bit）與取樣率
  Future<void> load(Uint8List pcm, int sampleRate) async {
    debugPrint('[PB] load() bytes=${pcm.length}, sr=$sampleRate');
    if (pcm.isEmpty || sampleRate <= 0) {
      debugPrint('[PB] load() aborted: empty pcm or invalid sr');
      return;
    }

    _player ??= PcmPlayer();
    await _player!.load(pcm, sampleRate);

    // 先以單聲道計（2 bytes/int16）
    int channels = 1;
    const bytesPerSample = 2;
    int frames = pcm.length ~/ (bytesPerSample * channels);
    int durMs = (frames * 1000 ~/ sampleRate);

    // 若時長仍為 0 且長度為 4 的倍數，推估為雙聲道
    if (durMs == 0 && pcm.length % 4 == 0) {
      channels = 2;
      frames = pcm.length ~/ (bytesPerSample * channels);
      durMs = (frames * 1000 ~/ sampleRate);
      debugPrint('[PB] fallback stereo durationMs=$durMs');
    }

    _durationMs = durMs;
    _playheadMs = 0;
    _baseMs = 0;
    _isPlaying = false;

    _stopTicker();
    _sw.stop();

    debugPrint('[PB] durationMs=$_durationMs');
    notifyListeners(); // 先讓右側總長更新
  }

  Future<void> play() async {
    if (_player == null) return;
    if (_isPlaying) return;
    final my = ++_epoch;

    await _player!.play();
    if (my != _epoch) return;

    _isPlaying = true;
    _baseMs = _playheadMs;
    _sw
      ..reset()
      ..start();
    _startTicker();
    notifyListeners(); // 立刻推一次（避免等第一個 tick）
  }

  Future<void> pause() async {
    if (_player == null) return;
    _epoch++;
    _isPlaying = false;

    _stopTicker();
    _sw.stop();

    // 將目前 UI 播放頭落盤
    _playheadMs = (_baseMs + _sw.elapsedMilliseconds).clamp(0, _durationMs);

    try {
      await _player!.pause().timeout(
        const Duration(milliseconds: 600),
        onTimeout: () {},
      );
    } catch (_) {}

    notifyListeners();
  }

  /// 跳到指定毫秒
  Future<void> seekMs(int ms) async {
    final clamped = ms.clamp(0, _durationMs);
    _playheadMs = clamped;

    // 若正在播，重新校正秒錶基準
    if (_isPlaying) {
      _baseMs = _playheadMs;
      _sw
        ..reset()
        ..start();
    }

    try {
      final dyn = _player as dynamic; // 沒實作 seek 也不會崩
      await dyn.seek(Duration(milliseconds: _playheadMs));
    } catch (_) {}

    notifyListeners();
  }

  // ===== 拖曳流程 =====
  void beginScrub() {
    _isScrubbing = true;
    _stopTicker();
    _sw.stop();
    notifyListeners();
  }

  void updateScrub(int ms) {
    _playheadMs = ms.clamp(0, _durationMs);
    notifyListeners();
  }

  Future<void> endScrub(int ms) async {
    await seekMs(ms);
    _isScrubbing = false;
    if (_isPlaying) {
      _sw
        ..reset()
        ..start();
      _startTicker();
    }
    notifyListeners();
  }

  // ===== 內部 ticker（校正 _playheadMs，但 UI 讀 uiPositionMs）=====
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (_player == null || !_isPlaying || _isScrubbing) return;

      // 以秒錶為主的即時計算
      int ms = _baseMs + _sw.elapsedMilliseconds;

      // 若原生位置可用且差距大，用原生校正一次基準
      try {
        final p = _player!.position.inMilliseconds;
        if ((p - ms).abs() > 80) {
          ms = p;
          _baseMs = p;
          _sw
            ..reset()
            ..start();
        }
      } catch (_) {}

      _playheadMs = ms.clamp(0, _durationMs);
      notifyListeners(); // 不論是否改變都通知，讓外層能重繪
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// 停止並釋放底層播放器
  Future<void> stopAndRelease() async {
    _isPlaying = false;
    _stopTicker();
    _sw.stop();
    try {
      await _player?.pause().timeout(
        const Duration(milliseconds: 300),
        onTimeout: () {},
      );
    } catch (_) {}
    try {
      final dyn = _player as dynamic;
      await dyn.stop?.call();
      await dyn.flush?.call();
    } catch (_) {}
    try {
      await _player?.dispose();
    } catch (_) {}

    _player = null;
    _playheadMs = 0;
    _durationMs = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTicker();
    _player?.dispose();
    _player = null;
    super.dispose();
  }
}
