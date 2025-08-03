import 'package:flutter/material.dart';
import 'package:clipnote_audio/modules/editing/multitrack_editor.dart';

void main() {
  runApp(const ClipNoteAudioApp());
}

/// App 根元件：直接把 MultiTrackEditor 當首頁
class ClipNoteAudioApp extends StatelessWidget {
  const ClipNoteAudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ClipNote Audio',
      theme: ThemeData(useMaterial3: true, primarySwatch: Colors.blueGrey),
      home: const MultiTrackEditor(), // ← 直接進編輯器
    );
  }
}
