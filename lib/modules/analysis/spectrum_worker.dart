// lib/modules/analysis/spectrum_worker.dart
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

typedef BinsCallback = void Function(Float32List bins);

class SpectrumWorker {
  SpectrumWorker({required this.onBins, this.numBands = 64})
    : assert(numBands > 0);

  final BinsCallback onBins;
  final int numBands;

  Isolate? _iso;
  SendPort? _send;
  late final ReceivePort _recv = ReceivePort();
  bool _busy = false; // 節流：上一個計算沒回來就跳過

  Future<void> start() async {
    _iso = await Isolate.spawn<_WorkerInit>(
      _entry,
      _WorkerInit(_recv.sendPort, numBands),
      debugName: 'SpectrumWorker',
    );
    // 取得 worker 的 SendPort
    _send = await _recv.first as SendPort;

    // 之後 worker 的回傳都走這個 stream
    _recv.listen((msg) {
      if (msg is TransferableTypedData) {
        final bins = msg.materialize().asFloat32List();
        onBins(bins);
        _busy = false;
      }
    });
  }

  void dispose() {
    _recv.close();
    _iso?.kill(priority: Isolate.immediate);
    _iso = null;
    _send = null;
  }

  /// 丟一個時間窗（Int16List: 2048樣本）給 worker
  /// 會做一次拷貝避免共用記憶體被主執行緒覆寫。
  void postWindow(Int16List window) {
    if (_send == null || _busy) return;
    _busy = true;
    final bytes = Uint8List.fromList(
      window.buffer.asUint8List(0, window.lengthInBytes),
    );
    final ttd = TransferableTypedData.fromList([bytes]);
    _send!.send(ttd);
  }
}

// ===== Worker 端 =====

class _WorkerInit {
  final SendPort mainSend;
  final int bands;
  _WorkerInit(this.mainSend, this.bands);
}

// Isolate 入口：建立自己的 ReceivePort，回傳 SendPort 給主執行緒
void _entry(_WorkerInit init) {
  final rp = ReceivePort();
  init.mainSend.send(rp.sendPort);

  final bands = init.bands;
  rp.listen((msg) {
    if (msg is TransferableTypedData) {
      final bytes = msg.materialize().asUint8List();
      final i16 = Int16List.view(
        bytes.buffer,
        bytes.offsetInBytes,
        bytes.length ~/ 2,
      );
      final bins = _computeGoertzel(i16, bands);
      final ttd = TransferableTypedData.fromList([Uint8List.view(bins.buffer)]);
      init.mainSend.send(ttd);
    }
  });
}

/// 用 Goertzel 算出 [bands] 個頻帶能量（0..1），輸出 Float32List
Float32List _computeGoertzel(Int16List samples, int bands) {
  final N = samples.length; // 例如 2048
  final nyquistBin = N ~/ 2; // 有效頻域 0..Nyquist
  final out = Float32List(bands);

  // Hann window & normalize 轉 [-1,1]
  final scale = 1.0 / 32768.0;
  // 頻帶中心（線性取樣；想做對數可自行改成 log mapping）
  for (int b = 0; b < bands; b++) {
    final k = (1 + (b * (nyquistBin - 1) / bands)).round(); // 避免 DC
    final w = 2.0 * math.pi * k / N;
    final coeff = 2.0 * math.cos(w);

    double s0 = 0, s1 = 0, s2 = 0;
    for (int n = 0; n < N; n++) {
      final x = samples[n] * scale;
      final win = 0.5 * (1 - math.cos(2 * math.pi * n / (N - 1))); // Hann
      final xn = x * win;

      s0 = xn + coeff * s1 - s2;
      s2 = s1;
      s1 = s0;
    }
    final real = s1 - s2 * math.cos(w);
    final imag = s2 * math.sin(w);
    final mag = math.sqrt(real * real + imag * imag) / (N * 0.5); // 簡單正規化

    // 轉 dB 再壓到 0..1
    final db = 20 * math.log(mag + 1e-9) / math.ln10; // ln→log10
    const floorDb = -80.0;
    final norm = ((db - floorDb) / (-floorDb)).clamp(0.0, 1.0);
    out[b] = norm.toDouble();
  }
  return out;
}
