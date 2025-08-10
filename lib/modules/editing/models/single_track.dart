// lib/modules/editing/models/single_track.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:clipnote_audio/modules/editing/audio_track.dart';

enum TrackStatus { idle, decoding, ready, error }

/// 單一音軌（資料 + 狀態）。不做 I/O，只存狀態與資料。
class SingleTrack with ChangeNotifier {
  SingleTrack({
    required this.id,
    required this.bus,
    this.muted = false,
    this.solo = false,
    this.gainDb = 0.0,
    this.status = TrackStatus.ready,
    this.selected = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 先用 filePath 當 id（之後要換 uuid 也可）
  final String id;

  /// 混音所用的底層資料（你原本的 AudioTrack）
  AudioTrack bus;

  // 狀態
  bool muted;
  bool solo;
  double gainDb; // dB；真正作用在 MixBus 時再轉 linear
  bool selected;
  TrackStatus status;
  final DateTime createdAt;

  // 快捷
  String get filePath => bus.filePath;
  String get name => bus.name;
  int get sampleRate => bus.sampleRate;
  Int16List get samples => bus.samples;

  // 操作（會觸發通知）
  void setMuted(bool v) {
    muted = v;
    notifyListeners();
  }

  void setSolo(bool v) {
    solo = v;
    notifyListeners();
  }

  void setGainDb(double v) {
    gainDb = v;
    notifyListeners();
  }

  void setSelected(bool v) {
    selected = v;
    notifyListeners();
  }

  void setStatus(TrackStatus s) {
    status = s;
    notifyListeners();
  }

  /// 當你對 bus 做裁切/淡入淡出後，用新內容替換
  void replaceBus(AudioTrack newBus) {
    bus = newBus;
    notifyListeners();
  }
}
