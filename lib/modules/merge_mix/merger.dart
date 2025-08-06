import 'dart:io';

/// 合併模組骨架
class Merger {
  /// 使用 FFmpeg 的 `amix` 將多段音訊合成到單一輸出 [outputPath]。
  ///
  /// 若 FFmpeg 執行失敗，會拋出例外。
  static Future<void> merge(
      List<String> inputPaths, String outputPath) async {
    if (inputPaths.isEmpty) {
      throw ArgumentError('inputPaths cannot be empty');
    }

    // 準備 ffmpeg 參數
    final args = <String>[];
    for (final path in inputPaths) {
      args.addAll(['-i', path]);
    }
    final inputs = inputPaths.length;
    args.addAll([
      '-filter_complex',
      'amix=inputs=$inputs:dropout_transition=0',
      '-c:a',
      'pcm_s16le',
      outputPath,
    ]);

    final result = await Process.run('ffmpeg', args);
    if (result.exitCode != 0) {
      throw ProcessException(
          'ffmpeg', args, result.stderr.toString(), result.exitCode);
    }
  }
}
