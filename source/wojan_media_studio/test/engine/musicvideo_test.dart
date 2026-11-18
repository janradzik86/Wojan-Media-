import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wojan_media_studio/engine/dsp/analysis.dart';
import 'package:wojan_media_studio/engine/dsp/pcm.dart';
import 'package:wojan_media_studio/engine/export/video_export.dart';
import 'package:wojan_media_studio/engine/ffmpeg/probe.dart';
import 'package:wojan_media_studio/engine/musicvideo/auto.dart';
import 'package:wojan_media_studio/engine/musicvideo/styles.dart';
import 'package:wojan_media_studio/engine/project/asset.dart';
import 'package:wojan_media_studio/engine/video/compiler.dart';

import 'test_media.dart';

void main() {
  final assets = <String, MediaAsset>{};
  late AudioAnalysis a;
  final fontsDir = '${Directory.current.path}/assets/fonts';

  Future<MediaAsset> add(String id, String path) async {
    final info = MediaInfo.fromProbe(path, await TestMedia.runner.probeJson(path));
    return assets[id] = MediaAsset(id: id, name: id, kind: info.kind, sha256: '', size: info.sizeBytes, relPath: '', duration: info.duration, width: info.width, height: info.height, hasAudio: info.hasAudio, localPath: path);
  }

  setUpAll(() async {
    await TestMedia.init();
    await add('song', await TestMedia.clickTrack(128, 24));
    await add('i1', await TestMedia.image('i1', 'red'));
    await add('i2', await TestMedia.image('i2', 'blue', w: 1080, h: 1920));
    await add('v1', await TestMedia.video('v1', 3));
    a = AudioAnalyzer.analyze(await PcmDecoder(TestMedia.runner, TestMedia.dir).decode(assets['song']!.localPath!));
  });

  test('cuts land exactly on detected beats', () {
    final r = MusicVideoRequest(music: assets['song']!, visuals: [assets['i1']!, assets['i2']!, assets['v1']!], style: styleById('hiphop'), mode: MusicVideoMode.beatSync);
    final p = MusicVideoGenerator().generate(r, a);
    final starts = p.clipStarts();
    expect(p.clips.length, greaterThan(8));
    for (var i = 1; i < starts.length; i++) {
      final nearest = a.beats.reduce((x, y) => (x - starts[i]).abs() < (y - starts[i]).abs() ? x : y);
      expect((nearest - starts[i]).abs(), lessThan(1e-6), reason: 'clip $i at ${starts[i]}');
    }
    expect(p.visualDuration, closeTo(a.duration, 1e-6));
  });

  test('every mode × sample of styles renders a real file', () async {
    final r = VideoRenderer(TestMedia.runner, Directory('${TestMedia.dir.path}/mv'), fontsDir);
    const lyrics = 'Pierwszy wers piosenki\nDrugi wers – żółć i łąka\n\n[Refren]\nTrzeci wers śpiewany głośno\nCzwarty wers na koniec';
    var n = 0;
    for (final mode in MusicVideoMode.values) {
      final style = factoryStyles[n++ % factoryStyles.length];
      final req = MusicVideoRequest(
        music: assets['song']!,
        visuals: [assets['i1']!, assets['i2']!, assets['v1']!],
        extraTracks: mode == MusicVideoMode.album ? [assets['song']!] : const [],
        lyrics: lyrics,
        title: 'Tytuł utworu',
        artist: 'WoJan',
        style: style,
        mode: mode,
        width: 1080,
        height: 1920,
        promoLength: 10,
        logo: assets['i1'],
      );
      final p = MusicVideoGenerator().generate(req, a);
      final out = '${TestMedia.dir.path}/mv_${mode.name}.mp4';
      await r.render(p, MapAssetResolver(assets, TestMedia.dir.path), VideoExportSettings(width: 270, height: 480, fps: 15, preset: 'ultrafast', crf: 30), out, music: a);
      final info = MediaInfo.fromProbe(out, await TestMedia.runner.probeJson(out));
      expect(info.duration, closeTo(p.duration, 0.15), reason: '${mode.name}/${style.id}');
      expect(info.hasAudio, isTrue);
    }
  }, timeout: const Timeout(Duration(minutes: 20)));

  test('all 20 styles generate valid projects and render', () async {
    final r = VideoRenderer(TestMedia.runner, Directory('${TestMedia.dir.path}/mv'), fontsDir);
    expect(factoryStyles.length, 20);
    for (final st in factoryStyles) {
      final p = MusicVideoGenerator().generate(MusicVideoRequest(music: assets['song']!, visuals: [assets['i1']!, assets['i2']!], style: st, mode: MusicVideoMode.dynamic, title: st.name, promoLength: 6), a);
      p.fixedDuration = 6;
      final out = '${TestMedia.dir.path}/style_${st.id}.mp4';
      await r.render(p, MapAssetResolver(assets, TestMedia.dir.path), VideoExportSettings(width: 180, height: 320, fps: 12, preset: 'ultrafast', crf: 32), out, music: a);
      expect(File(out).lengthSync(), greaterThan(1000), reason: st.id);
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
