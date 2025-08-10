import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Represents a slice of audio data with optional fade in/out.
/// All units are in *samples*.
@immutable
class AudioSegment {
  /// Start position on the final timeline in samples.
  final int start;

  /// Offset into the source PCM buffer in samples.
  final int sourceStart;

  /// Number of samples included in this segment.
  final int duration;

  /// Fade in length in samples. (clamped to [0, duration])
  final int fadeIn;

  /// Fade out length in samples. (clamped to [0, duration - fadeIn])
  final int fadeOut;

  const AudioSegment({
    required this.start,
    required this.sourceStart,
    required this.duration,
    this.fadeIn = 0,
    this.fadeOut = 0,
  }) : assert(start >= 0),
       assert(sourceStart >= 0),
       assert(duration >= 0),
       assert(fadeIn >= 0),
       assert(fadeOut >= 0);

  /// End positions (exclusive)
  int get end => start + duration;
  int get sourceEnd => sourceStart + duration;

  bool get hasFadeIn => fadeIn > 0;
  bool get hasFadeOut => fadeOut > 0;

  /// Return a copy where fades are clamped to valid ranges.
  AudioSegment clamped() {
    final fi = math.min(fadeIn, duration);
    final fo = math.min(fadeOut, math.max(0, duration - fi));
    return copyWith(fadeIn: fi, fadeOut: fo);
  }

  /// Gain (0..1) at sample index `i` *inside this segment* (0-based).
  /// Use equal-power curve by default to avoid the -3 dB dip.
  double gainAt(int i, {FadeCurve curve = FadeCurve.equalPower}) {
    if (duration <= 0) return 0.0;

    // Fade-in
    if (fadeIn > 0 && i < fadeIn) {
      final t = i / fadeIn; // 0..1
      return curve == FadeCurve.linear ? t : _equalPowerIn(t);
    }

    // Fade-out
    final tail = duration - fadeOut;
    if (fadeOut > 0 && i >= tail) {
      final t = (duration - i) / fadeOut; // 0..1
      return curve == FadeCurve.linear ? t : _equalPowerOut(t);
    }

    // Middle
    return 1.0;
  }

  /// Linear copy-with
  AudioSegment copyWith({
    int? start,
    int? sourceStart,
    int? duration,
    int? fadeIn,
    int? fadeOut,
  }) {
    return AudioSegment(
      start: start ?? this.start,
      sourceStart: sourceStart ?? this.sourceStart,
      duration: duration ?? this.duration,
      fadeIn: fadeIn ?? this.fadeIn,
      fadeOut: fadeOut ?? this.fadeOut,
    );
  }

  /// Serialization helpers (optional but handy)
  Map<String, dynamic> toJson() => {
    'start': start,
    'sourceStart': sourceStart,
    'duration': duration,
    'fadeIn': fadeIn,
    'fadeOut': fadeOut,
  };

  factory AudioSegment.fromJson(Map<String, dynamic> j) => AudioSegment(
    start: j['start'] as int,
    sourceStart: j['sourceStart'] as int,
    duration: j['duration'] as int,
    fadeIn: (j['fadeIn'] as int?) ?? 0,
    fadeOut: (j['fadeOut'] as int?) ?? 0,
  );

  // === Curves ===

  // Equal-power fade-in/out: sin/cos to keep perceived loudness smooth.
  static double _equalPowerIn(double t) {
    // t: 0..1 -> gain: 0..1
    // equal-power pair: in = sin, out = cos
    return math.sin((t * math.pi) / 2.0);
  }

  static double _equalPowerOut(double t) {
    // t: 0..1 -> gain: 0..1
    return math.cos((1.0 - t) * math.pi / 2.0);
  }
}

enum FadeCurve { linear, equalPower }
