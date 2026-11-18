import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../dsp/analysis.dart';
import '../export/video_export.dart';
import '../ffmpeg/escape.dart';
import '../ffmpeg/probe.dart';
import '../ffmpeg/runner.dart';
import '../project/asset.dart';
import '../util/hash.dart';
import '../util/json_util.dart';
import 'compiler.dart';
import 'model.dart';

/// One unit of the segmented render: clip [index] from its first frame after
/// the incoming transition up to (and including) its outgoing transition into
/// the next clip. Frame ranges are on the GLOBAL frame grid so concatenated
/// segments stay sample-accurate with the audio track.
class SegmentPlan {
  final int index;
  final int globalStart, globalEnd; // frames [start, end)
  final int localStart; // first frame inside the mini project
  final VideoProject mini;
  final double timeOffset;
  SegmentPlan(this.index, this.globalStart, this.globalEnd, this.localStart, this.mini, this.timeOffset);
  int get frames => globalEnd - globalStart;
}

/// Asset resolver that substitutes downscaled proxies for big photos.
class ProxyResolver implements AssetResolver {
  final AssetResolver inner;
  final Map<String, String> proxies;
  ProxyResolver(this.inner, this.proxies);
  @override
  MediaAsset asset(String id) => inner.asset(id);
  @override
  String pathOf(String id) => proxies[id] ?? inner.pathOf(id);
}

/// Scalable renderer: memory use is independent of the number of clips
/// (every FFmpeg graph has at most two clip inputs). Segments are cached by
/// content hash, so after an edit only the changed clips are re-rendered.
class SegmentedRenderer {
  final MediaRunner runner;
  final Directory workDir;
  final Directory cacheDir;
  final String fontsDir;
  final Future<Set<String>> Function() encoders;
  SegmentedRenderer({required this.runner, required this.workDir, required this.cacheDir, required this.fontsDir, required this.encoders});

  static List<SegmentPlan> plan(VideoProject p, double fps) {
    final starts = p.clipStarts();
    final out = <SegmentPlan>[];
    final n = p.clips.length;
    final total = p.visualDuration;
    for (var i = 0; i < n; i++) {
      final s = starts[i];
      final inT = i > 0 ? p.effectiveTransition(i - 1) : 0.0;
      final a = ((s + inT) * fps).round();
      final b = i == n - 1 ? (total * fps).round() : ((s + p.clips[i].duration) * fps).round();
      if (b <= a) continue;
      final mini = VideoProject(width: p.width, height: p.height, fps: p.fps, background: p.background, clipAudio: false);
      final c0 = VisualClip.fromJson(p.clips[i].toJson());
      if (i == n - 1) c0.transition = Transition();
      mini.clips.add(c0);
      if (i < n - 1 && !p.clips[i].transition.isCut) {
        final c1 = VisualClip.fromJson(p.clips[i + 1].toJson());
        c1.transition = Transition();
        mini.clips.add(c1);
      }
      out.add(SegmentPlan(i, a, b, a - (s * fps).round(), mini, s));
    }
    return out;
  }

  /// Downscaled copies of large photos (decoded once instead of per frame).
  Future<Map<String, String>> makeProxies(VideoProject p, AssetResolver assets, int maxDim) async {
    final ids = <String>{
      for (final c in p.clips)
        if (c.kind == ClipKind.image && c.assetId != null) c.assetId!,
      for (final o in p.overlays) o.assetId,
    };
    final dir = Directory('${cacheDir.path}/proxy');
    await dir.create(recursive: true);
    final out = <String, String>{};
    for (final id in ids) {
      final a = assets.asset(id);
      if (a.kind != MediaKind.image) continue;
      final path = assets.pathOf(id);
      if (path.toLowerCase().endsWith('.gif') || path.toLowerCase().endsWith('.png') || path.toLowerCase().endsWith('.webp')) continue; // keep alpha/animation
      var w = a.width ?? 0, h = a.height ?? 0;
      if (w == 0 || h == 0) {
        try {
          final i = MediaInfo.fromProbe(path, await runner.probeJson(path));
          w = i.width ?? 0;
          h = i.height ?? 0;
        } catch (_) {}
      }
      if (math.max(w, h) <= maxDim) continue;
      final key = sha256String('${a.sha256.isEmpty ? path : a.sha256}|${File(path).existsSync() ? File(path).lastModifiedSync().millisecondsSinceEpoch : 0}|$maxDim');
      final f = File('${dir.path}/$key.jpg');
      if (!f.existsSync()) {
        final tmp = '${f.path}.tmp.jpg';
        final r = await runner.ffmpeg(['-i', path, '-vf', 'scale=$maxDim:$maxDim:force_original_aspect_ratio=decrease:flags=lanczos', '-frames:v', '1', '-q:v', '2', '-update', '1', tmp]);
        if (!r.ok || !File(tmp).existsSync()) continue;
        await File(tmp).rename(f.path);
      }
      out[id] = f.path;
    }
    return out;
  }

