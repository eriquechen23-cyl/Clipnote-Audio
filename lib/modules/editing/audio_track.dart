import 'dart:math' as math;
import 'dart:typed_data';
import 'segment.dart';

/// 純資料：PCM + 片段描述（狀態如 mute/solo/gain 放在 SingleTrack）
/// - filePath 作為此音軌的識別（TrackService/MixBus 會用它來對應）
/// - segments 預設一段覆蓋整首
class AudioTrack {
  final String filePath;
  final String name;
  final Int16List samples; // 16-bit PCM mono
  final int sampleRate; // ex: 48000
  final List<AudioSegment> segments;

  /// 若未提供 segments，預設為一段覆蓋整首
  AudioTrack(
    this.filePath,
    this.samples,
    this.sampleRate, {
    List<AudioSegment>? segments,
  }) : name = _basename(filePath),
       segments = _initSegments(segments, samples.length);

  /// 複製產生新 AudioTrack（常用於裁切/重算後回寫）
  AudioTrack copyWith({
    String? filePath,
    Int16List? samples,
    int? sampleRate,
    List<AudioSegment>? segments,
  }) {
    final newSamples = samples ?? this.samples;
    return AudioTrack(
      filePath ?? this.filePath,
      newSamples,
      sampleRate ?? this.sampleRate,
      segments: segments ?? this.segments,
    );
  }

  /// 樣本數（整首）
  int get totalSamples => samples.length;

  /// 秒數（整首）
  double get durationSeconds =>
      sampleRate > 0 ? samples.length / sampleRate : 0.0;

  /// 以目前 segments 計算「最後覆蓋到的終點樣本索引」
  int get coveredSamples {
    if (segments.isEmpty) return 0;
    final last = segments.reduce(
      (a, b) => (a.start + a.duration) >= (b.start + b.duration) ? a : b,
    );
    return last.start + last.duration;
  }

  /// 重新指定片段（會自動夾限避免越界）
  AudioTrack withSegments(List<AudioSegment> newSegments) {
    return copyWith(segments: _clampedSegments(newSegments, samples.length));
  }

  /// =============== 私有工具 ===============

  static String _basename(String path) {
    final slash = path.lastIndexOf('/');
    final back = path.lastIndexOf('\\');
    final cut = slash > back ? slash : back;
    return (cut >= 0 && cut < path.length - 1) ? path.substring(cut + 1) : path;
    // 你原本是 path.split('/').last；這裡多照顧 Windows 路徑
  }

  static List<AudioSegment> _initSegments(List<AudioSegment>? segs, int total) {
    final s = segs ?? [AudioSegment(start: 0, sourceStart: 0, duration: total)];
    return _clampedSegments(s, total);
  }

  // audio_track.dart 裡的 _clampedSegments(...) 內：
  static List<AudioSegment> _clampedSegments(
    List<AudioSegment> segs,
    int total,
  ) {
    return segs
        .map((e) {
          final s = e.start.clamp(0, total);
          final src = e.sourceStart.clamp(0, total);
          final maxDur = total - s;
          final d = e.duration.clamp(0, maxDur);

          // clamp fades
          final fi = math.min(e.fadeIn, d);
          final fo = math.min(e.fadeOut, math.max(0, d - fi));

          return e.copyWith(
            start: s,
            sourceStart: src,
            duration: d,
            fadeIn: fi,
            fadeOut: fo,
          );
        })
        .toList(growable: true);
  }
}
