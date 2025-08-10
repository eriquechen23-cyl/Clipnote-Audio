// lib/modules/decoding/ffmpeg_decoder.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

class DecodedPcm {
  final Uint8List buffer;
  final int sampleRate;
  const DecodedPcm(this.buffer, this.sampleRate);
}

class FFmpegDecoder {
  /// 轉成 s16le 單聲道。你要雙聲道可把 -ac 改 2
  Future<DecodedPcm> decode(
    String inputPath, {
    int sampleRate = 48000,
    int channels = 1,
  }) async {
    final dir = await getTemporaryDirectory();
    final out = File(
      '${dir.path}/decode_${DateTime.now().millisecondsSinceEpoch}.pcm',
    );
    if (out.existsSync()) await out.delete();
    // 轉檔指令：輸入 -> s16le raw PCM
    final cmd = [
      '-y',
      '-i',
      '"$inputPath"',
      '-vn',
      '-ac',
      '$channels',
      '-ar',
      '$sampleRate',
      '-f',
      's16le',
      '"${out.path}"',
    ].join(' ');

    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      final logs = await session.getOutput();
      throw 'FFmpeg failed ($rc): $logs';
    }

    final bytes = await out.readAsBytes();
    return DecodedPcm(bytes, sampleRate);
  }
}
