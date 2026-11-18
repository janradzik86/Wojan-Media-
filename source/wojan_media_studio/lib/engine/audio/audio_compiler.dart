import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../dsp/pcm.dart';
import '../export/audio_formats.dart';
import '../ffmpeg/escape.dart';
import '../ffmpeg/runner.dart';
import '../project/asset.dart';
import '../util/expr.dart';
import '../util/json_util.dart';
import 'audio_project.dart';
import 'effects.dart';

/// Graph builder shared by audio and video renderers.
class AudioGraphBuilder {
  final List<String> inputs = []; // ffmpeg input args
  final List<String> chains = [];
  int _inputCount = 0;
  int _label = 0;
  final int sampleRate;
  final Directory workDir;
  final Map<String, String> _irCache = {};
  late final FxContext fx;

  AudioGraphBuilder({required this.sampleRate, required this.workDir, int inputOffset = 0}) {
    _inputCount = inputOffset;
    fx = FxContext(sampleRate: sampleRate, addAuxInput: (p) => '[${addInput(p)}:a]', impulseResponse: _ir);
  }

  int addInput(String path, {List<String> pre = const []}) {
    inputs.addAll([...pre, '-i', path]);
    return _inputCount++;
  }

  String label(String p) => '${p}${_label++}';

  /// Generates a stereo exponential-decay noise impulse response (Schroeder
  /// style) for convolution reverb. Deterministic for given params.
  String _ir(double room, double damp) {
    final key = '${room.toStringAsFixed(2)}_${damp.toStringAsFixed(2)}';
    return _irCache.putIfAbsent(key, () {
      final len = (sampleRate * (0.3 + room * 3.2)).round();
      final rnd = math.Random(42);
      final chs = [Float32List(len), Float32List(len)];
      final t60 = 0.3 + room * 3.2;
      for (var c = 0; c < 2; c++) {
        var lp = 0.0;
        for (var i = 0; i < len; i++) {
          final t = i / sampleRate;
          final env = math.pow(10, -3 * t / t60).toDouble();
          final n = rnd.nextDouble() * 2 - 1;
          final a = 0.15 + damp * 0.8 * math.min(1.0, t / t60 * 2);
          lp = lp + (1 - a) * (n - lp); // progressive damping (lowpass)
          chs[c][i] = (lp * env * 0.5).toDouble();
        }
        // early reflections
        for (final ms in [7, 13, 19, 27, 37]) {
          final idx = (ms / 1000 * sampleRate * (0.5 + room)).round();
          if (idx < len) chs[c][idx] += (c == 0 ? 0.5 : 0.45) * (1 - ms / 60);
        }
      }
      final f = File('${workDir.path}/ir_$key.wav');
      workDir.createSync(recursive: true);
      // synchronous write via pcm helper
      writeWav16Sync(f, chs, sampleRate);
      return f.path;
    });
  }

  /// Applies an effect chain to [inLabel] returning the output label.
  String applyEffects(String inLabel, List<AudioEffect> effects) {
    var cur = inLabel;
    for (final e in effects.where((e) => e.enabled)) {
      final out = label('fx');
      chains.add(compileEffect(e, cur, out, fx));
      cur = out;
    }
    return cur;
  }

  String get graph => chains.join(';');
}

void writeWav16Sync(File f, List<Float32List> channels, int sampleRate) {
  final n = channels.first.length;
  final ch = channels.length;
  final dataLen = n * ch * 2;
  final bd = ByteData(44 + dataLen);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      bd.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  bd.setUint32(4, 36 + dataLen, Endian.little);
  str(8, 'WAVEfmt ');
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little);
  bd.setUint16(22, ch, Endian.little);
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * ch * 2, Endian.little);
  bd.setUint16(32, ch * 2, Endian.little);
  bd.setUint16(34, 16, Endian.little);
  str(36, 'data');
  bd.setUint32(40, dataLen, Endian.little);
  var o = 44;
  for (var i = 0; i < n; i++) {
    for (var c = 0; c < ch; c++) {
      final v = channels[c][i].clamp(-1.0, 1.0);
      bd.setInt16(o, (v * 32767).round(), Endian.little);
      o += 2;
    }
  }
  f.writeAsBytesSync(bd.buffer.asUint8List(), flush: true);
}

/// Compiles an [AudioProject] into a filter graph section producing a single
/// stereo float stream labelled with the returned name.
class AudioProjectCompiler {
  final AudioProject project;
  final AssetResolver assets;
  AudioProjectCompiler(this.project, this.assets);

