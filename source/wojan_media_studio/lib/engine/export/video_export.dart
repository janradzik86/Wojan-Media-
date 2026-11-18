import 'dart:math' as math;

import '../util/json_util.dart';

enum VideoContainer { mp4, webm, mov, mkv, gif }
enum VideoCodec { h264, h265, vp9, prores }
enum EncoderPreference { auto, software, hardware }

/// Video export configuration with codec/bitrate/quality/size estimation.
class VideoExportSettings {
  VideoContainer container;
  VideoCodec codec;
  EncoderPreference encoder;
  int width, height;
  double fps;
  int crf; // quality (lower = better), used when bitrateKbps == 0
  int bitrateKbps; // 0 = constant quality
  String preset; // x264/x265 speed preset
  int audioBitrateKbps;
  int audioSampleRate;
  double? rangeStart, rangeEnd;
  int gifWidth;
  double gifFps;

  VideoExportSettings({
    this.container = VideoContainer.mp4,
    this.codec = VideoCodec.h264,
    this.encoder = EncoderPreference.auto,
    this.width = 1080,
    this.height = 1920,
    this.fps = 30,
    this.crf = 20,
    this.bitrateKbps = 0,
    this.preset = 'medium',
    this.audioBitrateKbps = 192,
    this.audioSampleRate = 48000,
    this.rangeStart,
    this.rangeEnd,
    this.gifWidth = 480,
    this.gifFps = 15,
  });

  String get extension => container.name;

  Map<String, dynamic> toJson() => {
        'container': container.name,
        'codec': codec.name,
        'encoder': encoder.name,
        'width': width,
        'height': height,
        'fps': fps,
        'crf': crf,
        'bitrate': bitrateKbps,
        'preset': preset,
        'abitrate': audioBitrateKbps,
        'asr': audioSampleRate,
        'gifWidth': gifWidth,
        'gifFps': gifFps,
      };

  factory VideoExportSettings.fromJson(Map<String, dynamic> j) => VideoExportSettings(
        container: VideoContainer.values.firstWhere((e) => e.name == j['container'], orElse: () => VideoContainer.mp4),
        codec: VideoCodec.values.firstWhere((e) => e.name == j['codec'], orElse: () => VideoCodec.h264),
        encoder: EncoderPreference.values.firstWhere((e) => e.name == j['encoder'], orElse: () => EncoderPreference.auto),
        width: ji(j['width'], 1080),
        height: ji(j['height'], 1920),
        fps: jd(j['fps'], 30),
        crf: ji(j['crf'], 20),
        bitrateKbps: ji(j['bitrate']),
        preset: js(j['preset'], 'medium'),
        audioBitrateKbps: ji(j['abitrate'], 192),
        audioSampleRate: ji(j['asr'], 48000),
        gifWidth: ji(j['gifWidth'], 480),
        gifFps: jd(j['gifFps'], 15),
      );

  VideoExportSettings copy() => VideoExportSettings.fromJson(toJson())
    ..rangeStart = rangeStart
    ..rangeEnd = rangeEnd;

  /// Approximate bitrate (kbps) of constant-quality encodes for estimates.
  int get effectiveVideoKbps {
    if (bitrateKbps > 0) return bitrateKbps;
    final px = width * height * fps;
    // empirical bits-per-pixel for x264 at crf 20 ≈ 0.07, halves every +6 crf
    var bpp = 0.07 * math.pow(2, (20 - crf) / 6).toDouble();
    if (codec == VideoCodec.h265) bpp *= 0.6;
    if (codec == VideoCodec.vp9) bpp *= 0.65;
    if (codec == VideoCodec.prores) bpp = 1.2;
    return (px * bpp / 1000).round();
  }

  int estimateBytes(double seconds) {
    if (container == VideoContainer.gif) {
      return (gifWidth * gifWidth * height / width * gifFps * seconds * 0.12).round();
    }
    return ((effectiveVideoKbps + audioBitrateKbps) * 1000 / 8 * seconds).round();
  }

