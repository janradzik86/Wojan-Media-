import 'dart:convert';
import 'dart:io';

import '../export/audio_formats.dart';
import '../ffmpeg/escape.dart';
import '../ffmpeg/runner.dart';
import '../util/json_util.dart';
import 'effects.dart';

class LoudnessReport {
  final double integratedLufs, truePeakDb, lra, threshold;
  LoudnessReport(this.integratedLufs, this.truePeakDb, this.lra, this.threshold);
}

class SilenceRegion {
  final double start, end;
  SilenceRegion(this.start, this.end);
}

/// Quick, single-purpose tools (no timeline needed) – Mstudio style.
class AudioTools {
  final MediaRunner runner;
  AudioTools(this.runner);

  /// Format conversion with bitrate / sample rate / channels.
  Future<void> convert(String input, String output, AudioExportSettings s,
      {double? start, double? end, List<AudioEffect> effects = const [], Map<String, String> metadata = const {}, ProgressCb? onProgress, CancelToken? cancel}) async {
    final af = <String>[];
    if (effects.isNotEmpty) {
      // effects on a simple chain; complex ones use the project renderer
      for (final e in effects) {
        final g = compileEffect(e, 'a', 'b', FxContext(sampleRate: s.sampleRate, addAuxInput: (_) => throw UnsupportedError('aux'), impulseResponse: (_, _) => throw UnsupportedError('ir')));
        af.add(g.replaceFirst('[a]', '').replaceFirst(RegExp(r'\[b\]$'), ''));
      }
    }
    await runner.run([
      if (start != null) ...['-ss', fsec(start)],
      if (end != null) ...['-to', fsec(end)],
      '-i', input,
      '-vn', '-map', '0:a:0',
      if (af.isNotEmpty) ...['-af', af.join(',')],
      '-map_metadata', '0',
      for (final m in metadata.entries) ...['-metadata', '${m.key}=${m.value}'],
      ...s.codecArgs(),
      output,
    ], onProgress: onProgress, cancel: cancel, what: 'Konwersja nie powiodła się');
  }

  /// Cutter: keep [start,end] with optional fades.
  Future<void> cut(String input, String output, AudioExportSettings s, double start, double end, {double fadeIn = 0, double fadeOut = 0, CancelToken? cancel}) async {
    final len = end - start;
    if (len <= 0) throw MediaEngineException('Nieprawidłowy zakres cięcia');
    final af = <String>[
      if (fadeIn > 0) 'afade=t=in:st=0:d=${fsec(fadeIn)}',
      if (fadeOut > 0) 'afade=t=out:st=${fsec(len - fadeOut)}:d=${fsec(fadeOut)}',
    ];
    await runner.run([
      '-ss', fsec(start), '-t', fsec(len), '-i', input, '-vn', '-map', '0:a:0',
      if (af.isNotEmpty) ...['-af', af.join(',')],
      '-map_metadata', '0',
      ...s.codecArgs(), output,
    ], cancel: cancel, what: 'Cięcie nie powiodło się');
  }

  /// Omitter: removes [start,end] from the middle, joining the rest.
  Future<void> omit(String input, String output, AudioExportSettings s, double start, double end, {double crossfade = 0.02}) async {
    await runner.run([
      '-i', input,
      '-filter_complex',
      '[0:a]atrim=end=${fsec(start)},asetpts=PTS-STARTPTS[a];[0:a]atrim=start=${fsec(end)},asetpts=PTS-STARTPTS[b];[a][b]acrossfade=d=${fsec(crossfade)}:c1=tri:c2=tri[o]',
      '-map', '[o]', ...s.codecArgs(), output,
    ], what: 'Usuwanie fragmentu nie powiodło się');
  }

  /// Splitter: splits into two files at [at].
  Future<void> split(String input, String outA, String outB, AudioExportSettings s, double at) async {
    await runner.run(['-t', fsec(at), '-i', input, '-vn', '-map', '0:a:0', ...s.codecArgs(), outA]);
    await runner.run(['-ss', fsec(at), '-i', input, '-vn', '-map', '0:a:0', ...s.codecArgs(), outB]);
  }

