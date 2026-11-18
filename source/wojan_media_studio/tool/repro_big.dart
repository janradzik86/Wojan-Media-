// Reproduces the 111-clip / 4:47 project from the bug report and prints the
// ffmpeg command size; used with /usr/bin/time to measure peak memory.
import 'dart:io';
import 'package:wojan_media_studio/engine/dsp/analysis.dart';
import 'package:wojan_media_studio/engine/dsp/pcm.dart';
import 'package:wojan_media_studio/engine/ffmpeg/probe.dart';
import 'package:wojan_media_studio/engine/ffmpeg/runner.dart';
import 'package:wojan_media_studio/engine/musicvideo/auto.dart';
import 'package:wojan_media_studio/engine/musicvideo/styles.dart';
import 'package:wojan_media_studio/engine/project/asset.dart';
import 'dart:convert';

Future<void> main(List<String> a) async {
  final dir = Directory(a[0]);
  final r = ProcessRunner();
  final song = '${dir.path}/song.mp3';
  if (!File(song).existsSync()) {
    await r.run(['-f', 'lavfi', '-i', "aevalsrc='if(lt(mod(t,0.48),0.06),sin(2*PI*60*t)*0.9,0)+0.2*sin(2*PI*330*t)':s=44100:d=287", '-ac', '2', song]);
    for (var i = 0; i < 12; i++) {
      await r.run(['-f', 'lavfi', '-i', 'testsrc2=s=3000x4000:d=1', '-vf', 'hue=h=${i * 30}', '-frames:v', '1', '${dir.path}/p$i.jpg']);
    }
  }
  final assets = <String, MediaAsset>{};
  Future<MediaAsset> add(String id, String p) async {
    final i = MediaInfo.fromProbe(p, await r.probeJson(p));
    return assets[id] = MediaAsset(id: id, name: id, kind: i.kind, sha256: id, size: i.sizeBytes, relPath: '', duration: i.duration, width: i.width, height: i.height, hasAudio: i.hasAudio, localPath: p);
  }
  final m = await add('song', song);
  final vis = [for (var i = 0; i < 12; i++) await add('p$i', '${dir.path}/p$i.jpg')];
  final an = AudioAnalyzer.analyze(await PcmDecoder(r, dir).decode(song));
  final v = MusicVideoGenerator().generate(MusicVideoRequest(music: m, visuals: vis, style: styleById('hiphop'), mode: MusicVideoMode.beatSync), an);
  File('${dir.path}/project.json').writeAsStringSync(jsonEncode({'video': v.toJson(), 'assets': assets.map((k, x) => MapEntry(k, {...x.toJson(), 'local': x.localPath}))}));
  stdout.writeln('clips=${v.clips.length} duration=${v.duration.toStringAsFixed(2)} bpm=${an.bpm.toStringAsFixed(1)}');
}
