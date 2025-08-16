import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

/// 滿版桌布：支援去飽和、模糊、色調、暗化、vignette
class AppWallpaper extends StatelessWidget {
  final String asset;
  final double blur; // 高斯模糊
  final double darken; // 0..1 越大越暗
  final double saturation; // 0=灰階 1=原圖
  final Color? tint; // 顏色覆蓋（可為 null）
  final double tintOpacity; // 0..1
  final double vignette; // 0..1 角落壓暗
  final Alignment alignment;

  const AppWallpaper({
    super.key,
    required this.asset,
    this.blur = 8,
    this.darken = 0.55,
    this.saturation = 0.0,
    this.tint,
    this.tintOpacity = 0.08,
    this.vignette = 0.25,
    this.alignment = Alignment.center,
  });

  // saturation matrix
  static List<double> _sat(double s) {
    final inv = 1 - s;
    final r = 0.2126 * inv;
    final g = 0.7152 * inv;
    final b = 0.0722 * inv;
    return <double>[
      r + s,
      g,
      b,
      0,
      0,
      r,
      g + s,
      b,
      0,
      0,
      r,
      g,
      b + s,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColorFiltered(
            colorFilter: ColorFilter.matrix(_sat(saturation)),
            child: Image.asset(asset, fit: BoxFit.cover, alignment: alignment),
          ),
          if (blur > 0)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: const SizedBox.expand(),
            ),
          if (tint != null) Container(color: tint!.withOpacity(tintOpacity)),
          // 線性暗化（上略深、下略淺）
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(darken + 0.10),
                  Colors.black.withOpacity(darken),
                ],
              ),
            ),
          ),
          // vignette 壓角
          if (vignette > 0)
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.1),
                  radius: 1.2,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.35 * vignette),
                  ],
                  stops: const [0.6, 1.0],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
