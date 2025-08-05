import 'dart:math' as math;
import 'dart:typed_data';

/// MixBus 接受多條 PCM 音軌，於時間軸上對齊並加總產生混音結果。
class MixBus {
  final int sampleRate;
  final Map<String, _Track> _tracks = {};
  Uint8List? _cache;

  MixBus(this.sampleRate);

  /// 加入音軌資料 [pcm]，可指定起始位移 [offsetSamples]（單位：樣本）。
  void addTrack(String id, Uint8List pcm, {int offsetSamples = 0}) {
    _tracks[id] = _Track(Int16List.view(pcm.buffer), offsetSamples);
    _cache = null;
  }

  /// 移除音軌
  void removeTrack(String id) {
    _tracks.remove(id);
    _cache = null;
  }

  /// 取得混音後的 PCM 資料。
  Uint8List get output {
    _cache ??= _mix();
    return _cache!;
  }

  Uint8List _mix() {
    int length = 0;
    for (final t in _tracks.values) {
      length = math.max(length, t.offset + t.samples.length);
    }
    final mix32 = Int32List(length);
    for (final t in _tracks.values) {
      for (int i = 0; i < t.samples.length; i++) {
        mix32[t.offset + i] += t.samples[i];
      }
    }
    final out16 = Int16List(length);
    for (int i = 0; i < length; i++) {
      int v = mix32[i];
      if (v > 32767) v = 32767;
      if (v < -32768) v = -32768;
      out16[i] = v;
    }
    return Uint8List.view(out16.buffer);
  }
}

class _Track {
  final Int16List samples;
  final int offset;
  _Track(this.samples, this.offset);
}

