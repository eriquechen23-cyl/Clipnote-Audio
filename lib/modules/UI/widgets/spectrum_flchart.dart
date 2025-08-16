import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// 以 fl_chart 繪製的頻譜視覺化
/// 傳入 FFT magnitude 或 power 的 bins（線性頻率等距），自動壓縮到 barCount。
class SpectrumFlChart extends StatefulWidget {
  final List<double> bins; // 例如 0..N-1，對應 0..Nyquist
  final int sampleRate; // 用於顯示/轉換（可選）
  final int barCount; // 最終顯示幾根柱子
  final double barWidth; // 視覺寬度
  final double emaAlpha; // 指數平滑 0..1（0.2~0.5 比較穩）
  final bool useLogFreq; // 是否使用對數頻率聚合
  final double floorDb; // dB 轉換時的地板（避免 -inf）
  final EdgeInsets padding; // 內距
  final Gradient? gradient; // 自訂漸層；null 用內建

  const SpectrumFlChart({
    super.key,
    required this.bins,
    required this.sampleRate,
    this.barCount = 64,
    this.barWidth = 6,
    this.emaAlpha = 0.35,
    this.useLogFreq = true,
    this.floorDb = -90.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    this.gradient,
  });

  @override
  State<SpectrumFlChart> createState() => _SpectrumFlChartState();
}

class _SpectrumFlChartState extends State<SpectrumFlChart> {
  late List<double> _ema; // 平滑後的能量
  late List<double> _peaks; // 簡單 peak-hold（可選）
  final double _peakDecay = 0.03; // 每次更新往下掉的比例

  @override
  void initState() {
    super.initState();
    _ema = List.filled(widget.barCount, 0);
    _peaks = List.filled(widget.barCount, 0);
  }

  @override
  void didUpdateWidget(covariant SpectrumFlChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.barCount != widget.barCount) {
      _ema = List.filled(widget.barCount, 0);
      _peaks = List.filled(widget.barCount, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1) 將原始 bins 聚合到 barCount
    final bars = _aggregate(widget.bins, widget.barCount, widget.useLogFreq);

    // 2) 轉 dB（或保持線性），這裡用簡單 dB 轉換
    final db = _toDb(bars, floorDb: widget.floorDb); // 回傳 0..1 的比例值

    // 3) EMA 平滑 + peak hold
    for (int i = 0; i < db.length; i++) {
      _ema[i] = widget.emaAlpha * db[i] + (1 - widget.emaAlpha) * _ema[i];
      if (_ema[i] > _peaks[i]) {
        _peaks[i] = _ema[i];
      } else {
        _peaks[i] = math.max(0, _peaks[i] - _peakDecay);
      }
    }

    final groups = <BarChartGroupData>[];
    for (int i = 0; i < _ema.length; i++) {
      final v = _ema[i].clamp(0.0, 1.0);
      final peak = _peaks[i].clamp(0.0, 1.0);

      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            // 主能量
            BarChartRodData(
              toY: v,
              width: widget.barWidth,
              borderRadius: BorderRadius.circular(4),
              gradient:
                  widget.gradient ??
                  const LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xFF222A3A),
                      Color(0xFF3A6CF6),
                      Color(0xFF22D3EE),
                    ],
                  ),
            ),
            // Peak-hold（細線）
            BarChartRodData(
              toY: peak,
              width: math.max(2, widget.barWidth * 0.25),
              borderRadius: BorderRadius.circular(2),
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF176), Color(0xFFFFD54F)],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
            ),
          ],
          barsSpace: 0,
        ),
      );
    }

    return Padding(
      padding: widget.padding,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceEvenly,
          barGroups: groups,
          maxY: 1.0,
          minY: 0.0,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(enabled: false),
          backgroundColor: Colors.transparent,
        ),
        swapAnimationDuration: const Duration(milliseconds: 80),
        swapAnimationCurve: Curves.linear,
      ),
    );
  }

  // 將線性頻率 bins 壓成 barCount；支援線性或對數頻率聚合
  List<double> _aggregate(List<double> src, int barCount, bool logFreq) {
    final n = src.length;
    if (n == 0 || barCount <= 0) return List.filled(barCount, 0);

    final out = List<double>.filled(barCount, 0);
    if (!logFreq) {
      // 線性等分（每段取最大值，視覺更穩定）
      for (int i = 0; i < barCount; i++) {
        final start = (i * n / barCount).floor();
        final end = (((i + 1) * n / barCount).ceil()).clamp(0, n);
        double m = 0;
        for (int k = start; k < end; k++) {
          final v = src[k].abs();
          if (v > m) m = v;
        }
        out[i] = m;
      }
    } else {
      // 對數頻率：0..1 的對數刻度映射到 0..n-1
      for (int i = 0; i < barCount; i++) {
        final t0 = i / barCount;
        final t1 = (i + 1) / barCount;
        final f0 = _log01(t0);
        final f1 = _log01(t1);
        final start = (f0 * n).floor().clamp(0, n - 1);
        final end = (f1 * n).ceil().clamp(start + 1, n);
        double m = 0;
        for (int k = start; k < end; k++) {
          final v = src[k].abs();
          if (v > m) m = v;
        }
        out[i] = m;
      }
    }
    return out;
  }

  // 對數刻度：0→0、1→1，中間取 log10(1 + 9x)
  double _log01(double x) => math.log(1 + 9 * x) / math.log(10);

  // 轉 dB 並壓到 0..1（floorDb 對應 0，0dB 對應 1）
  List<double> _toDb(List<double> v, {double floorDb = -90.0}) {
    final out = List<double>.filled(v.length, 0);
    for (int i = 0; i < v.length; i++) {
      // 你可改成 20*log10 或 10*log10，依 magnitudes/power 決定
      final db = 20 * math.log(v[i] + 1e-9) / math.ln10; // 避免 -inf
      final norm = ((db - floorDb) / (0 - floorDb)).clamp(0.0, 1.0);
      out[i] = norm;
    }
    return out;
  }
}
