import 'package:clipnote_audio/modules/services/track_lane_service.dart';
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
  late final TrackLaneService laneSvc; // ★ 新增
  static const double _outerPad = 12;

  // 時間軸縮放（TracksPage 用）
  double _pxPerMs = 0.20;
  double _rightViewportWidthPx = 0; // 由 LayoutBuilder 寫入
  @override
  void initState() {
    super.initState();
    svc = MainEditorService();
    // ignore: discarded_futures
    laneSvc = TrackLaneService(svc); // ★ 綁定 editor
    svc.initAsync();
    _lockLandscape();
  }

  TimelineScale _nearestScale() {
    final vw = _rightViewportWidthPx > 0 ? _rightViewportWidthPx : 1.0;
    final windowMs = (vw / _pxPerMs).round();
    return nearestScaleForWindowMs(windowMs);
  }

  // —— 計算右側「可見編輯區」的寬度（px）——
  // 要跟 TracksPage 的常數同步：_listPadL/_listPadR/_headerW/_gutterW
  double _rightViewportWidth(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    const listPadL = 12.0;
    const listPadR = 12.0;
    const headerW = 280.0;
    const gutterW = 8.0;
    return w - 2 * _outerPad - listPadL - listPadR - headerW - gutterW;
  }

  // 套用縮放（以「可見寬度」換算新的 _pxPerMs）
  // 這個最小版不處理「以播放頭為錨捲動」，先能切再說；在播放中自動追隨會補上視覺位置。
  void _applyScale(TimelineScale s) {
    final vw = _rightViewportWidthPx > 0 ? _rightViewportWidthPx : 1.0;
    final newPxPerMs = vw / s.windowMs;
    if ((newPxPerMs - _pxPerMs).abs() > 1e-6) {
      setState(() => _pxPerMs = newPxPerMs); // ★ 觸發重建
    }
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
                      child: LayoutBuilder(
                        builder: (context, c) {
                          // 左欄固定寬 + 內距要扣掉
                          const headerW = 280.0;
                          const listPadL = 12.0;
                          const listPadR = 12.0;
                          const gutterW = 8.0;

                          final rightW =
                              c.maxWidth -
                              listPadL -
                              listPadR -
                              headerW -
                              gutterW;
                          if ((rightW - _rightViewportWidthPx).abs() > 0.5) {
                            _rightViewportWidthPx = rightW; // ★ 記下真寬
                          }

                          return AnimatedBuilder(
                            animation: svc,
                            builder: (context, _) {
                              return TracksPage(
                                tracks: svc.tracks,
                                onReorder: svc.reorderTracks,
                                onDeleteTrack: (i) => svc.removeTrackAt(i),
                                durationMs: svc.durationMs,
                                onSeekMs: svc.seekTo,
                                canEdit: !svc.isPlaying,
                                editor: svc,
                                pxPerMs: _pxPerMs,
                              );
                            },
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
                        onExport: _handleExport,
                        currentScale: _nearestScale(),
                        onSetScale: _applyScale,
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

  void _handleExport() async {
    final fmt = await _chooseExportFormat(context);
    if (fmt == null) return;

    final bitrate = switch (fmt) {
      AudioExportFormat.mp3 => 192,
      AudioExportFormat.m4a => 192,
      AudioExportFormat.wav => 0,
    };

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final where = await svc.exportMixToDownloads(
        format: fmt,
        bitrateKbps: bitrate,
        suggestFileName: 'clipnote_mix',
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已匯出到下載：$where')));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('匯出失敗：$e')));
    }
  }

  Future<AudioExportFormat?> _chooseExportFormat(BuildContext ctx) {
    return showModalBottomSheet<AudioExportFormat>(
      context: ctx,
      backgroundColor: const Color(0xFF121621),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text(
              '選擇輸出格式',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.audiotrack, color: Colors.white70),
              title: const Text('MP3', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, AudioExportFormat.mp3),
            ),
            ListTile(
              leading: const Icon(Icons.music_note, color: Colors.white70),
              title: const Text(
                'M4A (AAC)',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, AudioExportFormat.m4a),
            ),
            ListTile(
              leading: const Icon(Icons.waves, color: Colors.white70),
              title: const Text(
                'WAV（無壓縮）',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, AudioExportFormat.wav),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
