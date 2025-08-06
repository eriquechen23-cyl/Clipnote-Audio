import 'package:flutter/foundation.dart';

/// Represents a slice of audio data with optional fade in/out.
@immutable
class AudioSegment {
  /// Start position on the final timeline in samples.
  final int start;

  /// Offset into the source PCM buffer in samples.
  final int sourceStart;

  /// Number of samples included in this segment.
  final int duration;

  /// Fade in length in samples.
  final int fadeIn;

  /// Fade out length in samples.
  final int fadeOut;

  const AudioSegment({
    required this.start,
    required this.sourceStart,
    required this.duration,
    this.fadeIn = 0,
    this.fadeOut = 0,
  });

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
}
