import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';

class PlaybackService {
  static final PlaybackService instance = PlaybackService._internal();
  PlaybackService._internal() {
    _configureAudioContext();
    _subs.addAll([
      _player.onPlayerStateChanged.listen((s) {
        _isPlaying = s == PlayerState.playing;
      }),
      _player.onPositionChanged.listen((d) {
        _positionMs = d.inMilliseconds;
        _maybeRecalcMeter();
      }),
      _player.onDurationChanged.listen((d) {
        _durationMs = d.inMilliseconds;
      }),
      _player.onPlayerComplete.listen((_) {
        _isPlaying = false;
        _positionMs = _durationMs;
      }),
    ]);
  }

  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription> _subs = [];

  bool _isLoaded = false;
  bool _isPlaying = false;
  int _positionMs = 0;
  int _durationMs = 0;

  bool get isLoaded => _isLoaded;
  bool get isPlaying => _isPlaying;
  int get positionMs => _positionMs;
  int get durationMs => _durationMs;

  // 電平
  double _meterPeak01 = 0;
  double get meterPeak01 => _meterPeak01;

  Int16List? _pcmI16;
  int? _sampleRate;

  double _volume = 1.0;
  double get volume => _volume;

  double _speed = 1.0;
  double get speed => _speed;

  Future<void> _configureAudioContext() async {
    await _player.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: [AVAudioSessionOptions.duckOthers],
        ),
        android: AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ),
    );
    await _player.setReleaseMode(ReleaseMode.stop);
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    await _player.setVolume(_volume);
  }

  Future<void> setSpeed(double r) async {
    _speed = r.clamp(0.5, 2.0);
    await _player.setPlaybackRate(_speed);
  }

  Future<void> load({required Uint8List bytes, required int sampleRate}) async {
    _pcmI16 = _bytesToI16(bytes);
    _sampleRate = sampleRate;
    final wav = _wrapS16AsWav(bytes, sampleRate, channels: 1);
    await _player.stop();
    await _player.setSource(BytesSource(wav));
    await _player.setPlaybackRate(_speed);
    await _player.setVolume(_volume);
    _isLoaded = true;
    _positionMs = 0;
  }

  Future<void> play() async {
    if (!_isLoaded) return;
    await _player.resume();
    _isPlaying = true;
  }

  Future<void> pause() async {
    if (!_isLoaded) return;
    await _player.pause();
    _isPlaying = false;
  }

  Future<void> seekTo(int ms) async {
    if (!_isLoaded) return;
    await _player.seek(Duration(milliseconds: ms));
    _positionMs = ms;
    _maybeRecalcMeter(force: true);
  }

  Future<void> unload() async {
    await _player.stop();
    _isLoaded = false;
    _isPlaying = false;
    _positionMs = 0;
    _durationMs = 0;
    _pcmI16 = null;
    _sampleRate = null;
    _meterPeak01 = 0;
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
  }

  // ====== 電平（節流） ======
  static const int _meterIntervalMs = 60;
  int _lastMeterCalcTick = 0;
  void _maybeRecalcMeter({bool force = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastMeterCalcTick < _meterIntervalMs) return;
    _lastMeterCalcTick = now;
    _recalcMeter();
  }

  void _recalcMeter() {
    final pcm = _pcmI16;
    final sr = _sampleRate;
    if (pcm == null || sr == null) {
      _meterPeak01 = 0;
      return;
    }
    const win = 2048;
    final startSample = ((_positionMs / 1000.0) * sr).floor();
    int peak = 0;
    final end = math.min(startSample + win, pcm.length);
    for (int idx = startSample; idx < end; idx++) {
      final v = pcm[idx].abs();
      if (v > peak) peak = v;
    }
    _meterPeak01 = (peak / 32768.0).clamp(0.0, 1.0);
  }

  // ====== 小工具 ======
  Int16List _bytesToI16(Uint8List b) {
    final bd = ByteData.sublistView(b);
    final len = b.length ~/ 2;
    final out = Int16List(len);
    for (int i = 0; i < len; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little);
    }
    return out;
  }

  Uint8List _wrapS16AsWav(
    Uint8List pcmS16,
    int sampleRate, {
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = pcmS16.length;
    final chunkSize = 36 + dataSize;

    final header = BytesBuilder()
      ..add(_ascii('RIFF'))
      ..add(_le32(chunkSize))
      ..add(_ascii('WAVE'))
      ..add(_ascii('fmt '))
      ..add(_le32(16))
      ..add(_le16(1))
      ..add(_le16(channels))
      ..add(_le32(sampleRate))
      ..add(_le32(byteRate))
      ..add(_le16(blockAlign))
      ..add(_le16(bitsPerSample))
      ..add(_ascii('data'))
      ..add(_le32(dataSize));

    final out = BytesBuilder()
      ..add(header.toBytes())
      ..add(pcmS16);
    return out.toBytes();
  }

  Uint8List _le16(int v) {
    final b = Uint8List(2);
    ByteData.sublistView(b).setUint16(0, v, Endian.little);
    return b;
  }

  Uint8List _le32(int v) {
    final b = Uint8List(4);
    ByteData.sublistView(b).setUint32(0, v, Endian.little);
    return b;
  }

  Uint8List _ascii(String s) => Uint8List.fromList(s.codeUnits);
}