  /// Merger: concatenates files (any formats) with optional crossfade.
  Future<void> merge(List<String> inputs, String output, AudioExportSettings s, {double crossfade = 0, ProgressCb? onProgress, CancelToken? cancel}) async {
    if (inputs.isEmpty) throw MediaEngineException('Brak plików do połączenia');
    final args = <String>[for (final i in inputs) ...['-i', i]];
    final g = StringBuffer();
    for (var i = 0; i < inputs.length; i++) {
      g.write('[$i:a]aformat=sample_fmts=fltp:sample_rates=${s.sampleRate}:channel_layouts=stereo[a$i];');
    }
    if (inputs.length == 1) {
      g.write('[a0]anull[o]');
    } else if (crossfade > 0) {
      var cur = 'a0';
      for (var i = 1; i < inputs.length; i++) {
        final o = i == inputs.length - 1 ? 'o' : 'x$i';
        g.write('[$cur][a$i]acrossfade=d=${fsec(crossfade)}[$o];');
        cur = o;
      }
    } else {
      g.write('${[for (var i = 0; i < inputs.length; i++) '[a$i]'].join()}concat=n=${inputs.length}:v=0:a=1[o]');
    }
    var graph = g.toString();
    if (graph.endsWith(';')) graph = graph.substring(0, graph.length - 1);
    await runner.run([...args, '-filter_complex', graph, '-map', '[o]', ...s.codecArgs(), output],
        onProgress: onProgress, cancel: cancel, what: 'Łączenie nie powiodło się');
  }

  /// Mixer: overlays files with individual volumes and offsets.
  Future<void> mix(List<String> inputs, String output, AudioExportSettings s, {List<double>? volumesDb, List<double>? offsets, bool longest = true}) async {
    final args = <String>[for (final i in inputs) ...['-i', i]];
    final g = StringBuffer();
    for (var i = 0; i < inputs.length; i++) {
      final v = volumesDb == null ? 0.0 : volumesDb[i];
      final off = offsets == null ? 0.0 : offsets[i];
      g.write('[$i:a]aformat=sample_fmts=fltp:sample_rates=${s.sampleRate}:channel_layouts=stereo,volume=${FfEscape.num(v)}dB');
      if (off > 0) g.write(',adelay=delays=${(off * 1000).round()}:all=1');
      g.write('[m$i];');
    }
    g.write('${[for (var i = 0; i < inputs.length; i++) '[m$i]'].join()}amix=inputs=${inputs.length}:normalize=0:duration=${longest ? 'longest' : 'shortest'},alimiter=limit=0.97:level=disabled[o]');
    await runner.run([...args, '-filter_complex', g.toString(), '-map', '[o]', ...s.codecArgs(), output], what: 'Miksowanie nie powiodło się');
  }

  /// Extract audio track from a video file.
  Future<void> extractFromVideo(String video, String output, AudioExportSettings s, {ProgressCb? onProgress, CancelToken? cancel}) async {
    await runner.run(['-i', video, '-vn', '-map', '0:a:0', '-map_metadata', '0', ...s.codecArgs(), output],
        onProgress: onProgress, cancel: cancel, what: 'Plik wideo nie zawiera ścieżki audio lub jest uszkodzony');
  }

  /// ID3 / tag editor with optional cover art. Stream copy, no re-encode.
  Future<void> writeTags(String input, String output, Map<String, String> tags, {String? coverImage}) async {
    final ext = output.split('.').last.toLowerCase();
    final supportsCover = {'mp3', 'm4a', 'flac'}.contains(ext);
    await runner.run([
      '-i', input,
      if (coverImage != null && supportsCover) ...['-i', coverImage],
      '-map', '0:a',
      if (coverImage != null && supportsCover) ...['-map', '1:v', '-c:v', ext == 'flac' ? 'png' : 'mjpeg', '-disposition:v', 'attached_pic', '-metadata:s:v', 'title=Cover', '-metadata:s:v', 'comment=Cover (front)'],
      '-c:a', 'copy',
      '-map_metadata', '0',
      for (final t in tags.entries) ...['-metadata', '${t.key}=${t.value}'],
      if (ext == 'mp3') ...['-id3v2_version', '3'],
      output,
    ], what: 'Zapis tagów nie powiódł się');
  }

  /// Ringtone maker (≤ 40 s, fades, m4a/mp3/ogg).
  Future<void> ringtone(String input, String output, double start, double end) async {
    final ext = output.split('.').last.toLowerCase();
    final s = AudioExportSettings(format: AudioExportSettings.formatFromExtension(ext) ?? AudioFormat.mp3, bitrateKbps: 192);
    final len = (end - start).clamp(1.0, 40.0);
    await cut(input, output, s, start, start + len, fadeIn: 0.3, fadeOut: 1.0);
  }

  /// EBU R128 loudness measurement.
  Future<LoudnessReport> measureLoudness(String input) async {
    final r = await runner.ffmpeg(['-i', input, '-vn', '-af', 'loudnorm=print_format=json', '-f', 'null', '-']);
    if (!r.ok) throw MediaEngineException('Pomiar głośności nie powiódł się', r.errorSummary);
    final i = r.log.lastIndexOf('{');
    final j = r.log.indexOf('}', i);
    final m = jsonDecode(r.log.substring(i, j + 1)) as Map<String, dynamic>;
    return LoudnessReport(jd(m['input_i']), jd(m['input_tp']), jd(m['input_lra']), jd(m['input_thresh']));
  }

