// lib/modules/editing/multitrack_editor.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'package:clipnote_audio/modules/editing/AudioTrackWidget.dart';
import 'package:clipnote_audio/modules/editing/models/single_track.dart';
import 'package:clipnote_audio/modules/editing/services/track_service.dart';
import 'package:clipnote_audio/modules/editing/services/spectrum_cache.dart';
import 'package:clipnote_audio/modules/editing/widgets/glass_card.dart';
import 'package:clipnote_audio/modules/editing/widgets/neon_background.dart';
import 'package:clipnote_audio/modules/editing/widgets/spectrum_bar.dart';
import 'package:clipnote_audio/modules/editing/widgets/status_pill.dart';
import 'package:clipnote_audio/modules/editing/widgets/timeline/timeline_seekbar.dart';
import 'package:clipnote_audio/modules/file_access/uploader.dart';
import 'package:clipnote_audio/modules/playback/playback_service.dart';

class MultiTrackEditor extends StatefulWidget {
  const MultiTrackEditor({super.key});
  @override
  State<MultiTrackEditor> createState() => _MultiTrackEditorState();
}

class _MultiTrackEditorState extends State<MultiTrackEditor> {
  final _uploader = FileUploader();
  final TrackService _svc = TrackService.instance;

  List<SingleTrack> get _tracks => _svc.tracks;
  get _mixBus => _svc.mixBus;

  final SpectrumCache _specCache = SpectrumCache(hopMs: 200, maxBars: 96);

  List<double> _currentSpectrum = const [];
  List<double> _blendScratch = const [];
  List<double>? _emaPrev;
  static const double _emaKeep = 0.85;

  bool _isPlayingAll = false;
  bool _isTogglingPlay = false;
  int _playEpoch = 0;

  Timer? _positionTimer;
  final PlaybackService _pb = PlaybackService.instance;

  final ValueNotifier<int> _posMs = ValueNotifier<int>(0);
  int _durationMs = 0;

  @override
  void initState() {
    super.initState();
    _warmSpectra();
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _pb.stopAndRelease();
    _posMs.dispose();
    super.dispose();
  }

  Future<void> _addTrack() async {
    try {
      final paths = await _uploader.pickAudioFiles();
      if (!mounted) return;
      if (paths.isEmpty) {
        _toast('沒有選到可用的音檔');
        return;
      }
      _showLoading();
      await _svc.addFiles(paths);
      _specCache.invalidate();
      await _reloadPlayer();
      setState(() {});
      unawaited(_warmSpectra());
    } catch (e, st) {
      debugPrint('addTrack overall error: $e\n$st');
      if (!mounted) return;
      _toast('新增音軌失敗：$e');
    } finally {
      _hideLoading();
    }
  }

  Future<void> _reloadPlayer() async {
    final data = _svc.masterPcm;
    final sr = _svc.sampleRate ?? (_mixBus?.sampleRate);
    debugPrint('[Editor] reloadPlayer pcmBytes=${data?.length ?? 0}, sr=$sr');

    if (data == null || data.isEmpty || sr == null || sr <= 0) {
      debugPrint('[Editor] reloadPlayer skipped: invalid pcm/sr');
      return;
    }

    await _pb.load(data, sr);
    final samples = _svc.masterPcm!.length ~/ 2; // 16-bit mono
    _durationMs = (samples * 1000) ~/ sr; // integer milliseconds
    _posMs.value = 0; // reset head
    await _warmSpectra();
  }

  Future<void> _warmSpectra() async {
    if (_mixBus == null) return;
    try {
      await _specCache.ensureReady(_mixBus!);
      final first = _specCache.neighborsAtMs(0);
      if (!first.isEmpty) {
        final bars = first.a.length;
        _blendScratch = List<double>.filled(bars, 0.0, growable: false);
        _emaPrev = List<double>.filled(bars, 0.0, growable: false);
        if (mounted && _currentSpectrum.isEmpty) {
          setState(() {
            _currentSpectrum = List<double>.filled(bars, 0.0, growable: false);
          });
        }
      }
    } catch (_) {}
  }

  void _seedHeadFromCacheOrZero() {
    final first = _specCache.neighborsAtMs(0);
    if (!first.isEmpty) {
      final bars = first.a.length;
      _blendScratch = List<double>.filled(bars, 0.0, growable: false);
      _emaPrev = List<double>.filled(bars, 0.0, growable: false);
      setState(() {
        _currentSpectrum = List<double>.from(first.a, growable: false);
      });
    } else {
      const bars = 96;
      _blendScratch = List<double>.filled(bars, 0.0, growable: false);
      _emaPrev = List<double>.filled(bars, 0.0, growable: false);
      setState(() {
        _currentSpectrum = List<double>.filled(bars, 0.0, growable: false);
      });
    }
  }

