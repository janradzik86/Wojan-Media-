import 'package:flutter_test/flutter_test.dart';
import 'package:wojan_media_studio/engine/dsp/analysis.dart';
import 'package:wojan_media_studio/engine/dsp/pcm.dart';

import 'test_media.dart';

void main() {
  setUpAll(() async => TestMedia.init());

  for (final bpm in [90.0, 128.0, 150.0]) {
    test('detects BPM $bpm on real decoded MP3', () async {
      final f = await TestMedia.clickTrack(bpm, 20);
      final pcm = await PcmDecoder(TestMedia.runner, TestMedia.dir).decode(f);
      expect(pcm.duration, closeTo(20, 0.2));
      final a = AudioAnalyzer.analyze(pcm);
      // ignore: avoid_print
      print('bpm=$bpm detected=${a.bpm.toStringAsFixed(2)} beats=${a.beats.length} onsets=${a.onsets.length} conf=${a.bpmConfidence.toStringAsFixed(2)}');
      expect(a.bpm, closeTo(bpm, bpm * 0.03));
      final expectedBeats = 20 * bpm / 60;
      expect(a.beats.length, closeTo(expectedBeats, expectedBeats * 0.12));
      // beat phase: beats should be within 40ms of true click positions
      final period = 60 / bpm;
      var good = 0;
      for (final b in a.beats) {
        final ph = b % period;
        if (ph < 0.05 || period - ph < 0.05) good++;
      }
      expect(good / a.beats.length, greaterThan(0.85));
      expect(a.onsets.length, greaterThan(expectedBeats * 0.7));
    });
  }

  test('peaks/clipping', () async {
    final f = await TestMedia.tone(440, 2, vol: 12.0);
    final pcm = await PcmDecoder(TestMedia.runner, TestMedia.dir).decode(f);
    final a = AudioAnalyzer.analyze(pcm);
    expect(a.clippedSamples, greaterThan(100));
    final p = AudioAnalyzer.waveformPeaks(pcm.samples, 100);
    expect(p.length, 200);
  });
}
