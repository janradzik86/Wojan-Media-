import 'dart:math' as math;
import 'dart:typed_data';

/// In-place iterative radix-2 FFT (Cooley–Tukey). [re] and [im] must have a
/// power-of-two length.
class FFT {
  final int n;
  final Float64List _cos, _sin;
  final Int32List _rev;
  final Float64List window;

  FFT(this.n)
      : _cos = Float64List(n ~/ 2),
        _sin = Float64List(n ~/ 2),
        _rev = Int32List(n),
        window = Float64List(n) {
    if (n & (n - 1) != 0) throw ArgumentError('FFT size must be power of two');
    for (var i = 0; i < n ~/ 2; i++) {
      _cos[i] = math.cos(-2 * math.pi * i / n);
      _sin[i] = math.sin(-2 * math.pi * i / n);
    }
    final bits = (math.log(n) / math.ln2).round();
    for (var i = 0; i < n; i++) {
      var r = 0, x = i;
      for (var b = 0; b < bits; b++) {
        r = (r << 1) | (x & 1);
        x >>= 1;
      }
      _rev[i] = r;
    }
    for (var i = 0; i < n; i++) {
      window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1)); // Hann
    }
  }

  void transform(Float64List re, Float64List im) {
    for (var i = 0; i < n; i++) {
      final j = _rev[i];
      if (j > i) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var size = 2; size <= n; size <<= 1) {
      final half = size >> 1;
      final step = n ~/ size;
      for (var i = 0; i < n; i += size) {
        for (var j = 0, k = 0; j < half; j++, k += step) {
          final l = i + j + half;
          final tre = re[l] * _cos[k] - im[l] * _sin[k];
          final tim = re[l] * _sin[k] + im[l] * _cos[k];
          re[l] = re[i + j] - tre;
          im[l] = im[i + j] - tim;
          re[i + j] += tre;
          im[i + j] += tim;
        }
      }
    }
  }

  /// Magnitude spectrum (n/2 bins) of a windowed frame starting at [offset].
  Float64List magnitudes(Float32List samples, int offset, [Float64List? out]) {
    final re = Float64List(n), im = Float64List(n);
    for (var i = 0; i < n; i++) {
      final idx = offset + i;
      re[i] = (idx >= 0 && idx < samples.length ? samples[idx] : 0) * window[i];
    }
    transform(re, im);
    final m = out ?? Float64List(n ~/ 2);
    for (var i = 0; i < n ~/ 2; i++) {
      m[i] = math.sqrt(re[i] * re[i] + im[i] * im[i]) * 2 / n;
    }
    return m;
  }
}
