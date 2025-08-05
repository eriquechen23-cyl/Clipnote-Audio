//C:\workingset\program\flutter\clipnote_audio\lib\modules\file_access\uploader.dart
import 'package:file_picker/file_picker.dart';

/// 檔案選取模組，支援音樂格式 (mp3 / m4a / wav / aac)。
/// 🇹🇼 由於 Android 11+ 的 Storage Access Framework 可能會隱藏部份副檔名，
/// 改採 FileType.custom 並明確列出副檔名可確保 mp3、m4a 都能被列出。
/// 若使用 Android 13 以上，請在 AndroidManifest.xml 加入：
/// <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
class FileUploader {
  /// 開啟系統檔案選取器並回傳所選音檔的絕對路徑。
  /// 若使用者取消選取，回傳 null。
  Future<List<String>> pickAudioFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'wav', 'aac'],
        allowMultiple: true,
        withData: false,
        dialogTitle: '選擇音檔 (可複選)',
      );
      if (result == null || result.files.isEmpty) return [];
      return result.files.map((f) => f.path!).toList();
    } catch (e) {
      print('Error picking audio files: $e');
      return [];
    }
  }

  /// 選取單一音檔並回傳其路徑。
  /// 如果使用者未選取任何檔案則回傳 null。
  Future<String?> pickAudioFile() async {
    final files = await pickAudioFiles();
    if (files.isEmpty) return null;
    return files.first;
  }
}
