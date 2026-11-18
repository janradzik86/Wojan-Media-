import 'dart:convert';
import 'dart:io';
import 'package:wojan_media_studio/engine/ffmpeg/runner.dart';
import 'package:wojan_media_studio/engine/project/asset.dart';
import 'package:wojan_media_studio/engine/video/compiler.dart';
import 'package:wojan_media_studio/engine/video/model.dart';
import 'package:wojan_media_studio/engine/video/segments.dart';

Future<void> main(List<String> a) async {
  final j = jsonDecode(File('${a[0]}/project.json').readAsStringSync()) as Map<String, dynamic>;
  final v = VideoProject.fromJson(j['video'] as Map<String, dynamic>);
  final assets = (j['assets'] as Map).map((k, x) => MapEntry(k as String, MediaAsset.fromJson(Map<String, dynamic>.from(x as Map))..localPath = (x as Map)['local'] as String));
  final plans = SegmentedRenderer.plan(v, 20);
  stdout.writeln('plan frames=${plans.fold<int>(0, (s, p) => s + p.frames)} expected=${(v.visualDuration * 20).round()} n=${plans.length} clips=${v.clips.length}');
  final r = ProcessRunner();
  var bad = 0;
  for (final sp in plans.take(int.parse(a[1]))) {
    final g = VideoCompiler(sp.mini, MapAssetResolver(assets, ''), Directory('${a[0]}/dwork'), CompileOptions(scale: 0.33, fps: 20, fontsDir: '/tmp', clipsOnly: true, trimStartFrame: sp.localStart, trimEndFrame: sp.localStart + sp.frames, timeOffset: sp.timeOffset)).compile();
    final res = await r.ffmpeg([...g.inputs, '-filter_complex', g.graph, '-map', '[${g.videoLabel}]', '-an', '-c:v', 'libx264', '-preset', 'ultrafast', '-r', '20', '-frames:v', '${sp.frames}', '${a[0]}/d.mp4']);
    final c = await r.ffprobe(['-v', 'error', '-select_streams', 'v:0', '-count_packets', '-show_entries', 'stream=nb_read_packets', '-of', 'csv=p=0', '${a[0]}/d.mp4']);
    final got = int.tryParse(c.log.trim().split('\n').first) ?? -1;
    if (got != sp.frames) {
      bad++;
      stdout.writeln('seg ${sp.index}: want ${sp.frames} got $got local=${sp.localStart} miniDur=${sp.mini.visualDuration.toStringAsFixed(4)} clipDur=${v.clips[sp.index].duration.toStringAsFixed(4)} tr=${v.clips[sp.index].transition.type}/${v.effectiveTransition(sp.index).toStringAsFixed(3)} ok=${res.ok}');
    }
  }
  stdout.writeln('bad=$bad');
}
