import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

/// 傳進 Isolate 的參數（純 Map/基本型）。
/// tracks: List<Map>，每個 track 帶 pcm(TransferableTypedData)、sr、start、srcStart、dur、fadeIn、fadeOut
/// targetSr: 目標取樣率（目前假設都一樣，先不重採樣）
Future<Map<String, dynamic>> renderMixInIsolate(
  Map<String, dynamic> args,
) async {
  return await Isolate.run(() => _renderMix(args));
}

Map<String, dynamic> _renderMix(Map<String, dynamic> args) {
  final List tracks = args['tracks'] as List;
  final int sr = args['targetSr'] as int? ?? 48000;

  // 1) 找出總長（樣本）
  int totalLen = 0;
  final _t = <_T>[];
  for (final t in tracks) {
    final tt = t as Map<String, dynamic>;
    final pcmTTD = tt['pcm'] as TransferableTypedData;
    final u8 = pcmTTD.materialize().asUint8List();
    final samples = Int16List.view(
      u8.buffer,
      u8.offsetInBytes,
      u8.lengthInBytes ~/ 2,
    );

    final start = (tt['start'] as int).clamp(0, 1 << 30);
    final srcStart = (tt['srcStart'] as int).clamp(0, samples.length);
    final dur = (tt['dur'] as int).clamp(0, samples.length - srcStart);
    final fadeIn = math.max(0, tt['fadeIn'] as int);
    final fadeOut = math.max(0, tt['fadeOut'] as int);

    _t.add(_T(samples, start, srcStart, dur, fadeIn, fadeOut));
    totalLen = math.max(totalLen, start + dur);
  }
  if (totalLen <= 0) {
    return {
      'sr': sr,
      'pcm': TransferableTypedData.fromList([Uint8List(0)]),
      'env': <double>[],
    };
  }

  // 2) 混音（32-bit 累加，最後夾回 int16）
  final acc = Int32List(totalLen);
  for (final t in _t) {
    final fadeInEnd = t.fadeIn;
    final fadeOutStart = t.dur - t.fadeOut;
    for (int i = 0; i < t.dur; i++) {
      final srcIdx = t.srcStart + i;
      final dstIdx = t.start + i;
      if (srcIdx < 0 || srcIdx >= t.samples.length || dstIdx >= totalLen)
        continue;

      // 計算淡入/淡出增益（線性）
      double g = 1.0;
      if (t.fadeIn > 0 && i < fadeInEnd) g = i / t.fadeIn;
      if (t.fadeOut > 0 && i > fadeOutStart) {
        final r = (t.dur - i) / t.fadeOut;
        g = math.min(g, r);
      }

      acc[dstIdx] += (t.samples[srcIdx] * g).round();
    }
  }

  // 3) 夾回 int16
  final out = Int16List(totalLen);
  for (int i = 0; i < totalLen; i++) {
    int v = acc[i];
    if (v > 32767) v = 32767;
    if (v < -32768) v = -32768;
    out[i] = v;
  }

  // 4) 預先做 Master 波形包絡（UI 直接畫，不會卡）
  final bars = math.min(1200, math.max(200, totalLen ~/ 400)); // 估一個合理柱數
  final step = totalLen / bars;
  final env = List<double>.filled(bars, 0.0);
  for (int i = 0; i < bars; i++) {
    final a = (i * step).floor();
    final b = ((i + 1) * step).floor().clamp(a + 1, totalLen);
    int m = 0;
    final stride = math.max(1, ((b - a) / 200).floor());
    for (int s = a; s < b; s += stride) {
      final v = out[s].abs();
      if (v > m) m = v;
    }
    env[i] = m / 32768.0;
  }

  final bytes = Uint8List.view(out.buffer);
  return {
    'sr': sr,
    'pcm': TransferableTypedData.fromList([bytes]),
    'env': env,
  };
}

class _T {
  final Int16List samples;
  final int start, srcStart, dur, fadeIn, fadeOut;
  _T(
    this.samples,
    this.start,
    this.srcStart,
    this.dur,
    this.fadeIn,
    this.fadeOut,
  );
}
