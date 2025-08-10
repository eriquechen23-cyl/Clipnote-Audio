import 'dart:ffi';
import 'dart:io';

/// 只用於你自家的 FFI（如 PcmPlayer）。
/// **禁止** 用來載入 FFmpeg；FFmpeg 請用 ffmpeg_kit_flutter_new。
DynamicLibrary loadNativeLibrary(String baseName) {
  // 防呆：改用 FFmpegKit，別再嘗試載入 libffmpeg.*
  if (baseName.toLowerCase() == 'ffmpeg' ||
      baseName.toLowerCase().startsWith('av')) {
    throw UnsupportedError(
      'Do not load libffmpeg.* directly. Use ffmpeg_kit_flutter_new instead.',
    );
  }

  String ext;
  if (Platform.isWindows) {
    ext = '.dll';
  } else if (Platform.isMacOS) {
    ext = '.dylib';
  } else if (Platform.isAndroid || Platform.isLinux) {
    ext = '.so';
  } else {
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  // 不同平台的命名候選：Windows 通常沒有 lib 前綴
  final candidates = <String>[
    if (Platform.isWindows) '$baseName$ext' else 'lib$baseName$ext',
    if (Platform.isWindows) 'lib$baseName$ext' else '$baseName$ext',
  ];

  final errors = <Object>[];
  for (final name in candidates) {
    try {
      return DynamicLibrary.open(name);
    } catch (e) {
      errors.add(e);
    }
  }
  throw Exception(
    'Failed to load native library for "$baseName". Tried: ${candidates.join(', ')}',
  );
}
