import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wojan_media_studio/engine/audio/audio_project.dart';
import 'package:wojan_media_studio/engine/dsp/analysis.dart';
import 'package:wojan_media_studio/engine/dsp/pcm.dart';
import 'package:wojan_media_studio/engine/export/video_export.dart';
import 'package:wojan_media_studio/engine/ffmpeg/probe.dart';
import 'package:wojan_media_studio/engine/musicvideo/auto.dart';
import 'package:wojan_media_studio/engine/musicvideo/styles.dart';
import 'package:wojan_media_studio/engine/project/asset.dart';
import 'package:wojan_media_studio/engine/video/compiler.dart';
import 'package:wojan_media_studio/engine/video/model.dart';

import 'test_media.dart';

void main() {
  final assets = <String, MediaAsset>{};
  Future<MediaAsset> add(String id, String path) async {
    final i = MediaInfo.fromProbe(path, await TestMedia.runner.probeJson(path));
    return assets[id] = MediaAsset(id: id, name: id, kind: i.kind, sha256: '', size: 0, relPath: '', duration: i.duration, width: i.width, height: i.height, hasAudio: i.hasAudio, localPath: path);
  }

  setUpAll(() async {
    await TestMedia.init();
    await add('song', await TestMedia.clickTrack(100, 21));
    await add('photo', await TestMedia.image('photo', 'red', w: 1600, h: 1200)); // landscape photo
    await add('photo2', await TestMedia.image('photo2', 'blue', w: 1200, h: 1600));
    await add('clip', await TestMedia.video('clip', 3));
  });

  VideoProject withSong() => VideoProject(width: 540, height: 960, fps: 15)..audio.tracks.first.clips.add(AudioClip(assetId: 'song', srcIn: 0, srcOut: assets['song']!.duration));

  test('one photo + music → film lasts the whole song, picture not stretched', () async {
    final p = withSong()..clips.add(VisualClip(kind: ClipKind.image, assetId: 'photo', imageDuration: 3, fit: FitMode.stretch));
    expect(p.fitToAudio(), isTrue);
    expect(p.clips.single.imageDuration, closeTo(21, 0.05));
    expect(p.clips.single.fit, FitMode.blurBackground);
    expect(p.duration, closeTo(21, 0.05));
    final out = '${TestMedia.dir.path}/one_photo.mp4';
    await VideoRenderer(TestMedia.runner, Directory('${TestMedia.dir.path}/w'), '${Directory.current.path}/assets/fonts').render(p, MapAssetResolver(assets, ''), VideoExportSettings(width: 540, height: 960, fps: 15, preset: 'ultrafast'), out);
    final i = MediaInfo.fromProbe(out, await TestMedia.runner.probeJson(out));
    expect(i.duration, closeTo(21, 0.15));
    expect(i.width, 540);
    expect(i.height, 960);
    // Undistorted: the 4:3 photo occupies a 4:3 band in the middle (blurred
    // background above/below), i.e. sharp content height ≈ 540*3/4 = 405 px.
    await TestMedia.runner.run(['-ss', '10', '-i', out, '-frames:v', '1', '-update', '1', '${TestMedia.dir.path}/one_photo.png']);
    expect(File('${TestMedia.dir.path}/one_photo.png').existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('several photos + transitions + a video clip are scaled proportionally', () {
    final p = withSong()
      ..clips.addAll([
        VisualClip(kind: ClipKind.image, assetId: 'photo', imageDuration: 2, transition: Transition(type: 'fade', duration: 0.5)),
        VisualClip(kind: ClipKind.video, assetId: 'clip', srcIn: 0, srcOut: 3, transition: Transition(type: 'fade', duration: 0.5)),
        VisualClip(kind: ClipKind.image, assetId: 'photo2', imageDuration: 4),
      ]);
    p.fitToAudio();
    expect(p.visualDuration, closeTo(21, 0.05));
    expect(p.clips[1].duration, closeTo(3, 1e-9), reason: 'video speed unchanged');
    expect(p.clips[2].imageDuration / p.clips[0].imageDuration, closeTo(2, 0.01), reason: 'proportions kept');
  });

  test('only a short video → last clip loops to the song length; no audio → no change', () {
    final p = withSong()..clips.add(VisualClip(kind: ClipKind.video, assetId: 'clip', srcIn: 0, srcOut: 3));
    p.fitToAudio();
    expect(p.clips.single.loopVideo, isTrue);
    expect(p.visualDuration, closeTo(21, 0.05));
    final q = VideoProject()..clips.add(VisualClip(kind: ClipKind.image, assetId: 'photo'));
    expect(q.fitToAudio(), isFalse);
  });

  test('one-click with a single photo makes one continuous shot over the whole song', () async {
    final a = AudioAnalyzer.analyze(await PcmDecoder(TestMedia.runner, TestMedia.dir).decode(assets['song']!.localPath!));
    for (final mode in [MusicVideoMode.dynamic, MusicVideoMode.beatSync, MusicVideoMode.slideshow, MusicVideoMode.lyricVideo]) {
      final v = MusicVideoGenerator().generate(MusicVideoRequest(music: assets['song']!, visuals: [assets['photo']!], style: styleById('slavic_folk'), mode: mode), a);
      expect(v.clips.length, 1, reason: mode.name);
      expect(v.visualDuration, closeTo(a.duration, 0.01), reason: mode.name);
      expect(v.clips.single.fit, FitMode.blurBackground);
    }
  });

  VisualClip photo(String id, {double d = 3}) => VisualClip(kind: ClipKind.image, assetId: id, imageDuration: d, motion: Motion(preset: MotionPreset.kenBurnsIn), fit: FitMode.blurBackground, transition: Transition(type: 'fade', duration: 0.5));

  test('long still is shown as-is (no zoom over the whole song)', () {
    final p = withSong()..clips.add(photo('photo'));
    p.fitToAudio();
    expect(p.clips.single.motion.isStatic, isTrue, reason: 'display time only – picture not zoomed/stretched');
    expect(p.fitAudio, isTrue);
  });

  test('more photos than the song can hold → all shortened, film ends with the audio', () {
    final song = assets['song']!.duration;
    final p = withSong();
    for (var i = 0; i < 20; i++) {
      p.clips.add(photo(i.isEven ? 'photo' : 'photo2', d: 3)); // 20×3 s ≫ 21 s
    }
    expect(p.visualDuration, greaterThan(song + 10));
    p.fitToAudio();
    expect(p.visualDuration, closeTo(song, 0.05), reason: 'pictures fill exactly the audio');
    expect(p.duration, closeTo(song, 0.05));
    final d0 = p.clips.first.imageDuration;
    for (final c in p.clips) {
      expect(c.imageDuration, closeTo(d0, 1e-6), reason: 'equal photos stay equal');
      expect(c.motion.preset, MotionPreset.kenBurnsIn, reason: 'short shots keep their motion');
    }
  });

  test('adding / removing photos after fitting keeps the film = audio length', () {
    final song = assets['song']!.duration;
    final p = withSong()..clips.addAll([photo('photo'), photo('photo2')]);
    p.fitToAudio();
    expect(p.visualDuration, closeTo(song, 0.05));
    // add 5 more → the others get shorter, nothing goes past the audio
    for (var i = 0; i < 5; i++) {
      p.clips.add(photo('photo'));
    }
    p.fitToAudio();
    expect(p.visualDuration, closeTo(song, 0.05));
    expect(p.duration, closeTo(song, 0.05));
    // remove 4 → the remaining get longer and still fill the audio
    p.clips.removeRange(0, 4);
    p.fitToAudio();
    expect(p.visualDuration, closeTo(song, 0.05));
    // round trip of the flag
    expect(VideoProject.fromJson(p.toJson()).fitAudio, isTrue);
  });
}
