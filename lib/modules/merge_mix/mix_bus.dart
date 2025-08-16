// lib/modules/merge_mix/mix_bus.dart
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // compute, TransferableTypedData

class MixResult {
  final Uint8List pcmS16; // mono s16le
  final int sampleRate; // Hz
  final int durationMs; // ms
  MixResult(this.pcmS16, this.sampleRate, this.durationMs);
}

double _dbToLinear(double db) => math.pow(10.0, db / 20.0).toDouble();

// --- 可切換的 soft-clip（預設快版；要更「音樂」可改） ---
const bool _kUseFastClip = true;
double _softClip(double x) {
  if (_kUseFastClip) {
    // fast soft-clip: y = x / (1 + |x|)
    return (x / (1.0 + x.abs())).clamp(-1.0, 1.0);
  }
  // 數值穩定的 tanh 版本（較貴）
  if (x > 10) return 1.0;
  if (x < -10) return -1.0;
  final e2x = math.exp(2.0 * x);
  return ((e2x - 1.0) / (e2x + 1.0)).clamp(-1.0, 1.0);
}

class MixBus {
  /// 同步混音（在目前 isolate 跑）
  static MixResult mix({
    required List<Uint8List> tracksS16,
    required List<double> gainsDb,
    required List<bool> mutes,
    required List<bool> solos,
    required int sampleRate,
  }) {
    if (tracksS16.isEmpty) return MixResult(Uint8List(0), sampleRate, 0);

    // solo 只混被標記的軌；否則混非 mute 的軌
    final anySolo = solos.any((s) => s);
    final active = <int>[];
    for (var i = 0; i < tracksS16.length; i++) {
      if (anySolo ? solos[i] : !mutes[i]) active.add(i);
    }
    if (active.isEmpty) return MixResult(Uint8List(0), sampleRate, 0);

    // 目標長度用最長的那條
    var maxBytes = 0;
    for (final i in active) {
      maxBytes = math.max(maxBytes, tracksS16[i].length);
    }
    final maxSamples = maxBytes >> 1;

    // 浮點累加
    final floats = Float32List(maxSamples);
    for (final i in active) {
      final g = _dbToLinear(gainsDb[i]);
      final src = tracksS16[i];
      final view = ByteData.sublistView(src);
      var s = 0;
      for (; s < maxSamples; s++) {
        final idx = s << 1;
        if (idx + 1 >= src.length) break;
        final sample = view.getInt16(idx, Endian.little) / 32768.0;
        floats[s] += (sample * g);
      }
      // 其餘尾端保持 0
    }

    // soft-clip + 轉回 s16
    final out = Uint8List(maxSamples << 1);
    final outView = ByteData.sublistView(out);
    for (var s = 0; s < maxSamples; s++) {
      final y = _softClip(floats[s]);
      outView.setInt16(s << 1, (y * 32767.0).round(), Endian.little);
    }

    final durationMs = ((maxSamples / sampleRate) * 1000).round();
    return MixResult(out, sampleRate, durationMs);
  }

  /// 背景混音（compute 在背景 isolate 跑；輸入/輸出皆用 TTD 避免拷貝）
  static Future<MixResult> mixAsync({
    required List<Uint8List> tracksS16,
    required List<double> gainsDb,
    required List<bool> mutes,
    required List<bool> solos,
    required int sampleRate,
  }) async {
    // 將輸入也轉成 TransferableTypedData，避免跨 isolate 大拷貝
    final ttdInputs = tracksS16
        .map((b) => TransferableTypedData.fromList([b]))
        .toList(growable: false);

    final map = await compute<_MixReqTTD, Map<String, Object?>>(
      _mixEntryTTD,
      _MixReqTTD(ttdInputs, gainsDb, mutes, solos, sampleRate),
    );

    final ttd = map['pcm'] as TransferableTypedData;
    final bytes = ttd.materialize().asUint8List();
    final sr = map['sr'] as int;
    final dur = map['dur'] as int;
    return MixResult(bytes, sr, dur);
  }
}

// ====== compute 所需：請求物件 + 頂層函式（TTD 版本） ======

class _MixReqTTD {
  final List<TransferableTypedData> tracksS16; // 以 TTD 傳遞
  final List<double> gainsDb;
  final List<bool> mutes;
  final List<bool> solos;
  final int sampleRate;
  const _MixReqTTD(
    this.tracksS16,
    this.gainsDb,
    this.mutes,
    this.solos,
    this.sampleRate,
  );
}

// 注意：compute 的入口必須是「頂層函式」
Map<String, Object?> _mixEntryTTD(_MixReqTTD r) {
  // materialize 輸入
  final bytesList = <Uint8List>[];
  for (final ttd in r.tracksS16) {
    bytesList.add(ttd.materialize().asUint8List());
  }

  final res = MixBus.mix(
    tracksS16: bytesList,
    gainsDb: r.gainsDb,
    mutes: r.mutes,
    solos: r.solos,
    sampleRate: r.sampleRate,
  );

  // 用 TransferableTypedData 回傳，避免拷貝
  final ttdOut = TransferableTypedData.fromList([res.pcmS16]);
  return {'pcm': ttdOut, 'sr': res.sampleRate, 'dur': res.durationMs};
}