  void _startSpectrumTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted) return;

      final posMs = _pb.playheadMs;
      _posMs.value = posMs; // tick the listenable every ~33ms
      var nb = _specCache.neighborsAtMs(posMs);
      if (nb.isEmpty) {
        final lastReadyMs = (_specCache.length > 0)
            ? (_specCache.length - 1) * 200
            : 0;
        nb = _specCache.neighborsAtMs(lastReadyMs);
        if (nb.isEmpty) return;
      }

      final a = nb.a, b = nb.b, t = nb.t;
      final len = (a.length < b.length) ? a.length : b.length;
      if (len == 0) return;

      if (_blendScratch.length != len ||
          _emaPrev == null ||
          _emaPrev!.length != len) {
        _blendScratch = List<double>.filled(len, 0.0, growable: false);
        _emaPrev = List<double>.filled(len, 0.0, growable: false);
      }

      final prev = _emaPrev!;
      for (int i = 0; i < len; i++) {
        final blend = a[i] + (b[i] - a[i]) * t;
        final smooth = prev[i] * _emaKeep + blend * (1 - _emaKeep);
        _blendScratch[i] = smooth;
        prev[i] = smooth;
      }
      setState(() {
        _currentSpectrum = List<double>.of(_blendScratch, growable: false);
      });
    });
  }

  Future<void> _toggleAllPlayPause() async {
    if (_tracks.isEmpty) return;
    final goingToPlay = !_isPlayingAll;

    if (goingToPlay) {
      final my = ++_playEpoch;
      setState(() => _isTogglingPlay = true);
      try {
        // 🔑 只有首次或資料變更後才 load，避免剛播放就清掉播放頭
        if (!_pb.isReady) {
          await _reloadPlayer();
          if (my != _playEpoch) return;
        }
        _seedHeadFromCacheOrZero();
        if (my != _playEpoch) return;
        _startSpectrumTimer();
        if (my != _playEpoch) return;
        unawaited(_specCache.ensureReady(_mixBus!));
        await _pb.play();
        if (my != _playEpoch) return;
        if (mounted) setState(() => _isPlayingAll = true);
      } finally {
        if (mounted) setState(() => _isTogglingPlay = false);
      }
    } else {
      _playEpoch++;
      setState(() => _isTogglingPlay = true);
      try {
        _positionTimer?.cancel();
        await _pb.pause();
        if (mounted) setState(() => _isPlayingAll = false);
      } finally {
        if (mounted) setState(() => _isTogglingPlay = false);
      }
    }
  }

  Future<void> _exportMix() async {
    if (_tracks.isEmpty || _mixBus == null) return;
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: '選擇導出位置',
      fileName: 'mix.wav',
    );
    if (outputPath == null) return;
    try {
      final bytes = _buildWav(_svc.masterPcm!, _svc.sampleRate!);
      await File(outputPath).writeAsBytes(bytes);
      _toast('導出成功');
    } catch (e) {
      _toast('導出失敗: $e');
    }
  }

  List<int> _buildWav(Uint8List pcm, int sampleRate) {
    final byteRate = sampleRate * 2;
    final blockAlign = 2;
    final builder = BytesBuilder();
    builder.add(ascii.encode('RIFF'));
    builder.add(_int32(pcm.length + 36));
    builder.add(ascii.encode('WAVE'));
    builder.add(ascii.encode('fmt '));
    builder.add(_int32(16));
    builder.add(_int16(1));
    builder.add(_int16(1));
    builder.add(_int32(sampleRate));
    builder.add(_int32(byteRate));
    builder.add(_int16(blockAlign));
    builder.add(_int16(16));
    builder.add(ascii.encode('data'));
    builder.add(_int32(pcm.length));
    builder.add(pcm);
    return builder.toBytes();
  }

  Uint8List _int16(int value) {
    final b = ByteData(2);
    b.setInt16(0, value, Endian.little);
    return b.buffer.asUint8List();
  }

  Uint8List _int32(int value) {
    final b = ByteData(4);
    b.setInt32(0, value, Endian.little);
    return b.buffer.asUint8List();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }

  void _hideLoading() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = NeonBackground(
      child: Column(
        children: [
          const SizedBox(height: 64),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: GlassCard(
              useBlur: false,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: Colors.white70),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '合成音軌（Master）',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusPill(
                        text: '${_tracks.length} Tracks',
                        icon: Icons.library_music,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 90,
                    child: _currentSpectrum.isEmpty
                        ? const _EmptySpectrumPlaceholder()
                        : RepaintBoundary(
                            child: SpectrumBar(
                              spectrum: _currentSpectrum,
                              height: 90,
                              gradient: const LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  // 時間軸：依靠 PlaybackService 自動刷新
                  TimelineSeekBar(
                    height: 28,
                    positionMs: _posMs,
                    durationMs: _durationMs,
                    onSeek: (ms) async {
                      await _pb.seekMs(ms);
                      _posMs.value = ms;
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _tracks.isEmpty
                  ? Center(
                      child: FilledButton.icon(
                        onPressed: _addTrack,
                        style: _pillStyle(),
                        icon: const Icon(Icons.file_open),
                        label: const Text('選擇音檔'),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: _tracks.length,
                      itemBuilder: (_, i) {
                        final st = _tracks[i];
                        final track = st.bus;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassCard(
                            padding: const EdgeInsets.all(8),
                            child: AudioTrackWidget(
                              track: track,

                              // Replace ONLY the two callbacks below inside your AudioTrackWidget(...)
                              // Requires you already added:
                              //   final ValueNotifier<int> _posMs = ValueNotifier(0);
                              //   int _durationMs = 0;
                              // and you update _posMs in _startSpectrumTimer() and _reloadPlayer() as shown earlier.
                              onDelete: () async {
                                final wasPlaying = _isPlayingAll;
                                final snapshotEpoch = _playEpoch;
                                final currentMs = _pb.playheadMs;

                                await _svc.removeById(st.id);
                                _specCache.invalidate();

                                if (_tracks.isEmpty) {
                                  _positionTimer?.cancel();
                                  await _pb.stopAndRelease();
                                  setState(() {
                                    _isPlayingAll = false;
                                    _currentSpectrum = const [];
                                    _blendScratch = const [];
                                    _emaPrev = null;
                                    _durationMs = 0; // ⟵ timeline length 0
                                  });
                                  _posMs.value =
                                      0; // ⟵ reset playhead for TimelineSeekBar
                                  return;
                                }

                                _positionTimer?.cancel();
                                await _reloadPlayer(); // ⟵ this will recompute _durationMs and reset _posMs to 0

                                _seedHeadFromCacheOrZero();
                                unawaited(_specCache.ensureReady(_mixBus!));

                                if (wasPlaying && snapshotEpoch == _playEpoch) {
                                  await _pb.seekMs(currentMs);
                                  _posMs.value =
                                      currentMs; // ⟵ keep UI in sync after reload
                                  await _pb.play();
                                  _startSpectrumTimer();
                                  setState(() => _isPlayingAll = true);
                                } else {
                                  final kept = currentMs < 0
                                      ? 0
                                      : (currentMs > _durationMs
                                            ? _durationMs
                                            : currentMs);
                                  _posMs.value =
                                      kept; // ⟵ show the preserved head even if not playing
                                  setState(() => _isPlayingAll = false);
                                }
                              },

                              onChanged: () async {
                                _svc.updateTrackBus(st, track);
                                _specCache.invalidate();

                                final wasPlaying = _isPlayingAll;
                                final snapshotEpoch = _playEpoch;
                                final currentMs = _pb.playheadMs;

                                _positionTimer?.cancel();
                                await _reloadPlayer(); // ⟵ recompute _durationMs and reset _posMs to 0

                                _seedHeadFromCacheOrZero();
                                unawaited(_specCache.ensureReady(_mixBus!));

                                if (wasPlaying && snapshotEpoch == _playEpoch) {
                                  await _pb.seekMs(currentMs);
                                  _posMs.value =
                                      currentMs; // ⟵ sync timeline immediately
                                  await _pb.play();
                                  _startSpectrumTimer();
                                } else {
                                  final kept = currentMs < 0
                                      ? 0
                                      : (currentMs > _durationMs
                                            ? _durationMs
                                            : currentMs);
                                  _posMs.value =
                                      kept; // ⟵ static timeline reflects last known head
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    FilledButton.icon(
                      onPressed: (_tracks.isEmpty || _isTogglingPlay)
                          ? null
                          : _toggleAllPlayPause,
                      style: _pillStyle(),
                      icon: (_isTogglingPlay && !_isPlayingAll)
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _isPlayingAll ? Icons.pause : Icons.play_arrow,
                            ),
                      label: Text(_isPlayingAll ? '暫停所有' : '播放所有'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _addTrack,
                      style: _pillOutline(),
                      icon: const Icon(Icons.add),
                      label: const Text('新增音軌'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _tracks.isEmpty ? null : _exportMix,
                      style: _pillStyle(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF22D3EE), Color(0xFF60A5FA)],
                        ),
                      ),
                      icon: const Icon(Icons.download),
                      label: const Text('導出'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '導出',
            onPressed: _tracks.isEmpty ? null : _exportMix,
            icon: const Icon(Icons.download),
          ),
        ],
      ),
      body: bg,
    );
  }

  // --- Styles ---
  ButtonStyle _pillStyle({LinearGradient? gradient}) {
    final base = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: const StadiumBorder(),
      foregroundColor: Colors.white,
      backgroundColor: const Color(0x1AFFFFFF),
      elevation: 0,
    );
    if (gradient == null) return base;
    return base.merge(
      const ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        overlayColor: WidgetStatePropertyAll(Colors.white12),
        shape: WidgetStatePropertyAll(
          StadiumBorder(side: BorderSide(color: Colors.white30)),
        ),
      ),
    );
  }

  ButtonStyle _pillOutline() {
    return OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: const StadiumBorder(),
      side: const BorderSide(color: Color(0x44FFFFFF)),
      foregroundColor: Colors.white,
    );
  }
}

// 小 placeholder
class _EmptySpectrumPlaceholder extends StatelessWidget {
  const _EmptySpectrumPlaceholder();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('（等待播放以顯示頻譜）', style: TextStyle(color: Colors.white54)),
    );
  }
}
