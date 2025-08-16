// lib/modules/decoding/ffmpeg_decoder.dart
// Clipnote Audio — FFmpegKit 解碼器
//
// 目標：把任何輸入（mp3/m4a/aac/wav…）解到 mono s16le @ 48000 Hz，
// 存成暫存 .pcm，再讀回記憶體轉為 Int16List，回傳給 SingleTrackService。
//
// 需求：
//   pubspec.yaml 已加入：
//     ffmpeg_kit_flutter_new: ^3.1.0
//     path_provider: ^2.1.4
//     path: ^1.9.0
//
// 放置路徑建議：lib/modules/decoding/ffmpeg_decoder.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import 'package:clipnote_audio/modules/services/singleTrackService.dart';

class FfmpegKitDecoder implements PcmDecoder {
  const FfmpegKitDecoder();

  @override
  Future<DecodedAudio> decodeToS16leMono48k(String path) async {
    // 1) 準備暫存輸出
    final tmpDir = await getTemporaryDirectory();
    final outName = _safeBasename(path) + '.s16le.pcm';
    final outPath = p.join(tmpDir.path, outName);

    // 2) 先刪舊檔
    final outFile = File(outPath);
    if (await outFile.exists()) {
      await outFile.delete();
    }

    // 3) FFmpeg 轉檔：強制單聲道、48k、s16le 原始 PCM
    //    -vn 移除影像；-ac 1 單聲道；-ar 48000 採樣率；-f s16le 與 -acodec pcm_s16le
    final cmd = [
      '-y',
      '-i',
      _ffArg(path),
      '-vn',
      '-ac',
      '1',
      '-ar',
      kSampleRate.toString(),
      '-f',
      's16le',
      '-acodec',
      'pcm_s16le',
      _ffArg(outPath),
    ].join(' ');

    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      final logs = (await session.getAllLogs())
          .map((e) => e.getMessage())
          .join('\n');
      throw Exception('FFmpeg 轉檔失敗 (code=${rc?.getValue()}):\n$logs');
    }

    // 4) 讀取 PCM 檔案內容
    final bytes = await outFile.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('PCM 檔為空：$outPath');
    }

    // 5) 嘗試以 ffprobe 取時長（秒）；若失敗就用樣本數推估
    int durationMs = await _probeDurationMs(path);
    durationMs = durationMs > 0
        ? durationMs
        : ((bytes.length ~/ kBytesPerSample) * 1000 ~/ kSampleRate);

    // 6) 轉為 Int16List（小端）
    final pcm = _bytesToInt16LE(bytes);

    return DecodedAudio(pcm, kSampleRate, durationMs);
  }

  // --- helpers ---
  Future<int> _probeDurationMs(String inputPath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(_ffArg(inputPath));
      final info = await session.getMediaInformation();
      if (info == null) return 0;
      final durStr = info.getDuration(); // string seconds e.g. "123.456789"
      if (durStr == null) return 0;
      final sec = double.tryParse(durStr.trim());
      if (sec == null || sec.isNaN) return 0;
      return (sec * 1000).round();
    } catch (_) {
      return 0;
    }
  }

  Int16List _bytesToInt16LE(Uint8List bytes) {
    final bd = bytes.buffer.asByteData();
    final out = Int16List(bytes.length ~/ kBytesPerSample);
    for (int i = 0, j = 0; i < bytes.length; i += 2, j++) {
      out[j] = bd.getInt16(i, Endian.little);
    }
    return out;
  }

  String _safeBasename(String path) {
    final base = p.basenameWithoutExtension(path);
    // 移除不合法字元以避免在某些檔案系統出錯
    return base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  String _ffArg(String s) {
    // 若路徑含空白或特殊字元，包一層引號
    if (s.contains(' ') || s.contains("'")) {
      // 使用單引號包裹，內含單引號時轉義為 '\'' (sh 相容)
      final escaped = s.replaceAll("'", "'\\''");
      return "'" + escaped + "'";
    }
    return s;
  }
}
