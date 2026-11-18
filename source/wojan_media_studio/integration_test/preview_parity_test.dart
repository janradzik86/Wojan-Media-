import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:wojan_media_studio/app/services.dart';
import 'package:wojan_media_studio/engine/audio/audio_project.dart';
import 'package:wojan_media_studio/engine/export/video_export.dart';
import 'package:wojan_media_studio/engine/ffmpeg/runner.dart';
import 'package:wojan_media_studio/engine/lyrics/lyrics.dart';
import 'package:wojan_media_studio/engine/project/asset.dart';
import 'package:wojan_media_studio/engine/video/model.dart';
import 'package:wojan_media_studio/ui/preview/live_preview.dart';
import 'package:wojan_media_studio/ui/preview/preview_controller.dart';
import 'package:wojan_media_studio/ui/preview/text_layer.dart';

/// Renders the same project with the export engine (FFmpeg) and with the
/// real-time Flutter preview at the same timeline instant and stores both
/// frames side by side, with a similarity score, for every case. Fails if
/// the preview throws or is wildly different from the export.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final out = Platform.environment['WMS_PARITY'] ?? '/tmp/wms_parity';

  testWidgets('live preview matches export engine frames', (t) async {
    MediaKit.ensureInitialized();
    await Services.init();
    await PreviewFonts.ensure(userFontsDir: Services.i.fontsDir);
    await Directory(out).create(recursive: true);
    final r = ProcessRunner();
    final dir = await Directory.systemTemp.createTemp('wms_par_');
    final img = '${dir.path}/foto.png', img2 = '${dir.path}/foto2.png', song = '${dir.path}/song.wav';
    await r.run(['-f', 'lavfi', '-i', 'testsrc2=s=1080x1920:d=1', '-frames:v', '1', img]);
    await r.run(['-f', 'lavfi', '-i', 'mandelbrot=s=1080x1920', '-frames:v', '1', img2]);
    await r.run(['-f', 'lavfi', '-i', "aevalsrc='if(lt(mod(t,0.5),0.06),sin(2*PI*60*t)*0.9,0)+0.2*sin(2*PI*330*t)':s=44100:d=6", '-ac', '2', song]);
    final s = Services.i;
    final a1 = await s.store.importMedia(img), a2 = await s.store.importMedia(img2), m = await s.store.importMedia(song);
    final assets = {a1.id: a1, a2.id: a2, m.id: m};
    final resolver = MapAssetResolver(assets, s.root.path);
    final music = await s.analyze(resolver.pathOf(m.id), m.sha256);

    VideoProject base({bool two = false}) {
      final p = VideoProject(width: 270, height: 480, fps: 30);
      p.audio.tracks.first.clips.add(AudioClip(assetId: m.id, srcIn: 0, srcOut: 5));
      p.musicAssetId = m.id;
      p.clips.add(VisualClip(kind: ClipKind.image, assetId: a1.id, imageDuration: two ? 2.5 : 5, transition: Transition(type: 'fade', duration: 1)));
      if (two) p.clips.add(VisualClip(kind: ClipKind.image, assetId: a2.id, imageDuration: 2.5));
      return p;
    }

    final cases = <String, (VideoProject, double)>{
      'plain': (base(), 1.5),
      'kenburns': (base()..clips.first.motion = Motion(preset: MotionPreset.kenBurnsIn), 2.5),
      for (final tr in transitionNames.keys.where((k) => k != 'cut')) 'tr_$tr': (base(two: true)..clips.first.transition = Transition(type: tr, duration: 1), 2.0),
      for (final fx in ['tex_hearts_red', 'tex_confetti', 'tex_snowflakes', 'frame_gold', 'frame_film', 'godrays', 'halftone', 'snow', 'fog', 'fire', 'vignette', 'cinematic', 'oldfilm', 'retro', 'blur', 'mirror', 'kaleido', 'rgbsplit', 'zoompunch', 'neon', 'tex_bokeh', 'lights', 'flare'])
        'fx_$fx': (base()..vfx.add(VfxItem(type: fx, intensity: 0.8)), 1.52),
      for (final a in ['fade', 'zoomIn', 'slideUp', 'typewriter', 'wordPop', 'bounce', 'none'])
        'text_$a': (base()..texts.add(TextItem(text: 'Zażółć gęślą', start: 1, duration: 3, anim: a, animDur: 0.8, style: TextStyleSpec(size: 90, align: 'center'))), 1.5),
      'text_box_bottom': (base()..texts.add(TextItem(text: 'Napis na dole', start: 0, duration: 4, anim: 'none', style: TextStyleSpec(size: 60, box: true))), 1.5),
      'lyrics_karaoke': (base()
        ..lyrics = (LyricsTrack(lines: [LyricLine(0.5, 3.5, 'Śpiewam karaoke', [LyricWord(0.5, 1.2, 'Śpiewam'), LyricWord(1.3, 3.0, 'karaoke')])], mode: LyricsMode.karaoke)..style = TextStyleSpec(size: 70).toJson()), 1.6),
      'lyrics_lyric': (base()
        ..lyrics = (LyricsTrack(lines: [LyricLine(0.5, 3.5, 'Tekst piosenki')], mode: LyricsMode.lyric, anim: 'fade')..style = TextStyleSpec(size: 70).toJson()), 1.6),
      'grade_warm': (base()..globalGrade.filter = 'warm', 1.5),
      'vis_bars': (base()..visualizers.add(VisualizerItem(style: 'bars', y: 0.6, height: 0.4)), 1.55),
    };

    final renderer = s.videoRenderer();
    final report = StringBuffer('case\tsimilarity\n');
    final bad = <String>[];
    for (final e in cases.entries) {
      final (p, at) = e.value;
      // ---- engine frame
      final mp4 = '${dir.path}/${e.key}.mp4';
      await renderer.render(p, resolver, VideoExportSettings(width: 270, height: 480, fps: 30, preset: 'ultrafast', crf: 16), mp4, music: music);
      final engPng = '$out/${e.key}_engine.png';
      await r.run(['-ss', at.toStringAsFixed(3), '-i', mp4, '-frames:v', '1', engPng]);
      // ---- live preview frame
      final pc = PreviewController(project: p, assets: resolver, music: music);
      final key = GlobalKey();
      await t.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: Colors.black, body: Center(child: RepaintBoundary(key: key, child: SizedBox(width: 270, height: 480, child: LivePreview(controller: pc, showControls: false, pausedIcon: false))))),
      ));
      await pc.seek(at);
      for (var i = 0; i < 6; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
        await t.pump(const Duration(milliseconds: 16));
      }
      final ex = t.takeException();
      if (ex != null) bad.add('${e.key}: exception $ex');
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = (await t.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
      final bytes = (await t.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
      final prevPng = '$out/${e.key}_preview.png';
      await File(prevPng).writeAsBytes(bytes.buffer.asUint8List());
      await t.pumpWidget(const SizedBox());
      pc.dispose();
      // ---- similarity (SSIM via ffmpeg)
      // Random-dither / film-grain cases are compared after smoothing: their
      // noise is (by design) not the same random pattern in both renderers.
      final noisy = const {'tr_dissolve', 'fx_oldfilm', 'fx_retro'}.contains(e.key);
      final sc = noisy ? 'scale=270:480,gblur=sigma=4' : 'scale=270:480';
      final res = await Process.run('ffmpeg', ['-v', 'info', '-i', engPng, '-i', prevPng, '-lavfi', '[0:v]$sc,format=gray[a];[1:v]$sc,format=gray[b];[a][b]ssim', '-f', 'null', '-']);
      final mm = RegExp(r'All:([0-9.]+)').firstMatch('${res.stderr}');
      final ssim = mm == null ? 0.0 : double.parse(mm.group(1)!);
      report.writeln('${e.key}\t${ssim.toStringAsFixed(3)}');
      if (ssim < 0.4) bad.add('${e.key}: SSIM $ssim');
    }
    await File('$out/report.tsv').writeAsString(report.toString());
    // ignore: avoid_print
    print(report);
    expect(bad, isEmpty, reason: bad.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 30)));

  testWidgets('live preview stays smooth on a 120-clip 1080x1920 project', (t) async {
    final s = Services.i;
    final r = ProcessRunner();
    final dir = await Directory.systemTemp.createTemp('wms_big_');
    final imgs = <String>[];
    for (var k = 0; k < 6; k++) {
      final f = '${dir.path}/z$k.jpg';
      await r.run(['-f', 'lavfi', '-i', k.isEven ? 'testsrc2=s=4000x3000:d=1' : 'mandelbrot=s=3000x4000', '-vf', 'hue=h=${k * 50}', '-frames:v', '1', f]); // distinct files (store dedups by SHA-256)
      imgs.add(f);
    }
    final song = '${dir.path}/song.wav';
    await r.run(['-f', 'lavfi', '-i', "aevalsrc='0.3*sin(2*PI*220*t)':s=44100:d=300", '-ac', '2', song]);
    final assets = <String, MediaAsset>{};
    for (final f in [...imgs, song]) {
      final a = await s.store.importMedia(f);
      assets[a.id] = a;
    }
    final ids = assets.keys.toList();
    expect(ids.length, 7);
    final p = VideoProject(width: 1080, height: 1920, fps: 30);
    for (var k = 0; k < 120; k++) {
      p.clips.add(VisualClip(kind: ClipKind.image, assetId: ids[k % 6], imageDuration: 2.4, motion: Motion(preset: MotionPreset.kenBurnsIn), fit: FitMode.blurBackground, transition: Transition(type: k.isEven ? 'fade' : 'slideleft', duration: 0.5)));
    }
    p.audio.tracks.first.clips.add(AudioClip(assetId: ids.last, srcIn: 0, srcOut: 287));
    p.musicAssetId = ids.last;
    p.vfx.add(VfxItem(type: 'tex_hearts_red'));
    p.texts.add(TextItem(text: 'Gratulujemy!', start: 0, duration: 280, anim: 'glow'));
    final pc = PreviewController(project: p, assets: MapAssetResolver(assets, s.root.path));
    await t.pumpWidget(MaterialApp(home: Scaffold(backgroundColor: Colors.black, body: Center(child: SizedBox(width: 360, height: 700, child: LivePreview(controller: pc))))));
    await pc.seek(100);
    var frames = 0;
    final sw = Stopwatch()..start();
    await pc.play();
    while (sw.elapsedMilliseconds < 6000) {
      await t.pump(const Duration(milliseconds: 16));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1)));
      frames++;
    }
    final pos = pc.position;
    await pc.pause();
    expect(t.takeException(), isNull);
    final fps = frames / (sw.elapsedMilliseconds / 1000);
    // ignore: avoid_print
    print('BIG PROJECT: ${p.clips.length} clips, ${p.duration.toStringAsFixed(1)} s, preview ${fps.toStringAsFixed(1)} fps (debug build, software GL), clock advanced ${(pos - 100).toStringAsFixed(2)} s in ${sw.elapsedMilliseconds / 1000} s');
    await File('$out/big_project.txt').writeAsString('clips=${p.clips.length} duration=${p.duration} fps=$fps advanced=${pos - 100}\n');
    expect(pos - 100, closeTo(sw.elapsedMilliseconds / 1000, 1.0), reason: 'real-time clock');
    expect(fps, greaterThan(10));
    await t.pumpWidget(const SizedBox());
    pc.dispose();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
