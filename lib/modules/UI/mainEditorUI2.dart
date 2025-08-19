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
  bool _isScrubbing = false; // Mini bar 拖曳狀態
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

  // （移除未使用的 _rightViewportWidth 計算）

  // 套用縮放（以「可見寬度」換算新的 _pxPerMs）
  // 這個最小版不處理「以播放頭為錨捲動」，先能切再說；在播放中自動追隨會補上視覺位置。
  void _applyScale(TimelineScale s) {
    final vw = _rightViewportWidthPx > 0 ? _rightViewportWidthPx : 1.0;
    // 限制視窗可見時間範圍：最精細 0.05s（50ms），最粗 30m（1800000ms）
    final clampedWindowMs = s.windowMs.clamp(50, 1_800_000);
    final newPxPerMs = vw / clampedWindowMs;
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
                                onSetPxPerMs: (v) => setState(() {
                                  _pxPerMs = v;
                                }),
                                isScrubbing: _isScrubbing,
                                laneSvc: laneSvc,
                                // 交給 TracksPage，內部會根據 _isScrubbing 停用追隨
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
                      animation: Listenable.merge([
                        svc.playing,
                        svc.playhead,
                        laneSvc.selectedSegmentId,
                      ]),
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
                        onScrubStart: () => setState(() => _isScrubbing = true),
                        onScrubEnd: () => setState(() => _isScrubbing = false),
                        onCutAtPlayhead: _handleCutAtPlayhead,
                        onDeleteSelectedSegment:
                            laneSvc.selectedSegmentId.value != null
                            ? _handleDeleteSelectedSegment
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 全域阻擋層：長任務期間顯示 LOADING 並阻止所有操作
          AnimatedBuilder(
            animation: svc.busy,
            builder: (context, _) {
              if (!svc.busy.value) return const SizedBox.shrink();
              return Stack(
                children: [
                  ModalBarrier(
                    dismissible: false,
                    color: Colors.black.withOpacity(0.35),
                  ),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                      decoration: BoxDecoration(
                        color: const Color(0xCC121621),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text(
                            '處理中，請稍候…',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleCutAtPlayhead() async {
    // 只在選到某個 lane 時動作
    final laneId = laneSvc.selectedLaneId.value;
    if (laneId == null) return;
    final idx = int.tryParse(laneId.split('-').last);
    if (idx == null || idx < 0 || idx >= svc.tracks.length) return;
    final track = svc.tracks[idx];

    final ms = svc.playheadMs;
    final seg = track.segmentAtMs(ms);
    if (seg == null) return;

    final res = track.splitSegment(seg, ms);
    if (res == null) return;

    // 立即重建本軌與波形，主混音排程處理（避免卡 UI）
    track.rebuildRenderedNow();
    track.buildDownsampledWaveform(step: 128);
    svc.scheduleRebuild();

    // 選取右段，體感較好
    laneSvc.selectSegment(laneId: laneId, segId: res.right.id);
    if (mounted) setState(() {});
  }

  Future<void> _handleDeleteSelectedSegment() async {
    // 必須選到某個 lane 與 segment
    final laneId = laneSvc.selectedLaneId.value;
    final segId = laneSvc.selectedSegmentId.value;
    if (laneId == null || segId == null) return;

    final idx = int.tryParse(laneId.split('-').last);
    if (idx == null || idx < 0 || idx >= svc.tracks.length) return;
    final track = svc.tracks[idx];

    final segs = track.track.segments;
    final i = segs.indexWhere((s) => s.id == segId);
    if (i < 0) return;
    final seg = segs[i];

    // 刪除該段，刷新本軌與波形，主混音改排程
    track.removeSegment(seg);
    track.rebuildRenderedNow();
    track.buildDownsampledWaveform(step: 128);
    svc.scheduleRebuild();

    // 重新選取鄰近片段（若還有）
    if (segs.isNotEmpty) {
      final nextIdx = (i >= segs.length) ? segs.length - 1 : i;
      laneSvc.selectSegment(laneId: laneId, segId: segs[nextIdx].id);
    } else {
      // 清空該 lane 的段選取
      laneSvc.selectedSegmentId.value = null;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已刪除 1 段')));
    setState(() {});
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

    // 先詢問檔名（不含副檔名）
    final baseName = await _askExportFileName(context, fmt);
    if (baseName == null) return; // 使用者取消

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final where = await svc.exportMixToDownloads(
        format: fmt,
        bitrateKbps: bitrate,
        suggestFileName: baseName,
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

  Future<String?> _askExportFileName(
    BuildContext ctx,
    AudioExportFormat fmt,
  ) async {
    final ctrl = TextEditingController(text: 'clipnote_mix');
    String? result = await showDialog<String>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF121621),
        title: const Text('輸入檔名', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '不要加副檔名（例如：clipnote_mix）',
            hintStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF41D9FF)),
            ),
          ),
          onSubmitted: (v) {
            final cleaned = _sanitizeFileNameBase(_stripExtForFormat(v, fmt));
            if (cleaned.isNotEmpty) Navigator.pop(dCtx, cleaned);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, null),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final cleaned = _sanitizeFileNameBase(
                _stripExtForFormat(ctrl.text, fmt),
              );
              if (cleaned.isEmpty) return;
              Navigator.pop(dCtx, cleaned);
            },
            child: const Text('確定'),
          ),
        ],
      ),
    );
    return result;
  }

  String _stripExtForFormat(String name, AudioExportFormat fmt) {
    var n = name.trim();
    final ext = switch (fmt) {
      AudioExportFormat.mp3 => '.mp3',
      AudioExportFormat.m4a => '.m4a',
      AudioExportFormat.wav => '.wav',
    };
    if (n.toLowerCase().endsWith(ext)) {
      n = n.substring(0, n.length - ext.length);
    }
    return n;
  }

  String _sanitizeFileNameBase(String input) {
    final s = input.trim();
    if (s.isEmpty) return '';
    // 移除不合法字元（跨平台）：\\ / : * ? " < > |
    final forbidden = RegExp(r'[\\/:*?"<>|]');
    final cleaned = s.replaceAll(forbidden, '_');
    // 也避免結尾的點或空白
    return cleaned.replaceAll(RegExp(r'[\s\.]+$'), '');
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