  String clipChain(AudioGraphBuilder b, AudioClip c) {
    final sr = b.sampleRate;
    final idx = b.addInput(assets.pathOf(c.assetId));
    final f = <String>[
      'atrim=start=${fsec(c.srcIn)}:end=${fsec(c.srcOut)}',
      'asetpts=PTS-STARTPTS',
      'aformat=sample_fmts=fltp:sample_rates=$sr:channel_layouts=stereo',
      if (c.reverse) 'areverse',
      ...atempoChain(c.tempo),
    ];
    if (c.pitch.abs() > 1e-3) {
      final r = math.pow(2, c.pitch / 12).toDouble();
      f.addAll(['asetrate=${(sr * r).round()}', 'aresample=$sr', ...atempoChain(1 / r)]);
    }
    if (c.loops > 1) {
      final samples = (c.singleLength * sr).round();
      f.add('aloop=loop=${c.loops - 1}:size=$samples');
      f.add('asetpts=N/SR/TB');
    }
    var cur = b.label('clip');
    b.chains.add('[$idx:a]${f.join(',')}[$cur]');
    cur = b.applyEffects(cur, c.effects);
    final post = <String>[];
    if (c.muted) {
      post.add('volume=0');
    } else if (c.gainDb.abs() > 1e-3) {
      post.add('volume=${FfEscape.num(c.gainDb)}dB');
    }
    if (c.volumeAuto.isNotEmpty && !c.muted) {
      post.add("volume=eval=frame:volume='${keyframeExpr(c.volumeAuto)}'");
    }
    final len = c.length;
    if (c.fadeIn > 0) post.add('afade=t=in:st=0:d=${fsec(math.min(c.fadeIn, len))}:curve=tri');
    if (c.fadeOut > 0) post.add('afade=t=out:st=${fsec(math.max(0, len - c.fadeOut))}:d=${fsec(math.min(c.fadeOut, len))}:curve=tri');
    // Exact length after effects such as tempo (atempo can leave a few ms).
    post.add('apad');
    post.add('atrim=end=${fsec(len)}');
    final delayMs = (c.position * 1000).round();
    if (delayMs > 0) post.add('adelay=delays=$delayMs:all=1');
    final out = b.label('pc');
    b.chains.add('[$cur]${post.join(',')}[$out]');
    return out;
  }

  /// Returns label of the final mix, or null if nothing audible.
  String? compile(AudioGraphBuilder b, {double? rangeStart, double? rangeEnd}) {
    final anySolo = project.tracks.any((t) => t.solo);
    final trackOuts = <String>[];
    for (final t in project.tracks) {
      if (t.muted || (anySolo && !t.solo)) continue;
      final clipOuts = [for (final c in t.clips) clipChain(b, c)];
      if (clipOuts.isEmpty) continue;
      String mixed;
      if (clipOuts.length == 1) {
        mixed = clipOuts.first;
      } else {
        mixed = b.label('tm');
        b.chains.add('${clipOuts.map((e) => '[$e]').join()}amix=inputs=${clipOuts.length}:normalize=0:duration=longest:dropout_transition=0[$mixed]');
      }
      var cur = b.applyEffects(mixed, t.effects);
      final post = <String>[];
      if (t.gainDb.abs() > 1e-3) post.add('volume=${FfEscape.num(t.gainDb)}dB');
      if (t.pan.abs() > 1e-3) {
        final l = t.pan > 0 ? 1 - t.pan : 1.0, r = t.pan < 0 ? 1 + t.pan : 1.0;
        post.add('pan=stereo|c0=${FfEscape.num(l)}*c0|c1=${FfEscape.num(r)}*c1');
      }
      if (post.isNotEmpty) {
        final o = b.label('tp');
        b.chains.add('[$cur]${post.join(',')}[$o]');
        cur = o;
      }
      trackOuts.add(cur);
    }
    if (trackOuts.isEmpty) return null;
    String master;
    if (trackOuts.length == 1) {
      master = trackOuts.first;
    } else {
      master = b.label('mx');
      b.chains.add('${trackOuts.map((e) => '[$e]').join()}amix=inputs=${trackOuts.length}:normalize=0:duration=longest:dropout_transition=0[$master]');
    }
    master = b.applyEffects(master, project.masterEffects);
    final post = <String>[];
    if (project.masterGainDb.abs() > 1e-3) post.add('volume=${FfEscape.num(project.masterGainDb)}dB');
    final dur = project.duration;
    if (rangeStart != null || rangeEnd != null) {
      post.add('atrim=start=${fsec(rangeStart ?? 0)}:end=${fsec(rangeEnd ?? dur)}');
      post.add('asetpts=PTS-STARTPTS');
    } else {
      post.add('atrim=end=${fsec(dur)}');
    }
    final out = b.label('master');
    b.chains.add('[$master]${post.join(',')}[$out]');
    return out;
  }
}

/// Renders audio projects to files.
class AudioRenderer {
  final MediaRunner runner;
  final Directory workDir;
  AudioRenderer(this.runner, this.workDir);

  List<String> buildArgs(AudioProject p, AssetResolver assets, String outPath, AudioExportSettings s,
      {double? rangeStart, double? rangeEnd, Map<String, String> metadata = const {}}) {
    final b = AudioGraphBuilder(sampleRate: p.sampleRate, workDir: workDir);
    final out = AudioProjectCompiler(p, assets).compile(b, rangeStart: rangeStart, rangeEnd: rangeEnd);
    if (out == null) throw MediaEngineException('Projekt nie zawiera słyszalnych klipów');
    return [
      ...b.inputs,
      '-filter_complex', b.graph,
      '-map', '[$out]',
      for (final e in metadata.entries) ...['-metadata', '${e.key}=${e.value}'],
      ...s.codecArgs(),
      outPath,
    ];
  }

  Future<void> render(AudioProject p, AssetResolver assets, String outPath, AudioExportSettings s,
      {double? rangeStart, double? rangeEnd, ProgressCb? onProgress, CancelToken? cancel, Map<String, String> metadata = const {}}) async {
    await workDir.create(recursive: true);
    final args = buildArgs(p, assets, outPath, s, rangeStart: rangeStart, rangeEnd: rangeEnd, metadata: metadata);
    await runner.run(args, onProgress: onProgress, cancel: cancel, what: 'Renderowanie audio nie powiodło się');
  }
}
