import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:clipnote_audio/modules/decoding/ffmpeg_decoder.dart';
import 'package:clipnote_audio/modules/decoding/pcm_player.dart';
import 'package:clipnote_audio/modules/editing/AudioTrackWidget.dart';
import 'package:clipnote_audio/modules/editing/fft.dart';
import 'package:clipnote_audio/modules/file_access/uploader.dart';

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
  final Map<String, List<double>> _pcmData = {};
  final Map<String, PcmPlayer> _players = {};
  final List<AudioTrack> _tracks = [];
  bool _isPlayingAll = false;
  List<double> _mixedSpectrum = [];
  Timer? _mixerTimer;

  @override
  void dispose() {
    for (var player in _players.values) {
      player.dispose();
    }
    _mixerTimer?.cancel();
    super.dispose();
  }

  Future<void> _addTrack() async {
    final paths = await _uploader.pickAudioFiles();
    if (paths.isNotEmpty) {
      final decoder = FFmpegDecoder();
      for (final path in paths) {
        final pcmData = decoder.decode(path);
        final player = PcmPlayer();
        await player.load(pcmData.buffer, pcmData.sampleRate);

        final samples = Int16List.view(pcmData.buffer.buffer)
            .map((s) => s.toDouble())
            .toList();
        _pcmData[path] = samples;
        _players[path] = player;
        _tracks.add(AudioTrack(path));
      }
      _startMixerLoop();
      setState(() {});
    }
  }

  void _startMixerLoop() {
    _mixerTimer?.cancel();
    _mixerTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      const sampleRate = 44100;
      const windowSize = 1024;

      List<double> mixed = List.filled(windowSize, 0.0);
      for (final track in _tracks) {
        final pcm = _pcmData[track.filePath];
        final player = _players[track.filePath];
        if (pcm == null || player == null) continue;
        if (pcm.length < windowSize) continue;

        final posMs = player.position.inMilliseconds;
        final center = (posMs / 1000 * sampleRate).toInt();
        final rawStart = center - windowSize ~/ 2;
        final maxStart = pcm.length - windowSize;
        final start = math.max(0, math.min(rawStart, maxStart)).toInt();
        final window = pcm.sublist(start, start + windowSize);

        for (int i = 0; i < window.length; i++) {
          mixed[i] += window[i];
        }
      }

      final bins = spectrum500Hz(mixed, 44100.0);
      setState(() => _mixedSpectrum = bins);
    });
  }

  Future<void> _toggleAllPlayPause() async {
    _isPlayingAll = !_isPlayingAll;
    for (final player in _players.values) {
      _isPlayingAll ? await player.play() : await player.pause();
    }
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
              final player = _players[track.filePath]!;
              return AudioTrackWidget(
                track: track,
                isPlaying: player.playing,
                onPlayPause: () async {
                  player.playing ? await player.pause() : await player.play();
                  setState(() {});
                },
                onDelete: () async {
                  await player.dispose();
                  _pcmData.remove(track.filePath);
                  _players.remove(track.filePath);
                  _tracks.removeAt(i);
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
