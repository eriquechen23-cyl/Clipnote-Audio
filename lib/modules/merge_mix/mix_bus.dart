import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clipnote_audio/modules/editing/audio_track.dart';
import 'package:clipnote_audio/modules/editing/segment.dart';

/// MixBus 接受多條 PCM 音軌，依時間軸與淡入淡出設定混音。
class MixBus {
  final int sampleRate;
  final Map<String, _Track> _tracks = {};
  Uint8List? _cache;

  MixBus(this.sampleRate);

  void addTrack(AudioTrack track) {
    _tracks[track.filePath] =
        _Track(track.samples, List<AudioSegment>.from(track.segments));
    _cache = null;
  }

  void updateTrack(AudioTrack track) {
    final t = _tracks[track.filePath];
    if (t != null) {
      t.segments = List<AudioSegment>.from(track.segments);
      _cache = null;
    }
  }

  void removeTrack(String id) {
    _tracks.remove(id);
    _cache = null;
  }

  Uint8List get output {
    _cache ??= _mix();
    return _cache!;
  }

  Uint8List _mix() {
    int length = 0;
    for (final t in _tracks.values) {
      for (final seg in t.segments) {
        length = math.max(length, seg.start + seg.duration);
      }
    }
    final mix32 = Int32List(length);
    for (final t in _tracks.values) {
      for (final seg in t.segments) {
        final maxDur = math.min(seg.duration,
            t.samples.length - seg.sourceStart);
        for (int i = 0; i < maxDur; i++) {
          double sample = t.samples[seg.sourceStart + i].toDouble();
          if (seg.fadeIn > 0 && i < seg.fadeIn) {
            sample *= i / seg.fadeIn;
          } else if (seg.fadeOut > 0 && i >= seg.duration - seg.fadeOut) {
            sample *= (seg.duration - i) / seg.fadeOut;
          }
          mix32[seg.start + i] += sample.toInt();
        }
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
  List<AudioSegment> segments;
  _Track(this.samples, this.segments);
}