  /// Two-pass, linear LUFS normalisation (accurate, no pumping).
  Future<void> normalizeLufs(String input, String output, AudioExportSettings s, {double targetLufs = -14, double truePeak = -1}) async {
    final m = await measureLoudness(input);
    await runner.run([
      '-i', input, '-vn',
      '-af',
      'loudnorm=I=${FfEscape.num(targetLufs)}:TP=${FfEscape.num(truePeak)}:LRA=11:measured_I=${FfEscape.num(m.integratedLufs)}:measured_TP=${FfEscape.num(m.truePeakDb)}:measured_LRA=${FfEscape.num(m.lra)}:measured_thresh=${FfEscape.num(m.threshold)}:linear=true,aresample=${s.sampleRate}',
      ...s.codecArgs(), output,
    ], what: 'Normalizacja nie powiodła się');
  }

  /// Peak normalisation to [targetDb] dBFS.
  Future<void> normalizePeak(String input, String output, AudioExportSettings s, {double targetDb = -1}) async {
    final r = await runner.ffmpeg(['-i', input, '-vn', '-af', 'volumedetect', '-f', 'null', '-']);
    final m = RegExp(r'max_volume:\s*(-?[\d.]+) dB').firstMatch(r.log);
    if (m == null) throw MediaEngineException('Nie można zmierzyć szczytu', r.errorSummary);
    final gain = targetDb - double.parse(m.group(1)!);
    await runner.run(['-i', input, '-vn', '-af', 'volume=${FfEscape.num(gain)}dB', ...s.codecArgs(), output]);
  }

  /// Detects silence regions.
  Future<List<SilenceRegion>> detectSilence(String input, {double thresholdDb = -45, double minDur = 0.5}) async {
    final r = await runner.ffmpeg(['-i', input, '-vn', '-af', 'silencedetect=n=${FfEscape.num(thresholdDb)}dB:d=${FfEscape.num(minDur)}', '-f', 'null', '-']);
    final out = <SilenceRegion>[];
    double? st;
    for (final l in r.log.split('\n')) {
      final a = RegExp(r'silence_start: (-?[\d.]+)').firstMatch(l);
      final b = RegExp(r'silence_end: (-?[\d.]+)').firstMatch(l);
      if (a != null) st = double.parse(a.group(1)!);
      if (b != null && st != null) {
        out.add(SilenceRegion(st < 0 ? 0 : st, double.parse(b.group(1)!)));
        st = null;
      }
    }
    return out;
  }

  /// Batch conversion; returns list of produced files (errors collected).
  Future<Map<String, String?>> batchConvert(List<String> inputs, String outDir, AudioExportSettings s,
      {void Function(int done, int total)? onFile, CancelToken? cancel}) async {
    final res = <String, String?>{};
    await Directory(outDir).create(recursive: true);
    for (var i = 0; i < inputs.length; i++) {
      if (cancel?.isCancelled == true) break;
      final inp = inputs[i];
      final base = inp.split(RegExp(r'[\\/]')).last;
      final stem = base.contains('.') ? base.substring(0, base.lastIndexOf('.')) : base;
      var out = '$outDir/$stem.${s.extension}';
      if (out == inp) out = '$outDir/${stem}_conv.${s.extension}';
      try {
        await convert(inp, out, s, cancel: cancel);
        res[inp] = out;
      } catch (e) {
        res[inp] = null;
      }
      onFile?.call(i + 1, inputs.length);
    }
    return res;
  }

  /// Render a waveform / spectrum PNG image (ffmpeg showwavespic/showspectrumpic).
  Future<void> waveformImage(String input, String outPng, {int w = 1200, int h = 240, String color = '0x35D0BA'}) async {
    await runner.run(['-i', input, '-filter_complex', 'aformat=channel_layouts=mono,showwavespic=s=${w}x$h:colors=${FfEscape.color(color)}', '-frames:v', '1', outPng]);
  }

  Future<void> spectrumImage(String input, String outPng, {int w = 1200, int h = 400}) async {
    await runner.run(['-i', input, '-lavfi', 'showspectrumpic=s=${w}x$h:legend=1:color=intensity', outPng]);
  }

  /// Records-safe helper: makes sure output dir exists.
  static Future<void> ensureDir(String file) async => File(file).parent.create(recursive: true);
}
