import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wojan_media_studio/engine/audio/audio_project.dart';
import 'package:wojan_media_studio/engine/dsp/analysis.dart';
import 'package:wojan_media_studio/engine/dsp/pcm.dart';
import 'package:wojan_media_studio/engine/export/video_export.dart';
import 'package:wojan_media_studio/engine/ffmpeg/probe.dart';
import 'package:wojan_media_studio/engine/lyrics/lyrics.dart';
import 'package:wojan_media_studio/engine/project/asset.dart';
import 'package:wojan_media_studio/engine/video/color.dart';
import 'package:wojan_media_studio/engine/video/compiler.dart';
import 'package:wojan_media_studio/engine/video/model.dart';
import 'package:wojan_media_studio/engine/video/transitions.dart';
import 'package:wojan_media_studio/engine/video/vfx.dart';
import 'package:wojan_media_studio/engine/video/visualizer.dart';

import 'test_media.dart';

final fontsDir = '${Directory.current.path}/assets/fonts';

void main() {
  late Map<String, MediaAsset> assets;
  late MapAssetResolver resolver;
  late AudioAnalysis music;
  late String outDir;

  Future<void> add(String id, String path) async {
    final info = MediaInfo.fromProbe(path, await TestMedia.runner.probeJson(path));
    assets[id] = MediaAsset(id: id, name: id, kind: info.kind, sha256: '', size: info.sizeBytes, relPath: '', duration: info.duration, width: info.width, height: info.height, hasAudio: info.hasAudio, localPath: path);
  }

  setUpAll(() async {
    await TestMedia.init();
    outDir = Platform.environment['WMS_TEST_OUT'] ?? TestMedia.dir.path;
    Directory(outDir).createSync(recursive: true);
    assets = {};
    await add('song', await TestMedia.clickTrack(120, 16));
    await add('img1', await TestMedia.image('img1', 'red'));
    await add('img2', await TestMedia.image('img2', 'blue', w: 1200, h: 1600));
    await add('img3', await TestMedia.image('img3', 'green', w: 1920, h: 1080));
    await add('clip1', await TestMedia.video('clip1', 4));
    await add('logo', await TestMedia.image('logo', 'yellow', w: 400, h: 400));
    resolver = MapAssetResolver(assets, TestMedia.dir.path);
    music = AudioAnalyzer.analyze(await PcmDecoder(TestMedia.runner, TestMedia.dir).decode(assets['song']!.localPath!));
  });

  test('mandatory video scenario: 9:16 music video 1080x1920 with fx, transitions, PL captions', () async {
    final p = VideoProject(width: 1080, height: 1920, fps: 30);
    p.audio.tracks.first.clips.add(AudioClip(assetId: 'song', srcIn: 0, srcOut: assets['song']!.duration));
    p.musicAssetId = 'song';
    p.clips.addAll([
      VisualClip(kind: ClipKind.image, assetId: 'img1', imageDuration: 4, motion: Motion(preset: MotionPreset.kenBurnsIn), transition: Transition(type: 'fade', duration: 0.5), animIn: 'fade'),
      VisualClip(kind: ClipKind.video, assetId: 'clip1', srcIn: 0.5, srcOut: 3.5, fit: FitMode.blurBackground, transition: Transition(type: 'slideleft', duration: 0.5), grade: ColorGrade()..filter = 'teal_orange'),
      VisualClip(kind: ClipKind.image, assetId: 'img2', imageDuration: 4, motion: Motion(preset: MotionPreset.beatPulse, intensity: 0.8), transition: Transition(type: 'spin', duration: 0.6)),
      VisualClip(kind: ClipKind.image, assetId: 'img3', imageDuration: 4, motion: Motion(preset: MotionPreset.panRight), transition: Transition(type: 'glitch', duration: 0.4), fit: FitMode.contain),
      VisualClip(kind: ClipKind.image, assetId: 'img1', imageDuration: 3, motion: Motion(preset: MotionPreset.zoomInRotate)),
    ]);
    p.vfx.addAll([
      VfxItem(type: 'snow', start: 0, duration: 6, reactive: true),
      VfxItem(type: 'beatflash', intensity: 0.5),
      VfxItem(type: 'vignette', intensity: 0.4),
    ]);
    p.overlays.add(OverlayItem(assetId: 'logo', start: 1, duration: 10, x: 0.85, y: 0.1, scale: 0.15, mask: MaskShape.circle, animIn: 'fade'));
    p.texts.add(TextItem(text: 'Zażółć gęślą jaźń – ŁÓDŹ', start: 0.5, duration: 4, anim: 'wordPop', style: TextStyleSpec(font: 'Anton', size: 80, align: 'center')));
    p.lyrics = LyricsTrack(mode: LyricsMode.karaoke, lines: [
      LyricLine(5, 8, 'Śpiewam o świcie nad Wisłą'),
      LyricLine(8.5, 12, 'Gwiazdy płoną jak źrenice'),
    ], style: TextStyleSpec(size: 60).toJson());
    p.visualizers.add(VisualizerItem(style: 'bars', y: 0.78, height: 0.12, start: 0, duration: 0));
    final dur = p.duration;
    expect(dur, closeTo(4 + 3 + 4 + 4 + 3 - 0.5 - 0.5 - 0.6 - 0.4, 0.01));
    final out = '$outDir/teledysk_test_1080x1920.mp4';
    final r = VideoRenderer(TestMedia.runner, Directory('${TestMedia.dir.path}/vwork'), fontsDir);
    final s = VideoExportSettings(width: 1080, height: 1920, fps: 30, preset: 'veryfast', crf: 23);
    final sw = Stopwatch()..start();
    final enc = await r.render(p, resolver, s, out, music: music);
    // ignore: avoid_print
    print('rendered with $enc in ${sw.elapsed.inSeconds}s, duration $dur');
    final info = MediaInfo.fromProbe(out, await TestMedia.runner.probeJson(out));
    expect(info.width, 1080);
    expect(info.height, 1920);
    expect(info.videoCodec, 'h264');
    expect(info.audioCodec, 'aac');
    expect(info.hasAudio, isTrue);
    expect(info.duration, closeTo(dur, 0.1));
    expect(info.fps, closeTo(30, 0.01));
    // frame count
    final fr = await TestMedia.runner.ffprobe(['-v', 'error', '-count_frames', '-select_streams', 'v:0', '-show_entries', 'stream=nb_read_frames', '-of', 'csv=p=0', out]);
    expect(int.parse(fr.log.trim().split('\n').first), closeTo((dur * 30).round(), 2));
    // contact sheet for visual verification
    await TestMedia.runner.run(['-i', out, '-vf', 'fps=1,scale=270:-1,tile=8x2', '-frames:v', '1', '-update', '1', '$outDir/teledysk_test_sheet.png']);
    // A/V sync: audio stream duration equals video duration
    final st = await TestMedia.runner.ffprobe(['-v', 'error', '-show_entries', 'stream=codec_type,duration', '-of', 'csv=p=0', out]);
    final durs = st.log.trim().split('\n').where((l) => l.contains(',')).map((l) => double.parse(l.split(',')[1])).toList();
    expect((durs[0] - durs[1]).abs(), lessThan(0.08));
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('every transition renders', () async {
    final r = VideoRenderer(TestMedia.runner, Directory('${TestMedia.dir.path}/vwork'), fontsDir);
    for (final t in transitionNames.keys) {
      final p = VideoProject(width: 320, height: 240, fps: 15);
      p.clips.addAll([
        VisualClip(kind: ClipKind.image, assetId: 'img1', imageDuration: 1.2, transition: Transition(type: t, duration: 0.5)),
        VisualClip(kind: ClipKind.image, assetId: 'img2', imageDuration: 1.2),
      ]);
      final out = '${TestMedia.dir.path}/tr_$t.mp4';
      await r.render(p, resolver, VideoExportSettings(width: 320, height: 240, fps: 15, preset: 'ultrafast'), out);
      final info = MediaInfo.fromProbe(out, await TestMedia.runner.probeJson(out));
      expect(info.duration, closeTo(p.duration, 0.1), reason: t);
    }
    expect(xfadeOptions('spin'), contains('custom'));
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('every vfx, motion and visualizer renders', () async {
    final r = VideoRenderer(TestMedia.runner, Directory('${TestMedia.dir.path}/vwork'), fontsDir);
    final failures = <String>[];
    Future<void> tryRender(String name, VideoProject p) async {
      try {
        final out = '${TestMedia.dir.path}/fx_$name.mp4';
        await r.render(p, resolver, VideoExportSettings(width: 360, height: 640, fps: 15, preset: 'ultrafast'), out, music: music);
        final info = MediaInfo.fromProbe(out, await TestMedia.runner.probeJson(out));
        if ((info.duration - p.duration).abs() > 0.15) failures.add('$name duration ${info.duration}');
      } catch (e) {
        failures.add('$name: $e');
      }
    }

    VideoProject base() {
      final p = VideoProject(width: 360, height: 640, fps: 15);
      p.audio.tracks.first.clips.add(AudioClip(assetId: 'song', srcIn: 0, srcOut: 3));
      p.clips.add(VisualClip(kind: ClipKind.image, assetId: 'img1', imageDuration: 3));
      return p;
    }

    for (final v in vfxNames.keys) {
      await tryRender('vfx_$v', base()..vfx.add(VfxItem(type: v, reactive: true, start: 0.5, duration: 2)));
    }
    for (final m in MotionPreset.values) {
      final p = base();
      p.clips.first.motion = Motion(preset: m);
      await tryRender('motion_${m.name}', p);
    }
    for (final s in visualizerNames.keys) {
      await tryRender('vis_$s', base()..visualizers.add(VisualizerItem(style: s, x: 0.1, y: 0.3, width: 0.8, height: 0.4, logoAssetId: s == 'circle' ? 'logo' : null)));
    }
    for (final a in textAnimNames.keys) {
      await tryRender('text_$a', base()..texts.add(TextItem(text: 'Tekst ąęł $a', anim: a, duration: 3, style: TextStyleSpec(gradientTo: a == 'fade' ? '#FF0000' : null))));
    }
    for (final a in inOutAnimNames.keys) {
      final p = base();
      p.clips.first.animIn = a;
      p.overlays.add(OverlayItem(assetId: 'clip1', start: 0.5, duration: 2, animIn: a, chromaKey: a == 'fade', mute: false, borderWidth: 4));
      await tryRender('anim_$a', p);
    }
    for (final mask in MaskShape.values) {
      await tryRender('mask_${mask.name}', base()..overlays.add(OverlayItem(assetId: 'img2', mask: mask, scale: 0.5, rotation: 10)));
    }
    final rev = base();
    rev.clips
      ..clear()
      ..add(VisualClip(kind: ClipKind.video, assetId: 'clip1', srcIn: 0, srcOut: 2, reverse: true, speed: 2, freezeAt: 0.5, freezeDuration: 1, rotate: 90, flipH: true, cropW: 0.5, cropH: 0.5));
    await tryRender('video_ops', rev);
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 20)));
}
