/// fft.dart - 簡易 FFT 與 100Hz 區間頻譜計算
import 'dart:math';

/// 複數資料結構
class Complex {
  final double re;
  final double im;
  const Complex(this.re, this.im);

  Complex operator +(Complex other) => Complex(re + other.re, im + other.im);
  Complex operator -(Complex other) => Complex(re - other.re, im - other.im);
  Complex operator *(Complex other) =>
      Complex(re * other.re - im * other.im, re * other.im + im * other.re);
  double abs() => sqrt(re * re + im * im);
}

/// Hanning window
List<double> hanningWindow(int N) =>
    List.generate(N, (i) => 0.5 - 0.5 * cos(2 * pi * i / (N - 1)));

/// Cooley–Tukey FFT 實作 (遞迴版)
List<Complex> fft(List<Complex> x) {
  final n = x.length;
  if (n <= 1) return x;
  assert((n & (n - 1)) == 0, 'FFT length must be power of two');
  final even = <Complex>[];
  final odd = <Complex>[];
  for (var i = 0; i < n; i++) {
    if (i.isEven)
      even.add(x[i]);
    else
      odd.add(x[i]);
  }
  final fftEven = fft(even);
  final fftOdd = fft(odd);

  final result = List<Complex>.filled(n, Complex(0, 0));
  for (var k = 0; k < n ~/ 2; k++) {
    final theta = -2 * pi * k / n;
    final wk = Complex(cos(theta), sin(theta));
    result[k] = fftEven[k] + (wk * fftOdd[k]);
    result[k + n ~/ 2] = fftEven[k] - (wk * fftOdd[k]);
  }
  return result;
}

/// 計算以 100Hz 為區間的頻譜能量
List<double> spectrum500Hz(List<double> pcm, double sampleRate) {
  final n = pcm.length;
  assert((n & (n - 1)) == 0, 'PCM length must be power of two');
  // 應用窗函數
  final window = hanningWindow(n);
  final input = List<Complex>.generate(
    n,
    (i) => Complex(pcm[i] * window[i], 0),
  );
  final spectrum = fft(input);
  final half = n ~/ 2;
  final nyquist = sampleRate / 2;
  final binHz = nyquist / half;

  final bins = <double>[];
  const binWidth = 500;
  for (var hzStart = 0; hzStart < nyquist; hzStart += binWidth) {
    var energy = 0.0;
    var count = 0;
    for (var i = 0; i < half; i++) {
      final freq = i * binHz;
      if (freq >= hzStart && freq < hzStart + binWidth) {
        energy += spectrum[i].abs();
        count++;
      }
    }
    // 從區間平均能量並正規化
    final value = count > 0 ? (energy / count) / n : 0.0;
    bins.add(value);
  }
  return bins;
}
