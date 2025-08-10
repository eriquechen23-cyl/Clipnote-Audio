// lib/modules/file_access/uploader.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class FileUploader {
  Future<List<String>> pickAudioFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'wav', 'aac'],
        allowMultiple: true,
        withData: true, // 重要：拿不到 path 時，用 bytes/stream
      );
      if (result == null) return [];

      final cacheDir = await getTemporaryDirectory();
      final out = <String>[];

      for (final f in result.files) {
        String? path = f.path;

        if (path == null) {
          // Android 11+ 常見：只有 content URI，沒有實體路徑
          Uint8List? data = f.bytes;
          if (data == null && f.readStream != null) {
            final bb = BytesBuilder();
            await for (final chunk in f.readStream!) {
              bb.add(chunk);
            }
            data = bb.toBytes();
          }
          if (data == null) continue; // 拿不到資料就略過

          final tempPath = p.join(cacheDir.path, f.name);
          await File(tempPath).writeAsBytes(data, flush: true);
          path = tempPath;
        }

        out.add(path);
      }

      return out;
    } catch (e) {
      // 可加上 debugPrint
      return [];
    }
  }

  Future<String?> pickAudioFile() async {
    final files = await pickAudioFiles();
    return files.isEmpty ? null : files.first;
  }
}
