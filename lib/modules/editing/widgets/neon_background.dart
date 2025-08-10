import 'package:flutter/material.dart';

class NeonBackground extends StatelessWidget {
  final Widget child;
  const NeonBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0B1220), Color(0xFF0A0F1C)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        const Positioned(
          top: -60,
          left: -40,
          child: _GlowCircle(color: Color(0x3322D3EE), size: 220),
        ),
        const Positioned(
          bottom: -40,
          right: -20,
          child: _GlowCircle(color: Color(0x3348B0F7), size: 180),
        ),
        child,
      ],
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowCircle({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color, blurRadius: 80, spreadRadius: 60)],
      ),
    );
  }
}