  /// Encoder name candidates in order of preference.
  List<String> encoderCandidates(Set<String> available) {
    final hw = <String>[];
    switch (codec) {
      case VideoCodec.h264:
        hw.addAll(['h264_mediacodec', 'h264_nvenc', 'h264_qsv', 'h264_amf', 'h264_mf']);
        break;
      case VideoCodec.h265:
        hw.addAll(['hevc_mediacodec', 'hevc_nvenc', 'hevc_qsv', 'hevc_amf', 'hevc_mf']);
        break;
      default:
        break;
    }
    final sw = switch (codec) {
      VideoCodec.h264 => ['libx264', 'libopenh264'],
      VideoCodec.h265 => ['libx265', 'libkvazaar'],
      VideoCodec.vp9 => ['libvpx-vp9'],
      VideoCodec.prores => ['prores_ks', 'prores'],
    };
    // The encoder list may be unknown or incomplete (e.g. truncated logs):
    // then every candidate is tried and the renderer falls back at runtime.
    final known = available.length >= 10;
    bool ok(String e) => !known || available.contains(e);
    final out = <String>[];
    if (encoder != EncoderPreference.software) out.addAll(hw.where(ok));
    if (encoder != EncoderPreference.hardware || out.isEmpty) out.addAll(sw.where(ok));
    // Last resort built into every FFmpeg build (always produces a file).
    final lastResort = switch (codec) {
      VideoCodec.vp9 => ['libvpx', 'mpeg4'],
      VideoCodec.prores => ['mpeg4'],
      _ => ['mpeg4'],
    };
    for (final e in lastResort) {
      if (!out.contains(e)) out.add(e);
    }
    return out;
  }

  List<String> videoArgs(String enc) {
    final rate = bitrateKbps > 0 ? bitrateKbps : effectiveVideoKbps;
    switch (enc) {
      case 'libx264':
        return ['-c:v', 'libx264', '-preset', preset, if (bitrateKbps > 0) ...['-b:v', '${bitrateKbps}k', '-maxrate', '${(bitrateKbps * 1.5).round()}k', '-bufsize', '${bitrateKbps * 2}k'] else ...['-crf', '$crf'], '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-movflags', '+faststart'];
      case 'libx265':
        return ['-c:v', 'libx265', '-preset', preset, if (bitrateKbps > 0) ...['-b:v', '${bitrateKbps}k'] else ...['-crf', '${crf + 4}'], '-pix_fmt', 'yuv420p', '-tag:v', 'hvc1', '-movflags', '+faststart'];
      case 'libkvazaar':
        return ['-c:v', 'libkvazaar', '-b:v', '${rate}k', '-pix_fmt', 'yuv420p', '-tag:v', 'hvc1'];
      case 'libvpx-vp9':
        return ['-c:v', 'libvpx-vp9', if (bitrateKbps > 0) ...['-b:v', '${bitrateKbps}k'] else ...['-crf', '${crf + 12}', '-b:v', '0'], '-row-mt', '1', '-deadline', 'good', '-cpu-used', '4', '-pix_fmt', 'yuv420p'];
      case 'prores_ks':
      case 'prores':
        return ['-c:v', enc, '-profile:v', '2', '-pix_fmt', 'yuv422p10le'];
      case 'libopenh264':
        return ['-c:v', 'libopenh264', '-b:v', '${rate}k', '-pix_fmt', 'yuv420p'];
      case 'mpeg4':
        return ['-c:v', 'mpeg4', '-q:v', '${(crf / 6).round().clamp(2, 8)}', '-pix_fmt', 'yuv420p', if (container == VideoContainer.mp4 || container == VideoContainer.mov) ...['-movflags', '+faststart']];
      case 'libvpx':
        return ['-c:v', 'libvpx', '-b:v', '${rate}k', '-pix_fmt', 'yuv420p'];
      default:
        // hardware encoders: bitrate based
        return ['-c:v', enc, '-b:v', '${rate}k', '-pix_fmt', enc.endsWith('_qsv') ? 'nv12' : 'yuv420p', if (container == VideoContainer.mp4 || container == VideoContainer.mov) ...['-movflags', '+faststart']];
    }
  }

  List<String> audioArgs() {
    switch (container) {
      case VideoContainer.webm:
        return ['-c:a', 'libopus', '-b:a', '${audioBitrateKbps}k', '-ar', '48000'];
      case VideoContainer.mov:
        return ['-c:a', 'aac', '-b:a', '${audioBitrateKbps}k', '-ar', '$audioSampleRate'];
      default:
        return ['-c:a', 'aac', '-b:a', '${audioBitrateKbps}k', '-ar', '$audioSampleRate'];
    }
  }
}

/// Resolution presets.
const resolutionPresets = <String, int>{'360p': 360, '480p': 480, '720p': 720, '1080p': 1080, '1440p': 1440, '4K': 2160};

/// Computes width/height for aspect ratio [aw]:[ah] where the SHORT side
/// equals [shortSide] (even numbers).
(int, int) sizeFor(int aw, int ah, int shortSide) {
  int even(double v) => (v / 2).round() * 2;
  if (aw >= ah) return (even(shortSide * aw / ah), even(shortSide.toDouble()));
  return (even(shortSide.toDouble()), even(shortSide * ah / aw));
}
