import 'dart:math' as math;
import 'dart:typed_data';

import 'fft.dart';
import 'pcm.dart';

/// Result of local music analysis. All times in seconds.
class AudioAnalysis {
  final double duration;
  final double bpm;
  final double bpmConfidence;
  final List<double> beats;
  final List<double> downbeats;
  final List<double> onsets; // transients
  final double frameRate; // envelope frames per second
  final Float32List rms; // per frame, 0..1
  final Float32List bass; // per frame, normalised 0..1
  final Float32List mid;
  final Float32List high;
  final Float32List onsetEnv; // normalised 0..1
  final double peak; // linear peak 0..1
  final double rmsDb;
  final int clippedSamples;
  final List<double> sectionChanges; // dynamic changes
  final Float32List averageSpectrum; // dB per bin (log-spaced 64 bands)

  AudioAnalysis({
    required this.duration,
    required this.bpm,
    required this.bpmConfidence,
    required this.beats,
    required this.downbeats,
    required this.onsets,
    required this.frameRate,
    required this.rms,
    required this.bass,
    required this.mid,
    required this.high,
    required this.onsetEnv,
    required this.peak,
    required this.rmsDb,
    required this.clippedSamples,
    required this.sectionChanges,
    required this.averageSpectrum,
  });

  double valueAt(Float32List env, double t) {
    final i = (t * frameRate).floor();
    if (i < 0 || env.isEmpty) return 0;
    if (i >= env.length) return env.last;
    return env[i];
  }

  Map<String, dynamic> toJson() => {
        'duration': duration,
        'bpm': bpm,
        'bpmConfidence': bpmConfidence,
        'beats': beats,
        'downbeats': downbeats,
        'onsets': onsets,
        'frameRate': frameRate,
        'peak': peak,
        'rmsDb': rmsDb,
        'clippedSamples': clippedSamples,
        'sectionChanges': sectionChanges,
        'rms': rms.toList(),
        'bass': bass.toList(),
        'mid': mid.toList(),
        'high': high.toList(),
        'onsetEnv': onsetEnv.toList(),
        'averageSpectrum': averageSpectrum.toList(),
      };

  static Float32List _f(Object? v) =>
      Float32List.fromList((v as List? ?? const []).map((e) => (e as num).toDouble()).toList());
  static List<double> _d(Object? v) => (v as List? ?? const []).map((e) => (e as num).toDouble()).toList();

  factory AudioAnalysis.fromJson(Map<String, dynamic> j) => AudioAnalysis(
        duration: (j['duration'] as num).toDouble(),
        bpm: (j['bpm'] as num).toDouble(),
        bpmConfidence: (j['bpmConfidence'] as num? ?? 0).toDouble(),
        beats: _d(j['beats']),
        downbeats: _d(j['downbeats']),
        onsets: _d(j['onsets']),
        frameRate: (j['frameRate'] as num).toDouble(),
        rms: _f(j['rms']),
        bass: _f(j['bass']),
        mid: _f(j['mid']),
        high: _f(j['high']),
        onsetEnv: _f(j['onsetEnv']),
        peak: (j['peak'] as num? ?? 0).toDouble(),
        rmsDb: (j['rmsDb'] as num? ?? -90).toDouble(),
        clippedSamples: (j['clippedSamples'] as num? ?? 0).toInt(),
        sectionChanges: _d(j['sectionChanges']),
        averageSpectrum: _f(j['averageSpectrum']),
      );

  /// Returns a copy with manually corrected beats / bpm.
  AudioAnalysis withBeats(List<double> newBeats, {double? newBpm}) {
    final b = [...newBeats]..sort();
    return AudioAnalysis(
      duration: duration,
      bpm: newBpm ?? (b.length > 1 ? 60 / _median([for (var i = 1; i < b.length; i++) b[i] - b[i - 1]]) : bpm),
      bpmConfidence: 1,
      beats: b,
      downbeats: [for (var i = 0; i < b.length; i += 4) b[i]],
      onsets: onsets,
      frameRate: frameRate,
      rms: rms,
      bass: bass,
      mid: mid,
      high: high,
      onsetEnv: onsetEnv,
      peak: peak,
      rmsDb: rmsDb,
      clippedSamples: clippedSamples,
      sectionChanges: sectionChanges,
      averageSpectrum: averageSpectrum,
    );
  }
}

