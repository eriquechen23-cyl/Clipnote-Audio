import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

class PcmPlayer {
  final AudioPlayer _player = AudioPlayer();
  String? _tmpWavPath;

  Future<void> load(Uint8List pcm, int sampleRate, {int channels = 1}) async {
    if (pcm.isEmpty) {
      throw 'Audio source error: PCM is empty';
    }

    final wavBytes = _wrapAsWavS16(pcm, sampleRate, channels: channels);

    final dir = await getTemporaryDirectory();
    final f = File(
      '${dir.path}/mix_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await f.writeAsBytes(wavBytes, flush: true);
    _tmpWavPath = f.path;

    try {
      await _player.setFilePath(_tmpWavPath!);
    } on PlayerException catch (e) {
      // e.code 通常是 "Source error"
      throw 'Audio source error: ${e.code} — ${e.message}';
    } on PlayerInterruptedException catch (e) {
      throw 'Audio interrupted: ${e.message}';
    } catch (e) {
      throw 'Audio load failed: $e';
    }
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();

  Duration get position => _player.position;
  bool get playing => _player.playing;

  Future<void> dispose() async {
    await _player.dispose();
    if (_tmpWavPath != null) {
      // 可選：清掉暫存檔
      try {
        File(_tmpWavPath!).deleteSync();
      } catch (_) {}
    }
  }

  // === Helpers ===
  Uint8List _wrapAsWavS16(Uint8List pcm, int sampleRate, {int channels = 1}) {
    final bits = 16;
    final blockAlign = channels * (bits ~/ 8); // 每樣本 bytes
    final byteRate = sampleRate * blockAlign; // 每秒 bytes
    final dataLen = pcm.length;
    final riffSize = 36 + dataLen;

    final bb = BytesBuilder();

    Uint8List _ascii(String s) =>
        Uint8List.fromList(s.codeUnits.map((c) => math.min(c, 0xFF)).toList());
    Uint8List _u16(int v) {
      final b = ByteData(2)..setUint16(0, v, Endian.little);
      return b.buffer.asUint8List();
    }

    Uint8List _u32(int v) {
      final b = ByteData(4)..setUint32(0, v, Endian.little);
      return b.buffer.asUint8List();
    }

    bb.add(_ascii('RIFF'));
    bb.add(_u32(riffSize));
    bb.add(_ascii('WAVE'));
    bb.add(_ascii('fmt '));
    bb.add(_u32(16)); // Subchunk1Size (PCM)
    bb.add(_u16(1)); // AudioFormat = PCM
    bb.add(_u16(channels)); // NumChannels
    bb.add(_u32(sampleRate)); // SampleRate
    bb.add(_u32(byteRate)); // ByteRate
    bb.add(_u16(blockAlign)); // BlockAlign
    bb.add(_u16(bits)); // BitsPerSample
    bb.add(_ascii('data'));
    bb.add(_u32(dataLen));
    bb.add(pcm);

    return bb.toBytes();
  }
}
