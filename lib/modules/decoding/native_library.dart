import 'dart:ffi';
import 'dart:io';

DynamicLibrary loadNativeLibrary(String baseName) {
  String ext;
  if (Platform.isAndroid || Platform.isLinux) {
    ext = '.so';
  } else if (Platform.isWindows) {
    ext = '.dll';
  } else if (Platform.isMacOS) {
    ext = '.dylib';
  } else {
    throw UnsupportedError('Unsupported platform');
  }
  final name = 'lib$baseName$ext';
  try {
    return DynamicLibrary.open(name);
  } catch (e) {
    final message =
        'Failed to load native library $name. Ensure it is present for this platform.';
    print(message);
    throw Exception(message);
  }
}
