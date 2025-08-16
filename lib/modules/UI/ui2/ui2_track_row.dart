import 'package:flutter/material.dart';
import 'ui2_primitives.dart';
import 'package:clipnote_audio/modules/services/singleTrackService.dart';
import 'package:clipnote_audio/modules/UI/widgets/waveform.dart';

class TrackRow extends StatelessWidget {
  final int index;
  final SingleTrackService service;
  final VoidCallback onDelete;

  // NEW
  final bool canEdit;

  const TrackRow({
    super.key,
    required this.index,
    required this.service,
    required this.onDelete,
    required this.canEdit,
  });

  @override
  Widget build(BuildContext context) {
    final s = service;
    return SoftCard(
      child: AnimatedBuilder(
        animation: s.track,
        builder: (context, _) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    child: Row(
                      children: [
                        const ChipTag(
                          text: '單軌',
                          icon: Icons.music_note_rounded,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Track ${index + 1}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 波形區：播放時禁止互動
                  Expanded(
                    child: IgnorePointer(
                      ignoring: !canEdit,
                      child: SizedBox(
                        height: 72,
                        child: WaveformPreview(
                          service: s,
                          // 若你的 WaveformPreview 支援手勢 callback，
                          // onDragStart: () => context.read<MainEditorService>().beginInteractiveEdit(),
                          // onDragUpdateMs: (ms, seg) => context.read<MainEditorService>().updateInteractiveDrag(
                          //   track: s, segment: seg, rawMs: ms, excludeId: seg.id?.toString(),
                          // ),
                          // onDragEnd: () => context.read<MainEditorService>().endInteractiveEdit(),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Tooltip(
                          message: s.isMuted ? 'Unmute' : 'Mute',
                          child: IconCircle(
                            icon: s.isMuted
                                ? Icons.volume_off
                                : Icons.volume_up,
                            onTap: () => s.setMute(!s.isMuted),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Tooltip(
                          message: s.isSolo ? 'Unsolo' : 'Solo',
                          child: IconCircle(
                            icon: s.isSolo
                                ? Icons.hearing_disabled
                                : Icons.hearing,
                            onTap: () => s.setSolo(!s.isSolo),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Tooltip(
                          message: '刪除此軌',
                          child: IconCircle(
                            icon: Icons.delete_outline,
                            onTap: onDelete,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Gain 滑桿（-24~+12 dB）
              Row(
                children: [
                  const SizedBox(
                    width: 120,
                    child: Text('Gain', style: TextStyle(fontSize: 11)),
                  ),
                  Expanded(
                    child: Slider(
                      value: s.trackGainDb,
                      min: -24,
                      max: 12,
                      divisions: 36,
                      label: '${s.trackGainDb.toStringAsFixed(1)} dB',
                      onChanged: (v) => s.setTrackGainDb(v),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      '${s.trackGainDb.toStringAsFixed(1)} dB',
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class TrackHeader extends StatelessWidget {
  const TrackHeader({super.key});
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            '軌道 / Track',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Text(
            '波形 / Waveform',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(
          width: 120,
          child: Text(
            '控制 / Controls',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
