import '../util/json_util.dart';
import 'runner.dart';

enum MediaKind { audio, video, image, subtitle, unknown }

const imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif', 'tif', 'tiff', 'avif'};
const videoExtensions = {'mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v', '3gp', 'ts', 'mts', 'flv', 'wmv', 'mpg', 'mpeg'};
const audioExtensions = {'mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg', 'oga', 'opus', 'wma', 'aiff', 'aif', 'amr', 'ac3', 'mka', 'alac', 'ape'};
const subtitleExtensions = {'srt', 'vtt', 'lrc', 'ass', 'ssa'};

String extOf(String path) {
  final i = path.lastIndexOf('.');
  if (i < 0) return '';
  return path.substring(i + 1).toLowerCase();
}

MediaKind guessKind(String path) {
  final e = extOf(path);
  if (imageExtensions.contains(e)) return MediaKind.image;
  if (videoExtensions.contains(e)) return MediaKind.video;
  if (audioExtensions.contains(e)) return MediaKind.audio;
  if (subtitleExtensions.contains(e)) return MediaKind.subtitle;
  return MediaKind.unknown;
}

/// Technical parameters of a media file, from FFprobe.
class MediaInfo {
  final String path;
  final MediaKind kind;
  final double duration;
  final int? width, height;
  final double? fps;
  final int? sampleRate, channels;
  final int? bitrate;
  final String? videoCodec, audioCodec, formatName;
  final int sizeBytes;
  final int rotation;
  final bool hasAudio, hasVideo;
  final Map<String, String> tags;

  MediaInfo({
    required this.path,
    required this.kind,
    required this.duration,
    this.width,
    this.height,
    this.fps,
    this.sampleRate,
    this.channels,
    this.bitrate,
    this.videoCodec,
    this.audioCodec,
    this.formatName,
    this.sizeBytes = 0,
    this.rotation = 0,
    this.hasAudio = false,
    this.hasVideo = false,
    this.tags = const {},
  });

  /// Display dimensions taking rotation metadata into account.
  int? get displayWidth => (rotation % 180 != 0) ? height : width;
  int? get displayHeight => (rotation % 180 != 0) ? width : height;

  static double _rate(String? r) {
    if (r == null || r.isEmpty) return 0;
    final p = r.split('/');
    if (p.length == 2) {
      final d = double.tryParse(p[1]) ?? 0;
      return d == 0 ? 0 : (double.tryParse(p[0]) ?? 0) / d;
    }
    return double.tryParse(r) ?? 0;
  }

  static MediaInfo fromProbe(String path, Map<String, dynamic> j) {
    final fmt = jm(j['format']);
    final streams = jl(j['streams']);
    Map<String, dynamic>? v, a;
    for (final s in streams) {
      final type = s['codec_type'];
      final disp = jm(s['disposition']);
      if (type == 'video' && v == null && ji(disp['attached_pic']) == 0) v = s;
      if (type == 'audio' && a == null) a = s;
    }
    final fmtName = js(fmt['format_name']);
    var kind = guessKind(path);
    final isImageFormat = fmtName.contains('image2') || fmtName.endsWith('_pipe') || fmtName == 'gif' || fmtName == 'webp_pipe';
    if (kind == MediaKind.unknown || kind == MediaKind.audio || kind == MediaKind.video) {
      if (v != null && (isImageFormat && a == null)) {
        kind = MediaKind.image;
      } else if (v != null) {
        kind = MediaKind.video;
      } else if (a != null) {
        kind = MediaKind.audio;
      }
    }
    var dur = jd(fmt['duration']);
    if (dur <= 0 && v != null) dur = jd(v['duration']);
    if (dur <= 0 && a != null) dur = jd(a['duration']);
    var rot = 0;
    if (v != null) {
      final tags = jm(v['tags']);
      rot = ji(tags['rotate']);
      for (final sd in jl(v['side_data_list'])) {
        if (sd.containsKey('rotation')) rot = -ji(sd['rotation']);
      }
      rot = ((rot % 360) + 360) % 360;
    }
    final tags = <String, String>{};
    jm(fmt['tags']).forEach((k, val) => tags[k.toLowerCase()] = '$val');
    return MediaInfo(
      path: path,
      kind: kind,
      duration: dur,
      width: v == null ? null : ji(v['width']),
      height: v == null ? null : ji(v['height']),
      fps: v == null ? null : _rate(js(v['avg_frame_rate'])) > 0 ? _rate(js(v['avg_frame_rate'])) : _rate(js(v['r_frame_rate'])),
      sampleRate: a == null ? null : ji(a['sample_rate']),
      channels: a == null ? null : ji(a['channels']),
      bitrate: ji(fmt['bit_rate']) == 0 ? null : ji(fmt['bit_rate']),
      videoCodec: v == null ? null : js(v['codec_name']),
      audioCodec: a == null ? null : js(a['codec_name']),
      formatName: fmtName,
      sizeBytes: ji(fmt['size']),
      rotation: rot,
      hasAudio: a != null,
      hasVideo: v != null,
      tags: tags,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'kind': kind.name,
        'duration': duration,
        'width': width,
        'height': height,
        'fps': fps,
        'sampleRate': sampleRate,
        'channels': channels,
        'bitrate': bitrate,
        'videoCodec': videoCodec,
        'audioCodec': audioCodec,
        'format': formatName,
        'size': sizeBytes,
        'rotation': rotation,
        'tags': tags,
      };
}

class Prober {
  final MediaRunner runner;
  final _cache = <String, MediaInfo>{};
  Prober(this.runner);

  Future<MediaInfo> probe(String path) async {
    final c = _cache[path];
    if (c != null) return c;
    final j = await runner.probeJson(path);
    final info = MediaInfo.fromProbe(path, j);
    _cache[path] = info;
    return info;
  }

  void invalidate(String path) => _cache.remove(path);
}
