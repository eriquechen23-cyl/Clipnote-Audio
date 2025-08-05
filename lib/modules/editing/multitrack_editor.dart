import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:clipnote_audio/modules/decoding/ffmpeg_decoder.dart';
import 'package:clipnote_audio/modules/decoding/pcm_player.dart';
import 'package:clipnote_audio/modules/editing/AudioTrackWidget.dart';
import 'package:clipnote_audio/modules/editing/fft.dart';
import 'package:clipnote_audio/modules/file_access/uploader.dart';
import 'package:clipnote_audio/modules/merge_mix/mix_bus.dart';

class SpectrumBar extends StatelessWidget {
  final List<double> spectrum;
  final double height;
  const SpectrumBar({super.key, required this.spectrum, this.height = 60});
  @override
  Widget build(BuildContext context) {
    final maxVal = spectrum.isNotEmpty
        ? spectrum.reduce((a, b) => a > b ? a : b)
        : 0.0;
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: spectrum.map((v) {
          final barHeight = maxVal > 0 ? (v / maxVal) * height : 0.0;
          return Container(
            width: 4,
            height: barHeight,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            color: Colors.blueAccent,
          );
        }).toList(),
      ),
    );
  }
}

class MultiTrackEditor extends StatefulWidget {
  const MultiTrackEditor({super.key});
  @override
  State<MultiTrackEditor> createState() => _MultiTrackEditorState();
}

class _MultiTrackEditorState extends State<MultiTrackEditor> {
  final _uploader = FileUploader();
  final List<AudioTrack> _tracks = [];
  bool _isPlayingAll = false;
  List<double> _mixedSpectrum = [];
  Timer? _mixerTimer;
  MixBus? _mixBus;
  PcmPlayer? _player;

  @override
  void dispose() {
    _player?.dispose();
    _mixerTimer?.cancel();
    super.dispose();
  }

  Future<void> _addTrack() async {
    final paths = await _uploader.pickAudioFiles();
    if (paths.isNotEmpty) {
      final decoder = FFmpegDecoder();
      for (final path in paths) {
        final pcmData = decoder.decode(path);
        _mixBus ??= MixBus(pcmData.sampleRate);
        _mixBus!.addTrack(path, pcmData.buffer);
        _tracks.add(AudioTrack(path));
      }
      await _reloadPlayer();
      _startMixerLoop();
      setState(() {});
    }
  }

  void _startMixerLoop() {
    _mixerTimer?.cancel();
    _mixerTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_mixBus == null || _player == null) return;
      const windowSize = 1024;
      final samples = Int16List.view(_mixBus!.output.buffer);
      if (samples.length < windowSize) return;
      final posMs = _player!.position.inMilliseconds;
      final center = (posMs / 1000 * _mixBus!.sampleRate).toInt();
      final rawStart = center - windowSize ~/ 2;
      final maxStart = samples.length - windowSize;
      final start = math.max(0, math.min(rawStart, maxStart));
      final window =
          samples.sublist(start, start + windowSize).map((s) => s.toDouble()).toList();
      final bins = spectrum500Hz(window, _mixBus!.sampleRate.toDouble());
      setState(() => _mixedSpectrum = bins);
    });
  }

  Future<void> _reloadPlayer() async {
    final data = _mixBus?.output;
    if (data == null) return;
    _player ??= PcmPlayer();
    await _player!.load(data, _mixBus!.sampleRate);
    if (_isPlayingAll) {
      await _player!.play();
    }
  }

  Future<void> _toggleAllPlayPause() async {
    if (_player == null) return;
    _isPlayingAll = !_isPlayingAll;
    _isPlayingAll ? await _player!.play() : await _player!.pause();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          color: Colors.blueGrey[900],
          child: const Center(
            child: Text(
              "多軌編輯器",
              style: TextStyle(fontSize: 24, color: Colors.white),
            ),
          ),
        ),
        // 混音跳動頻譜視覺化
        if (_mixedSpectrum.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 12, right: 12),
            child: SpectrumBar(spectrum: _mixedSpectrum, height: 100),
          ),
        // 音軌列表
        Expanded(
          child: ListView.builder(
            itemCount: _tracks.length,
            itemBuilder: (_, i) {
              final track = _tracks[i];
              return AudioTrackWidget(
                track: track,
                onDelete: () async {
                  _mixBus?.removeTrack(track.filePath);
                  _tracks.removeAt(i);
                  await _reloadPlayer();
                  setState(() {});
                },
              );
            },
          ),
        ),
        // 控制列
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: Icon(_isPlayingAll ? Icons.pause : Icons.play_arrow),
                label: Text(_isPlayingAll ? "暫停所有" : "播放所有"),
                onPressed: _toggleAllPlayPause,
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text("新增音軌"),
                onPressed: _addTrack,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
