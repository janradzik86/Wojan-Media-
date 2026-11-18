import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wojan_media_studio/engine/audio/audio_project.dart';
import 'package:wojan_media_studio/engine/dsp/analysis.dart';
import 'package:wojan_media_studio/engine/dsp/pcm.dart';
import 'package:wojan_media_studio/engine/export/video_export.dart';
import 'package:wojan_media_studio/engine/ffmpeg/probe.dart';
import 'package:wojan_media_studio/engine/project/asset.dart';
import 'package:wojan_media_studio/engine/video/compiler.dart';
import 'package:wojan_media_studio/engine/video/intros.dart';
import 'package:wojan_media_studio/engine/video/model.dart';
import 'package:wojan_media_studio/engine/video/vfx.dart';
import 'package:wojan_media_studio/engine/video/vfx_library.dart';

import 'test_media.dart';

/// Renders every effect of the extended library with FFmpeg and checks that
/// it really changes the picture (not a silent no-op) and keeps the length.
void main() {
  late Map<String, MediaAsset> assets;
  late MapAssetResolver resolver;
  late AudioAnalysis music;
  final fontsDir = '${Directory.current.path}/assets/fonts';

  Future<void> add(String id, String path) async {
    final info = MediaInfo.fromProbe(path, await TestMedia.runner.probeJson(path));
    assets[id] = MediaAsset(id: id, name: id, kind: info.kind, sha256: '', size: info.sizeBytes, relPath: '', duration: info.duration, width: info.width, height: info.height, hasAudio: info.hasAudio, localPath: path);
  }

  setUpAll(() async {
    await TestMedia.init();
    FxAssets.dir = '${Directory.current.path}/assets/fx';
    assets = {};
    await add('song', await TestMedia.clickTrack(120, 8));
    await add('img', await TestMedia.image('img_lib', 'gray', w: 1080, h: 1920));
    resolver = MapAssetResolver(assets, TestMedia.dir.path);
    music = AudioAnalyzer.analyze(await PcmDecoder(TestMedia.runner, TestMedia.dir).decode(assets['song']!.localPath!));
  });

  Future<Uint8List> frames(String path) async {
    final raw = '$path.gray';
    await TestMedia.runner.run(['-y', '-i', path, '-vf', 'scale=90:160', '-f', 'rawvideo', '-pix_fmt', 'gray', raw]);
    return File(raw).readAsBytes();
  }

  test('catalogue is consistent', () {
    for (final cat in vfxCategories.values) {
      for (final id in cat) {
        expect(allVfxNames.containsKey(id), isTrue, reason: 'category item $id has a name');
      }
    }
    for (final id in vfxLibraryNames.keys) {
      expect(isLibraryVfx(id), isTrue, reason: id);
    }
    for (final f in [...particleTextures.values.map((e) => e.file), ...frameTextures.values, ...spriteEffects.values]) {
      expect(File('assets/fx/$f').existsSync(), isTrue, reason: f);
    }
    expect(texTiling(1080, 1920).$1, 1);
    expect(texTiling(1920, 1080).$1, 3);
    final (_, _, tw, th) = texTiling(1920, 1080);
    expect(tw >= 1920 && th >= 1080, isTrue);
  });

  for (final size in const [(360, 640), (640, 360)]) {
    test('every library effect renders and changes the picture ${size.$1}x${size.$2}', () async {
      final r = VideoRenderer(TestMedia.runner, Directory('${TestMedia.dir.path}/libwork'), fontsDir);
      VideoProject base() {
        final p = VideoProject(width: size.$1, height: size.$2, fps: 15);
        p.audio.tracks.first.clips.add(AudioClip(assetId: 'song', srcIn: 0, srcOut: 3));
        p.clips.add(VisualClip(kind: ClipKind.image, assetId: 'img', imageDuration: 3));
        return p;
      }

      final settings = VideoExportSettings(width: size.$1, height: size.$2, fps: 15, preset: 'ultrafast', crf: 18);
      final refOut = '${TestMedia.dir.path}/lib_ref_${size.$1}.mp4';
      await r.render(base(), resolver, settings, refOut, music: music);
      final ref = await frames(refOut);
      final failures = <String>[];
      for (final id in vfxLibraryNames.keys) {
        final out = '${TestMedia.dir.path}/lib_${id}_${size.$1}.mp4';
        try {
          await r.render(base()..vfx.add(VfxItem(type: id, intensity: 0.8, reactive: id.startsWith('tex_hearts_red'))), resolver, settings, out, music: music);
          final info = MediaInfo.fromProbe(out, await TestMedia.runner.probeJson(out));
          if ((info.duration - 3).abs() > 0.15) failures.add('$id duration ${info.duration}');
          final f = await frames(out);
          var maxDiff = 0.0;
          const fs = 90 * 160;
          final n = (f.length < ref.length ? f.length : ref.length) ~/ fs;
          for (var k = 0; k < n; k++) {
            var changed = 0;
            for (var j = 0; j < fs; j++) {
              if ((f[k * fs + j] - ref[k * fs + j]).abs() > 16) changed++;
            }
            final d = 100 * changed / fs; // % of visibly changed pixels
            if (d > maxDiff) maxDiff = d;
          }
          if (maxDiff < 0.25) failures.add('$id has no visible effect (max changed $maxDiff %)');
        } catch (e) {
          failures.add('$id: $e');
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    }, timeout: const Timeout(Duration(minutes: 20)));
  }

  test('every intro preset applies, is removable and renders', () async {
    final r = VideoRenderer(TestMedia.runner, Directory('${TestMedia.dir.path}/introwork'), fontsDir);
    final failures = <String>[];
    for (final ip in introPresets) {
      final p = VideoProject(width: 270, height: 480, fps: 15);
      p.audio.tracks.first.clips.add(AudioClip(assetId: 'song', srcIn: 0, srcOut: 3));
      p.clips.add(VisualClip(kind: ClipKind.image, assetId: 'img', imageDuration: 3));
      p.texts.add(TextItem(text: 'x', start: 1, duration: 1));
      final before = p.duration;
      applyIntro(p, ip, 'Zażółć gęślą jaźń');
      if (ip.background.isNotEmpty) {
        expect(p.clips.first.label, introTag);
        expect(p.audio.tracks.first.clips.first.position, greaterThan(0));
        expect(p.texts.firstWhere((t) => t.text == 'x').start, greaterThan(1));
      }
      expect(p.vfx.length, ip.vfx.length);
      // re-applying replaces, never stacks
      applyIntro(p, ip, 'Tytuł');
      expect(p.vfx.length, ip.vfx.length);
      expect(p.texts.where((t) => t.layer == 90).length, ip.subtitle.isEmpty ? 1 : 2);
      final out = '${TestMedia.dir.path}/intro_${ip.id}.mp4';
      try {
        await r.render(p, resolver, VideoExportSettings(width: 270, height: 480, fps: 15, preset: 'ultrafast', crf: 30), out, music: music);
        final info = MediaInfo.fromProbe(out, await TestMedia.runner.probeJson(out));
        if ((info.duration - p.duration).abs() > 0.15) failures.add('${ip.id} duration ${info.duration} vs ${p.duration}');
      } catch (e) {
        failures.add('${ip.id}: $e');
      }
      removeIntro(p);
      expect(p.duration, closeTo(before, 1e-6), reason: ip.id);
      expect(p.texts.firstWhere((t) => t.text == 'x').start, closeTo(1, 1e-9));
      expect(p.vfx, isEmpty);
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 20)));
}
