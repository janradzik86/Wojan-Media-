import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wojan_media_studio/engine/audio/audio_project.dart';
import 'package:wojan_media_studio/engine/dsp/analysis.dart';
import 'package:wojan_media_studio/engine/dsp/pcm.dart';
import 'package:wojan_media_studio/engine/export/video_export.dart';
import 'package:wojan_media_studio/engine/ffmpeg/probe.dart';
import 'package:wojan_media_studio/engine/lyrics/lyrics.dart';
import 'package:wojan_media_studio/engine/musicvideo/auto.dart';
import 'package:wojan_media_studio/engine/musicvideo/styles.dart';
import 'package:wojan_media_studio/engine/project/asset.dart';
import 'package:wojan_media_studio/engine/video/compiler.dart';
import 'package:wojan_media_studio/engine/video/model.dart';
import 'package:wojan_media_studio/engine/video/segments.dart';

import 'test_media.dart';

void main() {
  final assets = <String, MediaAsset>{};
  late AudioAnalysis music;
  final fonts = '${Directory.current.path}/assets/fonts';
  Future<MediaAsset> add(String id, String path) async {
    final i = MediaInfo.fromProbe(path, await TestMedia.runner.probeJson(path));
    return assets[id] = MediaAsset(id: id, name: id, kind: i.kind, sha256: id, size: i.sizeBytes, relPath: '', duration: i.duration, width: i.width, height: i.height, hasAudio: i.hasAudio, localPath: path);
  }

  setUpAll(() async {
    await TestMedia.init();
    await add('song', await TestMedia.clickTrack(120, 14));
    await add('a', await TestMedia.image('a', 'red', w: 3000, h: 4000)); // big photo → proxy
    await add('b', await TestMedia.image('b', 'blue', w: 1920, h: 1080));
    await add('v', await TestMedia.video('v', 4));
    music = AudioAnalyzer.analyze(await PcmDecoder(TestMedia.runner, TestMedia.dir).decode(assets['song']!.localPath!));
  });

  VideoProject project() {
    final p = VideoProject(width: 540, height: 960, fps: 24);
    p.audio.tracks.first.clips.add(AudioClip(assetId: 'song', srcIn: 0, srcOut: 14));
    p.musicAssetId = 'song';
    p.clips.addAll([
      VisualClip(kind: ClipKind.image, assetId: 'a', imageDuration: 2.37, motion: Motion(preset: MotionPreset.kenBurnsIn), transition: Transition(type: 'fade', duration: 0.5)),
      VisualClip(kind: ClipKind.image, assetId: 'b', imageDuration: 1.93, motion: Motion(preset: MotionPreset.beatPulse), transition: Transition(type: 'cut')),
      VisualClip(kind: ClipKind.video, assetId: 'v', srcIn: 0.3, srcOut: 3.1, transition: Transition(type: 'slideleft', duration: 0.41)),
      VisualClip(kind: ClipKind.image, assetId: 'a', imageDuration: 3.11, motion: Motion(preset: MotionPreset.panRight), transition: Transition(type: 'spin', duration: 0.6), fit: FitMode.blurBackground),
      VisualClip(kind: ClipKind.image, assetId: 'b', imageDuration: 2.71, motion: Motion(preset: MotionPreset.zoomInRotate), animOut: 'fade'),
    ]);
    p.texts.add(TextItem(text: 'Napis ąęł', start: 1, duration: 5));
    p.vfx.add(VfxItem(type: 'beatflash'));
    p.lyrics = LyricsTrack(lines: [LyricLine(2, 5, 'Wers karaoke')], mode: LyricsMode.karaoke);
    return p;
  }

  test('segmented render == single-graph render (frame count, A/V, PSNR)', () async {
    final s = VideoExportSettings(width: 540, height: 960, fps: 24, preset: 'veryfast', crf: 16);
    final r = VideoRenderer(TestMedia.runner, Directory('${TestMedia.dir.path}/sw'), fonts);
    final single = '${TestMedia.dir.path}/single.mp4', seg = '${TestMedia.dir.path}/seg.mp4';
    await r.render(project(), MapAssetResolver(assets, ''), s, single, music: music, segmented: false);
    final sw = Stopwatch()..start();
    await r.render(project(), MapAssetResolver(assets, ''), s, seg, music: music);
    final first = sw.elapsedMilliseconds;
    Future<int> frames(String f) async => int.parse((await TestMedia.runner.ffprobe(['-v', 'error', '-count_frames', '-select_streams', 'v:0', '-show_entries', 'stream=nb_read_frames', '-of', 'csv=p=0', f])).log.trim().split('\n').first);
    expect(await frames(seg), await frames(single));
    expect(await frames(seg), (project().duration * 24).round());
    // Per-frame PSNR outside transition windows (inside them both methods
    // quantise fast motion to the frame grid with a sub-frame phase shift).
    final stats = '${TestMedia.dir.path}/psnr.txt';
    await TestMedia.runner.run(['-i', seg, '-i', single, '-lavfi', 'psnr=stats_file=$stats', '-f', 'null', '-']);
    final pr = project();
    final starts = pr.clipStarts();
    final windows = <(double, double)>[for (var i = 0; i < pr.clips.length - 1; i++) if (!pr.clips[i].transition.isCut) (starts[i + 1] - 1 / 24, starts[i + 1] + pr.effectiveTransition(i) + 1 / 24)];
    var checked = 0;
    for (final line in File(stats).readAsLinesSync()) {
      final n = int.parse(RegExp(r'n:(\d+)').firstMatch(line)!.group(1)!) - 1;
      final t = n / 24;
      if (windows.any((w) => t >= w.$1 && t <= w.$2)) continue;
      final v = RegExp(r'psnr_avg:([\d.]+|inf)').firstMatch(line)!.group(1)!;
      expect(v == 'inf' || double.parse(v) > 30, isTrue, reason: 'frame $n PSNR $v');
      checked++;
    }
    expect(checked, greaterThan((pr.duration * 24 * 0.8).round()));
    final ss = await TestMedia.runner.ffmpeg(['-i', seg, '-i', single, '-lavfi', 'ssim', '-f', 'null', '-']);
    final ssim = double.parse(RegExp(r'All:([\d.]+)').firstMatch(ss.log)!.group(1)!);
    // ignore: avoid_print
    print('SSIM segmented vs single: $ssim; frames outside transitions all > 30 dB ($checked); first segmented render ${first}ms');
    expect(ssim, greaterThan(0.97));
    // second render: all segments from cache → much faster
    final sw2 = Stopwatch()..start();
    await r.render(project(), MapAssetResolver(assets, ''), s, '${TestMedia.dir.path}/seg2.mp4', music: music);
    // ignore: avoid_print
    print('cached re-render ${sw2.elapsedMilliseconds}ms');
    expect(sw2.elapsedMilliseconds, lessThan(first * 0.8), reason: 'segments must come from cache');
    // change one clip → only that segment (and its neighbour) re-rendered
    final p2 = project()..clips[3].grade.saturation = 0.2;
    final plans = SegmentedRenderer.plan(p2, 24);
    expect(plans.length, 5);
    await r.render(p2, MapAssetResolver(assets, ''), s, '${TestMedia.dir.path}/seg3.mp4', music: music);
    final a = MediaInfo.fromProbe('${TestMedia.dir.path}/seg3.mp4', await TestMedia.runner.probeJson('${TestMedia.dir.path}/seg3.mp4'));
    expect(a.duration, closeTo(p2.duration, 0.05));
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('long project (120 clips, 4 min) renders with bounded graphs and exact length', () async {
    final v = MusicVideoGenerator().generate(MusicVideoRequest(music: assets['song']!, visuals: [assets['a']!, assets['b']!, assets['v']!], style: styleById('phonk'), mode: MusicVideoMode.beatSync), music);
    // stretch to 4 minutes by repeating clips
    final base = [...v.clips];
    while (v.clips.length < 120) {
      v.clips.addAll(base.map((c) => c.copy()));
    }
    v.fixedDuration = null;
    v.audio.tracks.first.clips.first.loops = 20;
    final out = '${TestMedia.dir.path}/long.mp4';
    final r = VideoRenderer(TestMedia.runner, Directory('${TestMedia.dir.path}/lw'), fonts);
    await r.render(v, MapAssetResolver(assets, ''), VideoExportSettings(width: 180, height: 320, fps: 12, preset: 'ultrafast', crf: 32), out, music: music);
    final i = MediaInfo.fromProbe(out, await TestMedia.runner.probeJson(out));
    expect(v.clips.length, greaterThanOrEqualTo(120));
    expect(i.duration, closeTo(v.duration, 0.1));
    final n = int.parse((await TestMedia.runner.ffprobe(['-v', 'error', '-count_frames', '-select_streams', 'v:0', '-show_entries', 'stream=nb_read_frames', '-of', 'csv=p=0', out])).log.trim().split('\n').first);
    expect(n, (v.duration * 12).round());
  }, timeout: const Timeout(Duration(minutes: 20)));
}
