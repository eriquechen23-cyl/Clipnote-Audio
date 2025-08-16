import 'package:flutter/material.dart';
import 'ui2_primitives.dart';

class LeftDock extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  const LeftDock({super.key, this.currentIndex = 3, required this.onSelect});
  // 每個按鈕 onTap: () => onSelect(索引)
  @override
  Widget build(BuildContext context) {
    return const Glass(
      width: 52,
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          _DockButton(icon: Icons.music_note_rounded, label: '音訊'),
          _DockButton(icon: Icons.mic_rounded, label: '錄音'),
          _DockButton(icon: Icons.graphic_eq_rounded, label: '效果'),
          _DockButton(icon: Icons.layers_rounded, label: '軌道'),
          Spacer(),
          _DockButton(icon: Icons.help_outline_rounded, label: '說明'),
        ],
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  final IconData icon;
  final String label;
  const _DockButton({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          IconCircle(icon: icon),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.white70)),
        ],
      ),
    );
  }
}
