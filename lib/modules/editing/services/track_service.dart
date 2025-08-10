// lib/modules/editing/services/track_service.dart
import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:clipnote_audio/modules/decoding/ffmpeg_decoder.dart';
import 'package:clipnote_audio/modules/editing/audio_track.dart';
import 'package:clipnote_audio/modules/merge_mix/mix_bus.dart';
import 'package:clipnote_audio/modules/editing/models/single_track.dart';

/// 管理所有單軌 + 維護 MixBus：新增/刪除/更新/狀態變化。
class TrackService extends ChangeNotifier {
  TrackService._();
  static final TrackService instance = TrackService._();

  final List<SingleTrack> _tracks = [];
  MixBus? _mixBus;

  final StreamController<List<SingleTrack>> _tracksStreamCtl =
      StreamController.broadcast();

  UnmodifiableListView<SingleTrack> get tracks => UnmodifiableListView(_tracks);

  Stream<List<SingleTrack>> get trackStream => _tracksStreamCtl.stream;

  MixBus? get mixBus => _mixBus;
  int? get sampleRate => _mixBus?.sampleRate;
  Uint8List? get masterPcm => _mixBus?.output;

  /// 解碼並加入多個檔案
  Future<List<SingleTrack>> addFiles(
    List<String> paths, {
    int targetSr = 48000,
    int channels = 1,
  }) async {
    if (paths.isEmpty) return const [];

    final decoder = FFmpegDecoder();
    final created = <SingleTrack>[];

    for (final p in paths) {
      try {
        final pcm = await decoder.decode(
          p,
          sampleRate: targetSr,
          channels: channels,
        );
        final samples = Int16List.view(pcm.buffer.buffer);

        final bus = AudioTrack(p, samples, pcm.sampleRate);
        _mixBus ??= MixBus(pcm.sampleRate);
        _mixBus!.addTrack(bus);

        final st = SingleTrack(id: p, bus: bus, status: TrackStatus.ready);

        st.addListener(_onAnyTrackChanged);
        _tracks.add(st);
        created.add(st);
      } catch (e) {
        debugPrint('TrackService.addFiles fail: $p $e');
        final st = SingleTrack(
          id: p,
          bus: AudioTrack(p, Int16List(0), targetSr),
          status: TrackStatus.error,
        );
        _tracks.add(st);
        created.add(st);
      }
    }

    _emit();
    return created;
  }

  /// 用 id 或 filePath 刪除
  Future<void> removeById(String idOrPath) async {
    final idx = _tracks.indexWhere(
      (t) => t.id == idOrPath || t.filePath == idOrPath,
    );
    if (idx < 0) return;

    final st = _tracks.removeAt(idx);
    st.removeListener(_onAnyTrackChanged);

    try {
      _mixBus?.removeTrack(st.filePath);
    } catch (_) {}

    if (_tracks.isEmpty) {
      _mixBus = null;
    }

    _emit();
  }

  /// 更新底層 AudioTrack（裁切/拉桿/淡入淡出後）
  void updateTrackBus(SingleTrack st, AudioTrack newBus) {
    try {
      _mixBus?.updateTrack(newBus);
    } catch (_) {}
    st.replaceBus(newBus);
    _emit();
  }

  // 這三個現在只更新狀態；真正作用到 MixBus 請在 _onAnyTrackChanged 實作
  void toggleMute(SingleTrack st) {
    st.setMuted(!st.muted);
  }

  void toggleSolo(SingleTrack st) {
    st.setSolo(!st.solo);
  }

  void setGainDb(SingleTrack st, double db) {
    st.setGainDb(db);
  }

  // ====== 內部 ======
  void _onAnyTrackChanged() {
    // TODO: 把 mute/solo/gain 反映到 MixBus。
    // 例：若 MixBus 有 setGain(filePath, linear)
    // final soloed = _tracks.any((t) => t.solo);
    // for (final t in _tracks) {
    //   final effectiveMute = soloed ? !t.solo : t.muted;
    //   final linear = effectiveMute ? 0.0 : _dbToLinear(t.gainDb);
    //   _mixBus?.setGain(t.filePath, linear);
    // }
    _emit();
  }

  void _emit() {
    notifyListeners();
    _tracksStreamCtl.add(List.unmodifiable(_tracks));
  }

  double _dbToLinear(double db) =>
      db <= -90 ? 0.0 : (pow(10.0, db / 20.0) as double);

  @override
  void dispose() {
    for (final t in _tracks) {
      t.removeListener(_onAnyTrackChanged);
    }
    _tracksStreamCtl.close();
    super.dispose();
  }
}
