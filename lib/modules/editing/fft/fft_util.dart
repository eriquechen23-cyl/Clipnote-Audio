// lib/modules/editing/fft_util.dart

import 'dart:async';
import 'fft.dart'; // 你的 getFftBins, fftSize
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
  /// 這裡不再使用 position（全檔案等距取樣），若要精細定位可再 slice
  static Future<List<double>> getSamples({
    required String filePath,
    required Duration position, // 目前未使用，可保留呼叫相容性
    required int sampleCount, // 通常等於 fftSize
  }) async {
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
  static Future<List<double>> computeSpectrum({
    required String filePath,
    required Duration position,
    required int sampleCount,
  }) async {
    final samples = await getSamples(
      filePath: filePath,
      position: position,
      sampleCount: sampleCount,
    );
    // 將 waveform samples（已經是振幅或歸一化值）丟進頻譜計算
    return getFftBins(samples);
  }
}
