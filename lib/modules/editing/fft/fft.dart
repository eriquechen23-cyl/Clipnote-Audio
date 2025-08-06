import 'dart:math';

/// FFT 尺寸常數
const int fftSize = 64;

/// 複數資料結構
class Complex {
  final double re;
  final double im;
  const Complex(this.re, this.im);

  Complex operator +(Complex other) => Complex(re + other.re, im + other.im);
  Complex operator -(Complex other) => Complex(re - other.re, im - other.re);
  Complex operator *(Complex other) =>
      Complex(re * other.re - im * other.im, re * other.im + im * other.re);

  /// 振幅
  double abs() => sqrt(re * re + im * im);
}

/// Cooley–Tukey FFT 實作 (遞迴版)
List<Complex> fft(List<Complex> x) {
  final n = x.length;
  // FFT 長度必須為 2 的次方，遞迴運算會持續切分
  assert((n & (n - 1)) == 0, 'FFT length must be power of two');
  if (n <= 1) return x;

  // 分離偶數與奇數項
  final even = <Complex>[];
  final odd = <Complex>[];
  for (var i = 0; i < n; i++) {
    (i.isEven ? even : odd).add(x[i]);
  }

  final fftEven = fft(even);
  final fftOdd = fft(odd);

  final result = List<Complex>.filled(n, const Complex(0, 0));
  for (var k = 0; k < n ~/ 2; k++) {
    final theta = -2 * pi * k / n;
    final wk = Complex(cos(theta), sin(theta));
    result[k] = fftEven[k] + (wk * fftOdd[k]);
    result[k + n ~/ 2] = fftEven[k] - (wk * fftOdd[k]);
  }
  return result;
}

/// 計算 FFT 振幅 bins，輸出長度為 fftSize
List<double> getFftBins(List<double> realInput) {
  assert(realInput.length == fftSize, 'Input length must be $fftSize');

  // Hanning 窗函數
  final window = List<double>.generate(
    fftSize,
    (i) => 0.5 - 0.5 * cos(2 * pi * i / (fftSize - 1)),
  );

  // 構建複數輸入
  final input = List<Complex>.generate(
    fftSize,
    (i) => Complex(realInput[i] * window[i], 0),
  );

  // 執行 FFT
  final spectrum = fft(input);

  // 回傳振幅列表
  return spectrum.map((c) => c.abs()).toList();
}