double _median(List<double> v) {
  if (v.isEmpty) return 0.5;
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

/// Local, deterministic music analysis (no network, no AI).
///
/// * Onset strength: log-compressed spectral flux (STFT 1024, hop 512 @22.05k).
/// * Tempo: autocorrelation of onset envelope weighted by a log-Gaussian
///   tempo prior centred at 120 BPM (range 60–200 BPM).
/// * Beats: dynamic-programming beat tracker (Ellis 2007).
/// * Bands: bass 20–150 Hz, mid 150–2000 Hz, high 2–11 kHz energies.
class AudioAnalyzer {
  static const int fftSize = 1024;
  static const int hop = 512;

  static AudioAnalysis analyze(PcmData pcm, {double? bpmHint}) {
    final x = pcm.samples;
    final sr = pcm.sampleRate;
    final fft = FFT(fftSize);
    final nFrames = math.max(1, ((x.length - fftSize) / hop).floor() + 1);
    final frameRate = sr / hop;
    final bins = fftSize ~/ 2;
    final binHz = sr / fftSize;
    int bin(double hz) => math.min(bins - 1, math.max(1, (hz / binHz).round()));
    final bassLo = bin(20), bassHi = bin(150), midHi = bin(2000), highHi = bin(11000);

    final rms = Float32List(nFrames);
    final bass = Float32List(nFrames);
    final mid = Float32List(nFrames);
    final high = Float32List(nFrames);
    final flux = Float32List(nFrames);
    var prev = Float64List(bins);
    var cur = Float64List(bins);
    // log-spaced average spectrum (64 bands, 30Hz..sr/2)
    const nBands = 64;
    final bandEdges = List<int>.generate(nBands + 1, (i) {
      final hz = 30 * math.pow((sr / 2) / 30, i / nBands);
      return bin(hz.toDouble());
    });
    final avgSpec = Float64List(nBands);

    for (var f = 0; f < nFrames; f++) {
      final off = f * hop;
      var s2 = 0.0;
      for (var i = 0; i < fftSize && off + i < x.length; i++) {
        s2 += x[off + i] * x[off + i];
      }
      rms[f] = math.sqrt(s2 / fftSize);
      fft.magnitudes(x, off, cur);
      var fl = 0.0, eb = 0.0, em = 0.0, eh = 0.0;
      for (var k = 1; k < bins; k++) {
        final lc = math.log(1 + 100 * cur[k]);
        final lp = math.log(1 + 100 * prev[k]);
        final d = lc - lp;
        if (d > 0) fl += d;
        final p = cur[k] * cur[k];
        if (k >= bassLo && k <= bassHi) {
          eb += p;
        } else if (k > bassHi && k <= midHi) {
          em += p;
        } else if (k > midHi && k <= highHi) {
          eh += p;
        }
      }
      for (var b = 0; b < nBands; b++) {
        var acc = 0.0;
        final lo = bandEdges[b], hi = math.max(bandEdges[b] + 1, bandEdges[b + 1]);
        for (var k = lo; k < hi && k < bins; k++) {
          acc += cur[k];
        }
        avgSpec[b] += acc / (hi - lo);
      }
      flux[f] = fl;
      bass[f] = math.sqrt(eb);
      mid[f] = math.sqrt(em);
      high[f] = math.sqrt(eh);
      final t = prev;
      prev = cur;
      cur = t;
    }

    // Normalise envelopes (95th percentile to 1).
    void norm(Float32List v) {
      if (v.isEmpty) return;
      final s = Float32List.fromList(v)..sort();
      final ref = s[(s.length * 0.95).floor().clamp(0, s.length - 1)];
      final r = ref <= 1e-9 ? 1.0 : ref;
      for (var i = 0; i < v.length; i++) {
        v[i] = math.min(1.0, v[i] / r);
      }
    }

    // Onset envelope: subtract local mean (high-pass), half-wave rectify.
    final onsetEnv = Float32List(nFrames);
    const w = 8;
    for (var i = 0; i < nFrames; i++) {
      var m = 0.0;
      var c = 0;
      for (var j = i - w; j <= i + w; j++) {
        if (j >= 0 && j < nFrames) {
          m += flux[j];
          c++;
        }
      }
      onsetEnv[i] = math.max(0, flux[i] - m / c).toDouble();
    }
    norm(onsetEnv);
    final rmsRaw = Float32List.fromList(rms);
    norm(bass);
    norm(mid);
    norm(high);

    // Peak / clipping / RMS dB on the raw signal.
    var peak = 0.0;
    var clipped = 0;
    var sum2 = 0.0;
    for (final v in x) {
      final a = v.abs();
      if (a > peak) peak = a;
      if (a >= 0.999) clipped++;
      sum2 += v * v;
    }
    final rmsAll = x.isEmpty ? 0 : math.sqrt(sum2 / x.length);
    final rmsDb = rmsAll <= 1e-9 ? -90.0 : 20 * math.log(rmsAll) / math.ln10;

    // Tempo via autocorrelation.
    final minLag = (frameRate * 60 / 200).floor();
    final maxLag = (frameRate * 60 / 60).ceil();
    final ac = Float64List(maxLag + 2);
    for (var lag = minLag; lag <= maxLag; lag++) {
      var s = 0.0;
      for (var i = lag; i < nFrames; i++) {
        s += onsetEnv[i] * onsetEnv[i - lag];
      }
      ac[lag] = s / math.max(1, nFrames - lag);
    }
    final center = bpmHint ?? 120.0;
    var bestLag = minLag;
    var bestScore = -1.0;
    var total = 0.0;
    for (var lag = minLag; lag <= maxLag; lag++) {
      final bpmL = 60 * frameRate / lag;
      final prior = math.exp(-0.5 * math.pow(math.log(bpmL / center) / math.ln2 / 0.9, 2));
      // also reward harmonics (2x lag) for stability
      final harm = lag * 2 <= maxLag ? ac[lag * 2] * 0.5 : 0.0;
      final score = (ac[lag] + harm) * prior;
      total += score;
      if (score > bestScore) {
        bestScore = score;
        bestLag = lag;
      }
    }
    // Parabolic interpolation for sub-frame lag precision.
    var lagF = bestLag.toDouble();
    if (bestLag > minLag && bestLag < maxLag) {
      final a = ac[bestLag - 1], b = ac[bestLag], c = ac[bestLag + 1];
      final den = a - 2 * b + c;
      if (den.abs() > 1e-12) lagF = bestLag + 0.5 * (a - c) / den;
    }
    var bpm = 60 * frameRate / lagF;
    final meanScore = total / math.max(1, maxLag - minLag + 1);
    final conf = meanScore <= 0 ? 0.0 : math.min(1.0, (bestScore / meanScore - 1) / 4);

    // Dynamic programming beat tracking.
    final period = 60 * frameRate / bpm;
    const tightness = 100.0;
    final score = Float64List(nFrames);
    final backlink = Int32List(nFrames)..fillRange(0, nFrames, -1);
    for (var i = 0; i < nFrames; i++) {
      var best = 0.0;
      var bi = -1;
      final lo = (i - 2 * period).round(), hi = (i - period / 2).round();
      for (var j = math.max(0, lo); j <= hi && j < i; j++) {
        final d = math.log((i - j) / period);
        final s = score[j] - tightness * d * d;
        if (bi < 0 || s > best) {
          best = s;
          bi = j;
        }
      }
      score[i] = onsetEnv[i] + (bi >= 0 ? best : 0);
      backlink[i] = bi;
    }
    // Find best end in last period.
    var end = nFrames - 1;
    var endScore = -1e18;
    for (var i = math.max(0, (nFrames - period).floor()); i < nFrames; i++) {
      if (score[i] > endScore) {
        endScore = score[i];
        end = i;
      }
    }
    final beatFrames = <int>[];
    for (var i = end; i >= 0; i = backlink[i]) {
      beatFrames.add(i);
      if (backlink[i] < 0) break;
    }
    final beats = beatFrames.reversed.map((f) => (f * hop + fftSize / 2) / sr).toList();
    // Drop leading beats in silence.
    final silentRms = 0.02;
    beats.removeWhere((b) {
      final f = (b * frameRate).floor().clamp(0, nFrames - 1);
      return rmsRaw[f] < silentRms * 0.5;
    });
    // Sub-frame refinement of beat positions (parabolic peak interpolation)
    for (var k = 0; k < beats.length; k++) {
      final f = ((beats[k] * sr - fftSize / 2) / hop).round();
      if (f > 0 && f < nFrames - 1) {
        final a = onsetEnv[f - 1], b = onsetEnv[f], c = onsetEnv[f + 1];
        final den = a - 2 * b + c;
        if (den.abs() > 1e-9 && b >= a && b >= c) {
          final d = (0.5 * (a - c) / den).clamp(-0.5, 0.5);
          beats[k] = ((f + d) * hop + fftSize / 2) / sr;
        }
      }
    }
    if (beats.length > 4) {
      // Least-squares fit of beat index vs time gives a precise tempo.
      final n = beats.length;
      var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
      for (var i = 0; i < n; i++) {
        sx += i;
        sy += beats[i];
        sxx += i * i;
        sxy += i * beats[i];
      }
      final slope = (n * sxy - sx * sy) / (n * sxx - sx * sx);
      if (slope > 0.2 && slope < 1.2) bpm = 60 / slope;
    }

    // Downbeats: choose phase (0..3) maximising bass energy at beats.
    final downbeats = <double>[];
    if (beats.isNotEmpty) {
      var bestPhase = 0;
      var bestE = -1.0;
      for (var ph = 0; ph < 4; ph++) {
        var e = 0.0;
        for (var i = ph; i < beats.length; i += 4) {
          final f = (beats[i] * frameRate).floor().clamp(0, nFrames - 1);
          e += bass[f] + onsetEnv[f];
        }
        if (e > bestE) {
          bestE = e;
          bestPhase = ph;
        }
      }
      for (var i = bestPhase; i < beats.length; i += 4) {
        downbeats.add(beats[i]);
      }
    }

    // Transients: local maxima of onset envelope above adaptive threshold.
    final onsets = <double>[];
    final minGap = (0.05 * frameRate).ceil();
    var last = -minGap;
    for (var i = 1; i < nFrames - 1; i++) {
      var m = 0.0;
      var c = 0;
      for (var j = i - 16; j <= i + 16; j++) {
        if (j >= 0 && j < nFrames) {
          m += onsetEnv[j];
          c++;
        }
      }
      final thr = 0.15 + 1.2 * m / c;
      if (onsetEnv[i] > thr && onsetEnv[i] >= onsetEnv[i - 1] && onsetEnv[i] > onsetEnv[i + 1] && i - last >= minGap) {
        onsets.add((i * hop + fftSize / 2) / sr);
        last = i;
      }
    }

    // Dynamic section changes: compare 4s RMS windows.
    final sections = <double>[];
    final win = (4 * frameRate).round();
    if (nFrames > win * 2) {
      final step = (frameRate).round();
      double meanRms(int a, int b) {
        var s = 0.0;
        for (var i = a; i < b; i++) {
          s += rmsRaw[i];
        }
        return s / math.max(1, b - a);
      }

      var lastChange = -1e9;
      for (var i = win; i < nFrames - win; i += step) {
        final a = meanRms(i - win, i), b = meanRms(i, i + win);
        final ratio = (math.max(a, b) + 1e-4) / (math.min(a, b) + 1e-4);
        final t = i / frameRate;
        if (ratio > 1.8 && t - lastChange > 8) {
          sections.add(t);
          lastChange = t;
        }
      }
    }

    final spec = Float32List(nBands);
    for (var b = 0; b < nBands; b++) {
      final v = avgSpec[b] / nFrames;
      spec[b] = v <= 1e-9 ? -90 : 20 * math.log(v) / math.ln10;
    }
    norm(rms);
    return AudioAnalysis(
      duration: pcm.duration,
      bpm: bpm,
      bpmConfidence: conf,
      beats: beats,
      downbeats: downbeats,
      onsets: onsets,
      frameRate: frameRate,
      rms: rms,
      bass: bass,
      mid: mid,
      high: high,
      onsetEnv: onsetEnv,
      peak: peak,
      rmsDb: rmsDb,
      clippedSamples: clipped,
      sectionChanges: sections,
      averageSpectrum: spec,
    );
  }

  /// Min/max peak pairs for waveform drawing: returns 2*buckets values.
  static Float32List waveformPeaks(Float32List x, int buckets) {
    final out = Float32List(buckets * 2);
    if (x.isEmpty) return out;
    final per = x.length / buckets;
    for (var b = 0; b < buckets; b++) {
      final s = (b * per).floor(), e = math.min(x.length, ((b + 1) * per).ceil());
      var mn = 0.0, mx = 0.0;
      for (var i = s; i < e; i++) {
        final v = x[i];
        if (v < mn) mn = v;
        if (v > mx) mx = v;
      }
      out[b * 2] = mn;
      out[b * 2 + 1] = mx;
    }
    return out;
  }

  /// Instantaneous spectrum (dB, [bins] log bands) at time t – used by the
  /// live spectrum analyser view.
  static Float32List spectrumAt(PcmData pcm, double t, {int bands = 48, int size = 2048}) {
    final fft = FFT(size);
    final off = (t * pcm.sampleRate).round() - size ~/ 2;
    final m = fft.magnitudes(pcm.samples, off);
    final out = Float32List(bands);
    final binHz = pcm.sampleRate / size;
    for (var b = 0; b < bands; b++) {
      final lo = (30 * math.pow((pcm.sampleRate / 2) / 30, b / bands) / binHz).floor().clamp(1, size ~/ 2 - 1);
      final hi = math.max(lo + 1, (30 * math.pow((pcm.sampleRate / 2) / 30, (b + 1) / bands) / binHz).floor().clamp(1, size ~/ 2));
      var acc = 0.0;
      for (var k = lo; k < hi; k++) {
        acc = math.max(acc, m[k]);
      }
      out[b] = acc <= 1e-9 ? -90 : 20 * math.log(acc) / math.ln10;
    }
    return out;
  }
}
