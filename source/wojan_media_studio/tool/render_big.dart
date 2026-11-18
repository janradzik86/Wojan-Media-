import 'dart:convert';
import 'dart:io';
import 'package:wojan_media_studio/engine/export/video_export.dart';
import 'package:wojan_media_studio/engine/ffmpeg/runner.dart';
import 'package:wojan_media_studio/engine/project/asset.dart';
import 'package:wojan_media_studio/engine/video/compiler.dart';
import 'package:wojan_media_studio/engine/video/model.dart';

Future<void> main(List<String> a) async {
  final j = jsonDecode(File('${a[0]}/project.json').readAsStringSync()) as Map<String, dynamic>;
  final v = VideoProject.fromJson(j['video'] as Map<String, dynamic>);
  final assets = (j['assets'] as Map).map((k, x) => MapEntry(k as String, MediaAsset.fromJson(Map<String, dynamic>.from(x as Map))..localPath = (x as Map)['local'] as String));
  final scale = double.parse(a[1]);
  final r = VideoRenderer(ProcessRunner(ffmpegPath: '${a[0]}/ffmpeg_timed.sh'), Directory('${a[0]}/work'), '${Directory.current.path}/assets/fonts');
  final sw = Stopwatch()..start();
  var last = 0.0;
  try {
    final enc = await r.render(v, MapAssetResolver(assets, ''), VideoExportSettings(width: (1080 * scale / 2).round() * 2, height: (1920 * scale / 2).round() * 2, fps: a.length > 2 ? double.parse(a[2]) : 20, preset: 'ultrafast', crf: 30), '${a[0]}/out_$scale.mp4', onProgress: (t) {
      if (t - last > 20) { last = t; stdout.writeln('progress ${t.toStringAsFixed(0)}s @ ${sw.elapsed.inSeconds}s'); }
    });
    stdout.writeln('DONE enc=$enc in ${sw.elapsed.inSeconds}s');
  } catch (e) {
    stdout.writeln('FAILED after ${sw.elapsed.inSeconds}s: $e');
  }
}