  String _cacheKey(SegmentPlan sp, AssetResolver assets, VideoExportSettings s, String encoder, AudioAnalysis? music, double musicOffset) {
    final usesBeat = sp.mini.clips.any((c) => c.motion.preset == MotionPreset.beatPulse);
    final paths = [
      for (final c in sp.mini.clips)
        if (c.assetId != null) () {
          final pth = assets.pathOf(c.assetId!);
          final f = File(pth);
          return '$pth|${f.existsSync() ? f.lengthSync() : 0}|${f.existsSync() ? f.lastModifiedSync().millisecondsSinceEpoch : 0}';
        }(),
      for (final c in sp.mini.clips)
        if (c.grade.lutAssetId != null) assets.pathOf(c.grade.lutAssetId!),
    ];
    return sha256String(jsonEncode({
      'v': 3,
      'mini': _noIds(sp.mini.toJson()),
      'range': [sp.localStart, sp.frames],
      'size': [s.width, s.height, s.fps],
      'enc': encoder,
      'q': [s.crf, s.bitrateKbps],
      'paths': paths,
      if (usesBeat) 'beat': [sp.timeOffset, music?.bpm, music?.beats.isEmpty ?? true ? 0 : music!.beats.first, musicOffset],
    }));
  }

  /// Intermediate (mezzanine) encoding: high quality, fast.
  List<String> _segArgs(String enc, VideoExportSettings s) {
    switch (enc) {
      case 'libx264':
        return ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '${math.max(12, s.crf - 6)}', '-pix_fmt', 'yuv420p', '-g', '${(s.fps * 2).round()}'];
      case 'mpeg4':
        return ['-c:v', 'mpeg4', '-q:v', '2', '-pix_fmt', 'yuv420p'];
      default:
        final kbps = math.max(2000, (s.effectiveVideoKbps * 3).round());
        return ['-c:v', enc, '-b:v', '${kbps}k', '-pix_fmt', enc.endsWith('_qsv') ? 'nv12' : 'yuv420p'];
    }
  }

  void _pruneCache(Directory d, {int maxBytes = 3 << 30}) {
    if (!d.existsSync()) return;
    final files = d.listSync().whereType<File>().where((f) => f.path.endsWith('.mp4')).toList()..sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    var total = files.fold<int>(0, (s, f) => s + f.lengthSync());
    for (final f in files) {
      if (total <= maxBytes) break;
      total -= f.lengthSync();
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }

  /// Renders [p] into [out]; returns encoder used for the final pass.
  Future<String> render(VideoProject p, AssetResolver assets, VideoExportSettings s, String out,
      {AudioAnalysis? music, double musicOffset = 0, ProgressCb? onProgress, CancelToken? cancel, required List<String> Function(CompiledGraph g, String enc) finalArgs}) async {
    await workDir.create(recursive: true);
    final segDir = Directory('${cacheDir.path}/segments');
    await segDir.create(recursive: true);
    final total = p.duration;
    final fps = s.fps;
    final scale = s.width / p.width;
    final proxies = await makeProxies(p, assets, (math.max(s.width, s.height) * 1.6).round());
    final res = ProxyResolver(assets, proxies);
    final plans = plan(p, fps);
    final totalFrames = plans.fold<int>(0, (a, b) => a + b.frames);
    final encList = s.encoderCandidates(await encoders());
    // Mezzanine encoder: the first candidate that works (probed on segment 1).
    var segEncIdx = 0;
    var framesDone = 0;
    final files = <String>[];
    for (final sp in plans) {
      if (cancel?.isCancelled == true) throw MediaEngineException('Renderowanie anulowane');
      String? done;
      MediaEngineException? last;
      for (var e = segEncIdx; e < encList.length; e++) {
        final enc = encList[e];
        final key = _cacheKey(sp, res, s, enc, music, musicOffset);
        final f = File('${segDir.path}/$key.mp4');
        if (f.existsSync() && f.lengthSync() > 0) {
          done = f.path;
          segEncIdx = e;
          break;
        }
        final g = VideoCompiler(sp.mini, res, Directory('${workDir.path}/seg'), CompileOptions(scale: scale, fps: fps, fontsDir: fontsDir, music: music, musicOffset: musicOffset, timeOffset: sp.timeOffset, clipsOnly: true, trimStartFrame: sp.localStart, trimEndFrame: sp.localStart + sp.frames)).compile();
        final tmp = '${f.path}.part.mp4';
        final base = framesDone;
        final r = await runner.ffmpeg([...g.inputs, '-filter_complex', g.graph, '-map', '[${g.videoLabel}]', '-an', ..._segArgs(enc, s), '-r', FfEscape.num(fps), '-frames:v', '${sp.frames}', tmp], cancel: cancel, onProgress: (t) {
          onProgress?.call(((base + (t * fps).clamp(0, sp.frames)) / math.max(1, totalFrames)) * total * 0.75);
        });
        if (r.cancelled) throw MediaEngineException('Renderowanie anulowane');
        if (r.ok && File(tmp).existsSync() && File(tmp).lengthSync() > 0) {
          await File(tmp).rename(f.path);
          done = f.path;
          segEncIdx = e;
          break;
        }
        if (File(tmp).existsSync()) await File(tmp).delete();
        last = MediaEngineException('Ujęcie ${sp.index + 1}: renderowanie nie powiodło się (enkoder $enc)', r.errorSummary);
      }
      if (done == null) throw last ?? MediaEngineException('Ujęcie ${sp.index + 1}: brak enkodera');
      files.add(done);
      framesDone += sp.frames;
      onProgress?.call(framesDone / math.max(1, totalFrames) * total * 0.75);
    }
    // concat list (stream concat by the demuxer – no quality loss)
    final list = File('${workDir.path}/segments_${DateTime.now().microsecondsSinceEpoch}.txt');
    await list.writeAsString(files.map((f) => "file '${f.replaceAll("'", "'\\''")}'").join('\n'));
    // Final pass: layers + grade + audio on top of the visual track.
    final g = VideoCompiler(p, res, workDir, CompileOptions(scale: scale, fps: fps, fontsDir: fontsDir, music: music, musicOffset: musicOffset, baseVideo: list.path)).compile();
    MediaEngineException? last;
    final tried = <String>[];
    final finalEncs = s.container == VideoContainer.gif ? ['gif'] : encList;
    for (final enc in finalEncs) {
      final r = await runner.ffmpeg(finalArgs(g, enc), cancel: cancel, onProgress: (t) => onProgress?.call(total * 0.75 + t * 0.25));
      if (r.cancelled) throw MediaEngineException('Renderowanie anulowane');
      if (r.ok) {
        _pruneCache(segDir);
        try {
          await list.delete();
        } catch (_) {}
        return enc;
      }
      tried.add(enc);
      last = MediaEngineException('Renderowanie nie powiodło się (enkoder $enc)', r.errorSummary);
    }
    throw MediaEngineException('Renderowanie nie powiodło się – wypróbowano enkodery: ${tried.join(', ')}', last?.details);
  }
}

/// Removes identity fields so equal content gives equal cache keys.
Object? _noIds(Object? v) {
  if (v is Map) return {for (final e in v.entries) if (e.key != 'id') e.key: _noIds(e.value)};
  if (v is List) return v.map(_noIds).toList();
  return v;
}

/// Used by tests/diagnostics.
String describePlan(List<SegmentPlan> plans) => plans.map((p) => '#${p.index}[${p.globalStart},${p.globalEnd})').join(' ');

/// Global frame count expected for a project at [fps].
int expectedFrames(VideoProject p, double fps) => (p.duration * fps).round();

/// Utility for JSON maps in cache keys.
Map<String, dynamic> stableJson(Map<String, dynamic> m) => jm(jsonDecode(jsonEncode(m)));
