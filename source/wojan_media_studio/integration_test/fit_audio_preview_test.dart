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
import 'package:wojan_media_studio/engine/project/asset.dart';
import 'package:wojan_media_studio/engine/video/model.dart';
import 'package:wojan_media_studio/ui/preview/live_preview.dart';
import 'package:wojan_media_studio/ui/preview/preview_controller.dart';
import 'package:wojan_media_studio/ui/preview/text_layer.dart';

/// "Dostosuj do długości audio" exactly as the editor does it: one photo
/// (and many photos) + a song; frames of the live preview and of the export
/// are captured across the whole song.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final out = Platform.environment['WMS_FIT'] ?? '/tmp/wms_fit';

  testWidgets('one photo spans the whole song in preview and export', (t) async {
    MediaKit.ensureInitialized();
    await Services.init();
    await PreviewFonts.ensure(userFontsDir: Services.i.fontsDir);
    await Directory(out).create(recursive: true);
    final r = ProcessRunner();
    final dir = await Directory.systemTemp.createTemp('wms_fit_');
    final photo = '${dir.path}/zdjecie.jpg', song = '${dir.path}/song.mp3';
    // landscape "photo" 4032x3024 like a phone camera
    await r.run(['-f', 'lavfi', '-i', 'mandelbrot=s=1344x1008,scale=4032:3024', '-frames:v', '1', '-q:v', '3', photo]);
    await r.run(['-f', 'lavfi', '-i', "aevalsrc='0.3*sin(2*PI*220*t)':s=44100:d=180", '-ac', '2', song]);
    final s = Services.i;
    final a = await s.store.importMedia(photo), m = await s.store.importMedia(song);
    final assets = {a.id: a, m.id: m};
    final res = MapAssetResolver(assets, s.root.path);
    // exactly what Video Studio creates on "add photo" + "add music"
    final p = VideoProject(width: 1080, height: 1920, fps: 30);
    p.clips.add(VisualClip(kind: ClipKind.image, assetId: a.id, imageDuration: 3, motion: Motion(preset: MotionPreset.kenBurnsIn), fit: FitMode.blurBackground, transition: Transition(type: 'fade', duration: 0.5)));
    p.audio.tracks.first.clips.add(AudioClip(assetId: m.id, srcIn: 0, srcOut: m.duration, fadeOut: 1.5));
    p.musicAssetId = m.id;
    p.fitToAudio(fit: FitMode.blurBackground);
    // ignore: avoid_print
    print('FIT: duration ${p.duration} audio ${p.audioDuration} clip ${p.clips.first.imageDuration} motion ${p.clips.first.motion.toJson()}');
    final pc = PreviewController(project: p, assets: res);
    final key = GlobalKey();
    await t.pumpWidget(MaterialApp(home: Scaffold(backgroundColor: Colors.black, body: Center(child: RepaintBoundary(key: key, child: SizedBox(width: 270, height: 480, child: LivePreview(controller: pc, showControls: false, pausedIcon: false)))))));
    for (final at in [0.5, 30.0, 90.0, 150.0, 179.0]) {
      await pc.seek(at);
      for (var i = 0; i < 8; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
        await t.pump(const Duration(milliseconds: 16));
      }
      final img = (await t.runAsync(() => (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage()))!;
      final png = (await t.runAsync(() => img.toByteData(format: ui.ImageByteFormat.png)))!;
      await File('$out/one_preview_${at.round()}.png').writeAsBytes(png.buffer.asUint8List());
    }
    final mp4 = '${dir.path}/one.mp4';
    await s.videoRenderer().render(p, res, VideoExportSettings(width: 270, height: 480, fps: 10, preset: 'ultrafast', crf: 20), mp4);
    for (final at in [0.5, 30.0, 90.0, 150.0, 179.0]) {
      await r.run(['-ss', '$at', '-i', mp4, '-frames:v', '1', '$out/one_engine_${at.round()}.png']);
    }
    pc.dispose();
  }, timeout: const Timeout(Duration(minutes: 20)));
}
