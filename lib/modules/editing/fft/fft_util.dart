// lib/modules/editing/fft_util.dart

import 'dart:async';
import 'fft.dart'; // 提供 fftSize 與 getFftBins
import 'package:audio_waveforms/audio_waveforms.dart';

/// 音訊 FFT 工具：改用 audio_waveforms Plugin
class FFTUtil {
  /// 每個檔案一個 PlayerController
  static final Map<String, PlayerController> _controllers = {};

  /// 緩存 waveform data（長度 = fftSize）
  static final Map<String, List<double>> _waveformCache = {};

  static PlayerController _controllerFor(String filePath) {
    return _controllers.putIfAbsent(filePath, () => PlayerController());
  }

  /// 從 audio_waveforms 取得固定數量的 waveform samples
  /// 目前忽略 position，取得等距抽樣資料
  static Future<List<double>> getSamples({
    required String filePath,
    required Duration position,
  }) async {
    const sampleCount = fftSize;
    final cacheKey = '$filePath#$sampleCount';
    if (_waveformCache.containsKey(cacheKey)) {
      return _waveformCache[cacheKey]!;
    }

    final controller = _controllerFor(filePath);
    // 1) 準備 player 並抽取 waveform，noOfSamples 決定波形長度
    await controller.preparePlayer(
      path: filePath,
      shouldExtractWaveform: true,
      noOfSamples: sampleCount,
    );
    // 2) 取回 waveform data（長度 = sampleCount）
    final data = await controller.extractWaveformData(
      path: filePath,
      noOfSamples: sampleCount,
    );
    // 3) 緩存後回傳
    _waveformCache[cacheKey] = data;
    return data;
  }

  /// 直接取得 FFT 振幅 bins
  /// [filePath] 與 [samples] 至少需提供一種來源
  static Future<List<double>> computeSpectrum({
    String? filePath,
    List<double>? samples,
    Duration position = Duration.zero,
  }) async {
    final data = samples ??
        await getSamples(
          filePath: filePath!,
          position: position,
        );
    return getFftBins(data);
  }
}
