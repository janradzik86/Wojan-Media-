import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wojan_media_studio/engine/export/video_export.dart';
import 'package:wojan_media_studio/engine/ffmpeg/probe.dart';
import 'package:wojan_media_studio/engine/ffmpeg/runner.dart';
import 'package:wojan_media_studio/engine/project/asset.dart';
import 'package:wojan_media_studio/engine/video/compiler.dart';
import 'package:wojan_media_studio/engine/video/model.dart';

import 'test_media.dart';

/// Simulates a device where some encoders are missing / fail and where the
/// encoder list arrives truncated in chunks (Android FFmpegKit behaviour).
class FlakyEncoderRunner extends MediaRunner {
  final ProcessRunner inner = ProcessRunner();
  final Set<String> broken;
  final bool truncateList;
  FlakyEncoderRunner(this.broken, {this.truncateList = false});
  @override
  Future<RunResult> ffmpeg(List<String> args, {ProgressCb? onProgress, CancelToken? cancel}) async {
    final r = await inner.ffmpeg(args, onProgress: onProgress, cancel: cancel);
    if (args.contains('-encoders') && truncateList) return RunResult(0, r.log.substring(0, min(600, r.log.length)));
    final i = args.indexOf('-c:v');
    if (i >= 0 && broken.contains(args[i + 1])) return RunResult(1, 'Unknown encoder ${args[i + 1]}');
    return r;
  }

  @override
  Future<RunResult> ffprobe(List<String> args) => inner.ffprobe(args);
}

void main() {
  setUpAll(() async => TestMedia.init());

  test('candidates are never empty, even with unknown/partial encoder list', () {
    final s = VideoExportSettings();
    for (final avail in [<String>{}, {'aac', 'png'}, {'aac', 'libmp3lame', 'png', 'mjpeg'}]) {
      final c = s.encoderCandidates(avail);
      expect(c, isNotEmpty);
      expect(c, contains('libx264'));
      expect(c.last, 'mpeg4');
    }
    final full = {'libx264', 'h264_mediacodec', 'aac', 'mpeg4', 'png', 'mjpeg', 'libvpx-vp9', 'libx265', 'gif', 'pcm_s16le', 'flac'};
    expect(s.encoderCandidates(full).first, 'h264_mediacodec');
    expect((VideoExportSettings()..encoder = EncoderPreference.software).encoderCandidates(full).first, 'libx264');
  });

  test('encoder list parser tolerates chunked logs', () async {
    final r = await TestMedia.runner.ffmpeg(['-encoders']);
    final whole = parseEncoderList(r.log);
    expect(whole, containsAll(['libx264', 'aac', 'mpeg4']));
    // re-chunk at random positions with extra newlines
    final rnd = Random(1);
    final b = StringBuffer();
    var i = 0;
    while (i < r.log.length) {
      final n = 20 + rnd.nextInt(200);
      b.write(r.log.substring(i, min(r.log.length, i + n)));
      i += n;
    }
    expect(parseEncoderList(b.toString()), containsAll(['libx264', 'aac', 'mpeg4']));
  });

  test('render falls back when hardware and x264 encoders fail (truncated list)', () async {
    final img = await TestMedia.image('fb', 'red');
    final info = MediaInfo.fromProbe(img, await TestMedia.runner.probeJson(img));
    final assets = {'i': MediaAsset(id: 'i', name: 'i', kind: info.kind, sha256: '', size: 0, relPath: '', localPath: img)};
    final p = VideoProject(width: 320, height: 568, fps: 15)..clips.add(VisualClip(kind: ClipKind.image, assetId: 'i', imageDuration: 2));
    final r = VideoRenderer(FlakyEncoderRunner({'h264_mediacodec', 'libx264', 'libopenh264'}, truncateList: true), Directory('${TestMedia.dir.path}/fbw'), '${Directory.current.path}/assets/fonts');
    final out = '${TestMedia.dir.path}/fallback.mp4';
    final enc = await r.render(p, MapAssetResolver(assets, ''), VideoExportSettings(width: 320, height: 568, fps: 15, preset: 'ultrafast'), out);
    expect(enc, 'mpeg4');
    final o = MediaInfo.fromProbe(out, await TestMedia.runner.probeJson(out));
    expect(o.duration, closeTo(2, 0.1));
    // normal device: libx264 used
    final r2 = VideoRenderer(FlakyEncoderRunner({'h264_mediacodec'}), Directory('${TestMedia.dir.path}/fbw'), '${Directory.current.path}/assets/fonts');
    expect(await r2.render(p, MapAssetResolver(assets, ''), VideoExportSettings(width: 320, height: 568, fps: 15, preset: 'ultrafast'), out), anyOf('libx264', 'h264_nvenc', 'h264_qsv', 'h264_amf', 'h264_mf'));
  });
}
