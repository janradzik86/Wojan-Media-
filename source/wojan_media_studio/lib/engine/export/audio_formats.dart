import '../util/json_util.dart';

/// Audio output formats with the encoder arguments used.
enum AudioFormat { mp3, wav, flac, aac, m4a, ogg, opus, wma, aiff }

class AudioExportSettings {
  AudioFormat format;
  int bitrateKbps;
  int sampleRate;
  int channels;
  int wavBits; // 16/24/32
  AudioExportSettings({this.format = AudioFormat.mp3, this.bitrateKbps = 192, this.sampleRate = 44100, this.channels = 2, this.wavBits = 16});

  String get extension {
    switch (format) {
      case AudioFormat.aac:
        return 'aac';
      case AudioFormat.m4a:
        return 'm4a';
      default:
        return format.name;
    }
  }

  bool get lossless => format == AudioFormat.wav || format == AudioFormat.flac || format == AudioFormat.aiff;

  List<String> codecArgs() {
    final common = ['-ar', '$sampleRate', '-ac', '$channels'];
    switch (format) {
      case AudioFormat.mp3:
        return ['-c:a', 'libmp3lame', '-b:a', '${bitrateKbps}k', ...common];
      case AudioFormat.wav:
        return ['-c:a', wavBits == 24 ? 'pcm_s24le' : wavBits == 32 ? 'pcm_f32le' : 'pcm_s16le', ...common];
      case AudioFormat.aiff:
        return ['-c:a', wavBits == 24 ? 'pcm_s24be' : 'pcm_s16be', ...common];
      case AudioFormat.flac:
        return ['-c:a', 'flac', '-compression_level', '5', ...common];
      case AudioFormat.aac:
        return ['-c:a', 'aac', '-b:a', '${bitrateKbps}k', '-f', 'adts', ...common];
      case AudioFormat.m4a:
        return ['-c:a', 'aac', '-b:a', '${bitrateKbps}k', '-movflags', '+faststart', ...common];
      case AudioFormat.ogg:
        return ['-c:a', 'libvorbis', '-b:a', '${bitrateKbps}k', ...common];
      case AudioFormat.opus:
        // Opus only supports 48k internally; ffmpeg resamples.
        return ['-c:a', 'libopus', '-b:a', '${bitrateKbps}k', '-ar', '48000', '-ac', '$channels'];
      case AudioFormat.wma:
        return ['-c:a', 'wmav2', '-b:a', '${bitrateKbps}k', ...common];
    }
  }

  /// Estimated output size in bytes for [seconds].
  int estimateSize(double seconds) {
    if (format == AudioFormat.wav || format == AudioFormat.aiff) {
      return (seconds * sampleRate * channels * (wavBits / 8)).round() + 44;
    }
    if (format == AudioFormat.flac) return (seconds * sampleRate * channels * 2 * 0.6).round();
    return (seconds * bitrateKbps * 1000 / 8).round();
  }

  Map<String, dynamic> toJson() => {'format': format.name, 'bitrate': bitrateKbps, 'sampleRate': sampleRate, 'channels': channels, 'wavBits': wavBits};
  factory AudioExportSettings.fromJson(Map<String, dynamic> j) => AudioExportSettings(
        format: AudioFormat.values.firstWhere((e) => e.name == j['format'], orElse: () => AudioFormat.mp3),
        bitrateKbps: ji(j['bitrate'], 192),
        sampleRate: ji(j['sampleRate'], 44100),
        channels: ji(j['channels'], 2),
        wavBits: ji(j['wavBits'], 16),
      );

  static AudioFormat? formatFromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'mp3':
        return AudioFormat.mp3;
      case 'wav':
        return AudioFormat.wav;
      case 'flac':
        return AudioFormat.flac;
      case 'aac':
        return AudioFormat.aac;
      case 'm4a':
        return AudioFormat.m4a;
      case 'ogg':
        return AudioFormat.ogg;
      case 'opus':
        return AudioFormat.opus;
      case 'wma':
        return AudioFormat.wma;
      case 'aiff':
      case 'aif':
        return AudioFormat.aiff;
    }
    return null;
  }
}
