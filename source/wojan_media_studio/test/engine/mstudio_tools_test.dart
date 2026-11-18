import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wojan_media_studio/engine/audio/tools.dart';
import 'package:wojan_media_studio/engine/dsp/pcm.dart';
import 'package:wojan_media_studio/engine/export/audio_formats.dart';
import 'package:wojan_media_studio/engine/ffmpeg/probe.dart';

import 'test_media.dart';

/// Mstudio parity tools: "Niemy" (mute a part), "Szybkość transmisji"
/// (bitrate) and "Wideo: niemy" (strip the sound track).
void main() {
  setUpAll(() async => TestMedia.init());

  double rms(List<double> s, int a, int b) {
    var acc = 0.0;
    for (var i = a; i < b; i++) {
      acc += s[i] * s[i];
    }
    return math.sqrt(acc / math.max(1, b - a));
  }

  test('Niemy silences exactly the chosen range and keeps the length', () async {
    final src = await TestMedia.tone(440, 6, name: 'mute_src', ext: 'wav');
    final out = '${TestMedia.dir.path}/muted.wav';
    await AudioTools(TestMedia.runner).muteRange(src, out, AudioExportSettings(format: AudioFormat.wav), 2, 4);
    final info = MediaInfo.fromProbe(out, await TestMedia.runner.probeJson(out));
    expect(info.duration, closeTo(6, 0.05));
    final pcm = await PcmDecoder(TestMedia.runner, TestMedia.dir).decode(out, sampleRate: 8000);
    final s = pcm.samples;
    expect(rms(s, 8000 * 0, 8000 * 1 + 7000), greaterThan(0.02), reason: 'before range audible');
    expect(rms(s, 8000 * 2 + 400, 8000 * 4 - 400), lessThan(1e-4), reason: 'range silent');
    expect(rms(s, 8000 * 4 + 400, 8000 * 6 - 200), greaterThan(0.02), reason: 'after range audible');
  });

  test('Szybkość transmisji changes the bitrate', () async {
    final src = await TestMedia.tone(440, 8, name: 'br_src', ext: 'wav');
    final t = AudioTools(TestMedia.runner);
    final lo = '${TestMedia.dir.path}/br64.mp3', hi = '${TestMedia.dir.path}/br256.mp3';
    await t.convert(src, lo, AudioExportSettings(format: AudioFormat.mp3, bitrateKbps: 64), effects: const [], metadata: const {});
    await t.convert(src, hi, AudioExportSettings(format: AudioFormat.mp3, bitrateKbps: 256), effects: const [], metadata: const {});
    final a = MediaInfo.fromProbe(lo, await TestMedia.runner.probeJson(lo)), b = MediaInfo.fromProbe(hi, await TestMedia.runner.probeJson(hi));
    expect(b.sizeBytes / a.sizeBytes, closeTo(4, 0.6));
  });

  test('Wideo: niemy removes sound and keeps the picture untouched', () async {
    final v = await TestMedia.video('vm_src', 3);
    final out = '${TestMedia.dir.path}/vm_out.mp4';
    await AudioTools(TestMedia.runner).stripAudio(v, out);
    final i0 = MediaInfo.fromProbe(v, await TestMedia.runner.probeJson(v));
    final i1 = MediaInfo.fromProbe(out, await TestMedia.runner.probeJson(out));
    expect(i0.hasAudio, isTrue);
    expect(i1.hasAudio, isFalse);
    expect(i1.width, i0.width);
    expect(i1.duration, closeTo(i0.duration, 0.1));
  });
}
