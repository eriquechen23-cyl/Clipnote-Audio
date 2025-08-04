// lib/modules/editing/single_track.dart

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:clipnote_audio/modules/editing/fft/fft.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../file_access/uploader.dart';
import 'fft/fft_util.dart'; // 新的 FFT 實作：包含 fftSize 常數與 getFftBins()

/// 單軌播放與即時頻譜元件
class SingleTrack extends StatefulWidget {
  const SingleTrack({Key? key}) : super(key: key);

  @override
  SingleTrackState createState() => SingleTrackState();
}

/// State 類型公開，方便外部使用 GlobalKey 控制播放
class SingleTrackState extends State<SingleTrack> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _filePath;
  List<double> _spectrumData = List.filled(fftSize, 0);
  Timer? _spectrumTimer;

  @override
  void dispose() {
    _spectrumTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  /// 切換播放 / 暫停
  Future<void> togglePlayPause() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
      _spectrumTimer?.cancel();
    } else {
      if (_filePath == null) {
        await _selectAndPlay();
      } else {
        await _audioPlayer.play();
        _startSpectrum();
      }
    }
    setState(() {});
  }

  Future<void> _selectAndPlay() async {
    final path = await FileUploader().pickAudioFile();
    if (path == null) return;
    _filePath = path;
    await _audioPlayer.setFilePath(path);
    await _audioPlayer.play();
    _startSpectrum();
    setState(() {});
  }

  void _startSpectrum() {
    _spectrumTimer?.cancel();
    _spectrumTimer = Timer.periodic(const Duration(milliseconds: 100), (
      _,
    ) async {
      if (!_audioPlayer.playing || _filePath == null) return;

      // 1) 從檔案讀取 fftSize 長度的 PCM samples
      final samples = await FFTUtil.getSamples(
        filePath: _filePath!,
        position: _audioPlayer.position,
        sampleCount: fftSize,
      );
      // 2) 用新的 FFT 實作計算每個 bin 的振幅
      final bins = getFftBins(samples);

      setState(() {
        _spectrumData = bins;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.music_note),
            title: Text(
              _filePath != null
                  ? _filePath!.split(Platform.pathSeparator).last
                  : '未選擇音檔',
            ),
            trailing: IconButton(
              icon: Icon(_audioPlayer.playing ? Icons.pause : Icons.play_arrow),
              onPressed: togglePlayPause,
            ),
          ),
          // 頻譜視覺化
          SizedBox(
            height: 100,
            child: CustomPaint(
              painter: SpectrumPainter(_spectrumData),
              child: Container(),
            ),
          ),
        ],
      ),
    );
  }
}

/// 頻譜繪製
class SpectrumPainter extends CustomPainter {
  final List<double> spectrum;
  SpectrumPainter(this.spectrum);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final barWidth = size.width / spectrum.length;

    for (var i = 0; i < spectrum.length; i++) {
      // 將振幅映射到畫布高度
      final magnitude = spectrum[i];
      final barHeight = (magnitude / spectrum.reduce(max)) * size.height;
      final x = i * barWidth;

      canvas.drawRect(
        Rect.fromLTWH(x, size.height - barHeight, barWidth - 1, barHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SpectrumPainter old) =>
      !listEquals(old.spectrum, spectrum);
}
