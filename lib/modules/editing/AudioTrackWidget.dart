import 'package:flutter/material.dart';

/// 音軌編輯元件：只顯示圖示與操作按鈕，不顯示文字資訊
class AudioTrackWidget extends StatelessWidget {
  final AudioTrack track;
  final VoidCallback onDelete;
  final VoidCallback onPlayPause;
  final bool isPlaying;

  const AudioTrackWidget({
    super.key,
    required this.track,
    required this.onDelete,
    required this.onPlayPause,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          children: [
            const Icon(Icons.music_note),
            const Spacer(),
            IconButton(
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: onPlayPause,
            ),
            IconButton(icon: const Icon(Icons.delete), onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}

/// 支援的音軌資料結構
class AudioTrack {
  final String filePath;
  final String name;
  AudioTrack(this.filePath) : name = filePath.split('/').last;
}
