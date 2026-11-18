import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wojan_media_studio/engine/audio/audio_compiler.dart';
import 'package:wojan_media_studio/engine/audio/audio_project.dart';
import 'package:wojan_media_studio/engine/audio/effects.dart';
import 'package:wojan_media_studio/engine/dsp/analysis.dart';
import 'package:wojan_media_studio/engine/dsp/pcm.dart';
import 'package:wojan_media_studio/engine/export/audio_formats.dart';
import 'package:wojan_media_studio/engine/ffmpeg/probe.dart';
import 'package:wojan_media_studio/engine/ffmpeg/runner.dart';
import 'package:wojan_media_studio/engine/project/asset.dart';

import 'test_media.dart';

void main() {
  late Map<String, MediaAsset> assets;
  late MapAssetResolver resolver;
  late Prober prober;

  setUpAll(() async {
    await TestMedia.init();
    prober = Prober(TestMedia.runner);
    final song = await TestMedia.clickTrack(120, 30); // MP3
    final pad = await TestMedia.tone(220, 20, name: 'pad', ext: 'flac');
    final voice = await TestMedia.tone(880, 6, name: 'voice', ext: 'ogg');
    assets = {};
    for (final e in {'song': song, 'pad': pad, 'voice': voice}.entries) {
      final info = await prober.probe(e.value);
      assets[e.key] = MediaAsset(id: e.key, name: e.key, kind: info.kind, sha256: '', size: info.sizeBytes, relPath: '', duration: info.duration, localPath: e.value);
    }
    resolver = MapAssetResolver(assets, TestMedia.dir.path);
  });

  test('mandatory audio scenario: trim, cut, fades, tempo, volume, mix, export', () async {
    final p = AudioProject();
    final t1 = p.tracks.first;
    p.appendAsset(t1.id, 'song', assets['song']!.duration);
    expect(p.duration, closeTo(30, 0.1));
    // 1. trim to 2s..26s  -> 24s
    p.trimTo(t1.id, 2, 26);
    expect(p.duration, closeTo(24, 0.01));
    // 2. delete 10..14 -> 20s
    p.deleteRange(t1.id, 10, 14);
    expect(p.duration, closeTo(20, 0.01));
    expect(t1.clips.length, 2);
    // 3. fades
    t1.clips.first.fadeIn = 2;
    t1.clips.last.fadeOut = 3;
    // 4. tempo 1.25 on second clip (10s -> 8s)
    t1.clips.last.tempo = 1.25;
    // 5. volume
    t1.gainDb = -3;
    // 6. mix: pad track + voice track with effects
    final t2 = p.addTrack('Pad');
    final pc = p.appendAsset(t2.id, 'pad', assets['pad']!.duration);
    pc.gainDb = -6;
    pc.effects.add(AudioEffect(AudioFx.reverb, {'room': 0.6, 'wet': 0.3}));
    final t3 = p.addTrack('Głos');
    final vc = p.appendAsset(t3.id, 'voice', assets['voice']!.duration);
    vc.position = 4;
    vc.effects.addAll([AudioEffect(AudioFx.equalizer, {'b1k': 4}), AudioEffect(AudioFx.compressor), AudioEffect(AudioFx.pitch, {'semitones': -3})]);
    p.masterEffects.add(AudioEffect(AudioFx.limiter));
    final expected = p.duration;
    expect(expected, closeTo(20, 0.01)); // pad is 20s, song now 18s
    final out = '${TestMedia.dir.path}/mix_out.mp3';
    final r = AudioRenderer(TestMedia.runner, Directory('${TestMedia.dir.path}/work'));
    await r.render(p, resolver, out, AudioExportSettings(format: AudioFormat.mp3, bitrateKbps: 192, sampleRate: 44100), metadata: {'title': 'Test miksu', 'artist': 'WoJan'});
    final info = MediaInfo.fromProbe(out, await TestMedia.runner.probeJson(out));
    expect(info.audioCodec, 'mp3');
    expect(info.sampleRate, 44100);
    expect(info.channels, 2);
    expect(info.duration, closeTo(expected, 0.1));
    expect(info.tags['title'], 'Test miksu');
    // "listen": signal must be non-silent in middle and fade in at start
    final pcm = await PcmDecoder(TestMedia.runner, TestMedia.dir).decode(out);
    final a = AudioAnalyzer.analyze(pcm);
    expect(a.rmsDb, greaterThan(-40));
    expect(a.peak, lessThanOrEqualTo(1.0));
    final sr = pcm.sampleRate;
    double rmsAt(double t) {
      var s = 0.0;
      final i0 = (t * sr).round();
      for (var i = i0; i < i0 + sr ~/ 10; i++) {
        s += pcm.samples[i] * pcm.samples[i];
      }
      return s;
    }
    expect(rmsAt(0.0), lessThan(rmsAt(5.0))); // fade-in
  });

  test('all effects compile and render (real ffmpeg)', () async {
    for (final fx in AudioFx.values) {
      final p = AudioProject();
      final c = p.appendAsset(p.tracks.first.id, 'voice', assets['voice']!.duration);
      c.effects.add(AudioEffect(fx));
      final out = '${TestMedia.dir.path}/fx_${fx.name}.wav';
      final r = AudioRenderer(TestMedia.runner, Directory('${TestMedia.dir.path}/work'));
      await r.render(p, resolver, out, AudioExportSettings(format: AudioFormat.wav));
      expect(File(out).lengthSync(), greaterThan(1000), reason: fx.name);
    }
  });

  test('all export formats', () async {
    for (final f in AudioFormat.values) {
      final p = AudioProject();
      p.appendAsset(p.tracks.first.id, 'voice', assets['voice']!.duration);
      final s = AudioExportSettings(format: f, bitrateKbps: 128);
      final out = '${TestMedia.dir.path}/fmt_${f.name}.${s.extension}';
      await AudioRenderer(TestMedia.runner, Directory('${TestMedia.dir.path}/work')).render(p, resolver, out, s);
      final info = MediaInfo.fromProbe(out, await TestMedia.runner.probeJson(out));
      expect(info.duration, closeTo(6, 0.15), reason: f.name);
    }
  });

  test('edit ops: split, copy/paste, silence, mute, duplicate, reorder, loops', () async {
    final p = AudioProject();
    final t = p.tracks.first;
    p.appendAsset(t.id, 'song', 30);
    p.splitAt(t.id, 10);
    expect(t.clips.length, 2);
    final cb = p.copyRange(t.id, 5, 15);
    expect(cb.fold<double>(0, (m, c) => m + c.length), closeTo(10, 1e-6));
    p.paste(t.id, 0, cb);
    expect(p.duration, closeTo(40, 1e-6));
    p.insertSilence(t.id, 0, 2);
    expect(p.duration, closeTo(42, 1e-6));
    p.muteRange(t.id, 20, 22);
    expect(t.clips.where((c) => c.muted).fold<double>(0, (m, c) => m + c.length), closeTo(2, 1e-6));
    p.duplicateRange(t.id, 2, 4, times: 2);
    expect(p.duration, closeTo(46, 1e-6));
    final firstId = t.clips.first.id;
    p.reorder(t.id, 0, t.clips.length - 1);
    expect(t.clips.last.id, firstId);
    final p2 = AudioProject();
    final c = p2.appendAsset(p2.tracks.first.id, 'voice', 6);
    c.loops = 3;
    expect(p2.duration, closeTo(18, 1e-6));
    final out = '${TestMedia.dir.path}/loops.wav';
    await AudioRenderer(TestMedia.runner, Directory('${TestMedia.dir.path}/work')).render(p2, resolver, out, AudioExportSettings(format: AudioFormat.wav));
    final info = MediaInfo.fromProbe(out, await TestMedia.runner.probeJson(out));
    expect(info.duration, closeTo(18, 0.05));
    // range export
    final out2 = '${TestMedia.dir.path}/range.wav';
    await AudioRenderer(TestMedia.runner, Directory('${TestMedia.dir.path}/work')).render(p2, resolver, out2, AudioExportSettings(format: AudioFormat.wav), rangeStart: 2, rangeEnd: 7);
    final info2 = MediaInfo.fromProbe(out2, await TestMedia.runner.probeJson(out2));
    expect(info2.duration, closeTo(5, 0.05));
  });

  test('corrupted file gives readable error', () async {
    final bad = File('${TestMedia.dir.path}/bad.mp3')..writeAsStringSync('not audio');
    expect(() => TestMedia.runner.probeJson(bad.path), throwsA(isA<MediaEngineException>()));
  });
}
