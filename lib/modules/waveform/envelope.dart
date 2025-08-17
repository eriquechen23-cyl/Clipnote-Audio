// lib/modules/waveform/envelope.dart
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:math' as math;

class EnvelopeLevel {
  final int sampleRate; // 48000
  final int stepSamples; // 32/64/128/... 對應一個 bucket 有多少 samples
  final Int16List minVals; // 每 bucket 的最小值（-32768..32767）
  final Int16List maxVals; // 每 bucket 的最大值（-32768..32767）

  const EnvelopeLevel({
    required this.sampleRate,
    required this.stepSamples,
    required this.minVals,
    required this.maxVals,
  });

  int get length => minVals.length;
  int get stepMs => (stepSamples * 1000) ~/ sampleRate;
  int indexFromMs(int ms) {
    final idx = ((ms * sampleRate ~/ 1000) ~/ stepSamples);
    return idx.clamp(0, math.max(0, length - 1));
  }

  int msAt(int idx) => ((idx * stepSamples) * 1000) ~/ sampleRate;
}

// ===== Isolate builder =====

class _EnvJob {
  final SendPort reply;
  final Int16List pcm;
  final int sampleRate;
  final int stepSamples;
  _EnvJob(this.reply, this.pcm, this.sampleRate, this.stepSamples);
}

void _envWorker(_EnvJob job) {
  final pcm = job.pcm;
  final step = math.max(1, job.stepSamples);
  final n = (pcm.length + step - 1) ~/ step;

  final minVals = Int16List(n);
  final maxVals = Int16List(n);

  for (int i = 0; i < n; i++) {
    final start = i * step;
    final end = math.min(start + step, pcm.length);
    int mn = 32767;
    int mx = -32768;
    for (int j = start; j < end; j++) {
      final v = pcm[j];
      if (v < mn) mn = v;
      if (v > mx) mx = v;
    }
    minVals[i] = mn;
    maxVals[i] = mx;
  }

  job.reply.send(
    EnvelopeLevel(
      sampleRate: job.sampleRate,
      stepSamples: step,
      minVals: minVals,
      maxVals: maxVals,
    ),
  );
}

Future<EnvelopeLevel> buildEnvelopeLevelIsolate({
  required Int16List pcm,
  required int sampleRate,
  required int stepSamples,
}) async {
  final rp = ReceivePort();
  await Isolate.spawn<_EnvJob>(
    _envWorker,
    _EnvJob(rp.sendPort, pcm, sampleRate, stepSamples),
    errorsAreFatal: true,
  );
  return await rp.first as EnvelopeLevel;
}
