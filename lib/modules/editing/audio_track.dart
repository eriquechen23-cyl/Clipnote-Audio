import 'dart:typed_data';

import 'segment.dart';

/// Holds PCM samples for a track along with editable segments.
class AudioTrack {
  final String filePath;
  final String name;
  final Int16List samples;
  final int sampleRate;
  List<AudioSegment> segments;

  AudioTrack(this.filePath, this.samples, this.sampleRate)
      : name = filePath.split('/').last,
        segments = [
          AudioSegment(start: 0, sourceStart: 0, duration: samples.length)
        ];
}
