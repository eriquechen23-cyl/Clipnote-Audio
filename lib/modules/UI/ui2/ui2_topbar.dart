// lib/modules/UI/ui2/ui2_topbar.dart
import 'package:flutter/material.dart';
import 'ui2_primitives.dart';

class TopBar extends StatelessWidget {
  final VoidCallback onImport, onExport;
  final String statusText;
  const TopBar({
    super.key,
    required this.onImport,
    required this.onExport,
    required this.statusText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          const Expanded(
            child: Glass(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                'ClipNote Audio — Main Editor',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 讓狀態 pill 可縮放，不再撐爆 Row
          Flexible(
            flex: 0,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: StatusPill(text: statusText),
            ),
          ),
          const SizedBox(width: 8),
          // 右側按鈕最多 200px 寬，窄螢幕時自動換行
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200, minWidth: 120),
            child: Glass(
              child: LayoutBuilder(
                builder: (_, c) {
                  return Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      IconBtn(
                        icon: Icons.audio_file_rounded,
                        tooltip: '匯入音訊',
                        onPressed: onImport,
                      ),
                      IconBtn(
                        icon: Icons.ios_share_rounded,
                        tooltip: '輸出（TODO）',
                        onPressed: onExport,
                      ),
                      const IconBtn(
                        icon: Icons.settings_rounded,
                        tooltip: '設定',
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
