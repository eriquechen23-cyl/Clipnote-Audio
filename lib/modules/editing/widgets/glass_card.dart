import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool useBlur; // 👈 新增
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.useBlur = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x22FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3306B6D4),
            blurRadius: 20,
            spreadRadius: 0,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );

    if (!useBlur)
      return ClipRRect(borderRadius: BorderRadius.circular(16), child: content);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: content,
      ),
    );
  }
}
