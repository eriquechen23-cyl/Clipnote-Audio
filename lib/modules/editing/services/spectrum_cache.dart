import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clipnote_audio/modules/editing/fft/fft.dart'; // fftSize
import 'package:clipnote_audio/modules/editing/fft/fft_util.dart'; // FFTUtil
import 'package:clipnote_audio/modules/merge_mix/mix_bus.dart';

class SpectrumNeighbors {
  final List<double> a; // floor 幀
  final List<double> b; // ceil 幀
  final double t; // 0..1 插值比例
  const SpectrumNeighbors(this.a, this.b, this.t);
  bool get isEmpty => a.isEmpty || b.isEmpty;
}

class SpectrumCache {
  SpectrumCache({this.hopMs = 200, this.maxBars = 96});

  final int hopMs; // 幀距（毫秒）
  final int maxBars; // 壓縮列數上限

  final List<List<double>> _frames = [];

  bool get isReady => _frames.isNotEmpty;
  int get length => _frames.length;

  Future<void> ensureReady(MixBus mixBus) async {
    if (isReady) return;

    final pcm = mixBus.output; // Uint8List, 16-bit LE
    final sr = mixBus.sampleRate;
    final samples = Int16List.view(pcm.buffer);

    final hop = (sr * (hopMs / 1000)).round();
    if (samples.length < fftSize) return;

    for (int start = 0; start + fftSize <= samples.length; start += hop) {
      final window = samples
          .sublist(start, start + fftSize)
          .map((s) => s.toDouble())
          .toList();
      final bins = await FFTUtil.computeSpectrum(samples: window);
      _frames.add(_reduceBars(bins, maxBars));
    }
    if (_frames.isEmpty) {
      // 保底避免後續越界
      _frames.add(List<double>.filled(maxBars, 0));
    }
  }

  /// 取得毫秒位置對應的前後幀與比例
  SpectrumNeighbors neighborsAtMs(int ms) {
    if (_frames.isEmpty) return const SpectrumNeighbors([], [], 0);
    final pos = ms / hopMs;
    final i0 = pos.floor();
    final i1 = i0 + 1;
    final t = (pos - i0).clamp(0, 1);
    final a = _frames[i0.clamp(0, _frames.length - 1)];
    final b = _frames[i1.clamp(0, _frames.length - 1)];
    return SpectrumNeighbors(a, b, t.toDouble());
  }

  void invalidate() => _frames.clear();

  List<double> _reduceBars(List<double> src, int maxBars) {
    if (src.length <= maxBars) return src;
    final f = (src.length / maxBars).ceil();
    final out = <double>[];
    for (int i = 0; i < src.length; i += f) {
      double m = 0;
      for (int j = i; j < math.min(i + f, src.length); j++) {
        if (src[j] > m) m = src[j];
      }
      out.add(m);
    }
    return out;
  }
}
