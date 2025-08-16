import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:clipnote_audio/modules/services/mainEditorService.dart';

// 你的元件
import 'package:clipnote_audio/modules/UI/ui2/ui2_primitives.dart';
import 'package:clipnote_audio/modules/UI/ui2/ui2_pages.dart';
import 'package:clipnote_audio/modules/UI/ui2/ui2_wallpaper.dart';

// 極簡底欄（含匯入 + 短時間軸）
import 'package:clipnote_audio/modules/UI/ui2/ui2_bottom_bar_mini.dart';

class MainEditorUI2 extends StatefulWidget {
  const MainEditorUI2({super.key});
  @override
  State<MainEditorUI2> createState() => _MainEditorUI2State();
}

class _MainEditorUI2State extends State<MainEditorUI2> {
  late final MainEditorService svc;

  static const double _outerPad = 12;

  // 時間軸縮放（TracksPage 用）
  double _pxPerMs = 0.20;

  @override
  void initState() {
    super.initState();
    svc = MainEditorService();
    // ignore: discarded_futures
    svc.initAsync();
    _lockLandscape();
  }

  Future<void> _lockLandscape() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _restoreOrientation() async {
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('lib/assets/bg1.jpg'), context);
  }

  @override
  void dispose() {
    _restoreOrientation();
    svc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width >= size.height;

    return Scaffold(
      backgroundColor: const Color(0xFF070A0F),
      body: Stack(
        children: [
          // 背景
          AppWallpaper(
            asset: 'lib/assets/bg1.jpg',
            saturation: 0.0,
            blur: 14,
            darken: 0.72,
            tint: const Color(0xFF6EA6FF),
            tintOpacity: 0.06,
            vignette: 0.35,
          ),
          const Opacity(opacity: 0.90, child: NeonGradientBackground()),
          Positioned.fill(
            child: Container(color: const Color(0xFF070A0F).withOpacity(0.40)),
          ),

          if (!isLandscape)
            const Center(
              child: Text('請旋轉為橫向', style: TextStyle(color: Colors.white70)),
            )
          else
            SafeArea(
              bottom: false, // 底欄自己 SafeArea
              child: Column(
                children: [
                  // ===== 只留軌道頁 =====
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: _outerPad,
                      ),
                      child: AnimatedBuilder(
                        animation: svc,
                        builder: (context, _) {
                          return TracksPage(
                            tracks: svc.tracks,
                            onReorder: svc.reorderTracks,
                            onDeleteTrack: (i) => svc.removeTrackAt(i),
                            durationMs: svc.durationMs,
                            onSeekMs: svc.seekTo,
                            // ★ 播放時鎖編輯
                            canEdit: !svc.isPlaying,
                            editor: svc,
                            pxPerMs: _pxPerMs,
                          );
                        },
                      ),
                    ),
                  ),

                  // ===== 極簡底欄：匯入 + 播放 + 短時間軸 + 時間/總長 + 匯出MP3 =====
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _outerPad,
                      8,
                      _outerPad,
                      12,
                    ),
                    child: AnimatedBuilder(
                      animation: Listenable.merge([svc.playing, svc.playhead]),
                      builder: (_, __) => MiniFooterBar(
                        isPlaying: svc.isPlaying,
                        positionMs: svc.playheadMs,
                        durationMs: svc.durationMs,
                        onPlayPause: svc.togglePlay,
                        onSeekMs: (ms) => svc.seekTo(ms),
                        onImport: _handleImport,
                        onExportMp3: _handleExportMp3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleImport() async {
    try {
      await svc.pickAndImportAudio();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('解碼失敗：$e')));
    }
  }

  void _handleExportMp3() {
    // TODO：接 FFmpegKit atrim/concat → mp3
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('匯出 MP3：TODO（FFmpegKit）')));
  }
}
