import '../ffmpeg/probe.dart';
import '../util/json_util.dart';

/// A media asset referenced by a project. Assets are identified by a stable
/// id and their SHA-256 content hash – never only by an absolute path – so
/// projects can move between Windows and Android.
class MediaAsset {
  final String id;
  String name;
  MediaKind kind;
  String sha256;
  int size;
  double duration;
  int? width, height;
  bool hasAudio;
  /// Path relative to the project's media folder once imported, e.g.
  /// `media/ab12…cd.mp3`. Local-only absolute path cache is kept separately.
  String relPath;
  /// Last known absolute location on this device (cache, not authoritative).
  String? localPath;

  MediaAsset({
    required this.id,
    required this.name,
    required this.kind,
    required this.sha256,
    required this.size,
    required this.relPath,
    this.duration = 0,
    this.width,
    this.height,
    this.localPath,
    this.hasAudio = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'sha256': sha256,
        'size': size,
        'duration': duration,
        'width': width,
        'height': height,
        'hasAudio': hasAudio,
        'relPath': relPath,
      };

  factory MediaAsset.fromJson(Map<String, dynamic> j) => MediaAsset(
        id: js(j['id']),
        name: js(j['name']),
        kind: MediaKind.values.firstWhere((e) => e.name == j['kind'], orElse: () => MediaKind.unknown),
        sha256: js(j['sha256']),
        size: ji(j['size']),
        duration: jd(j['duration']),
        width: j['width'] == null ? null : ji(j['width']),
        height: j['height'] == null ? null : ji(j['height']),
        relPath: js(j['relPath']),
        hasAudio: jb(j['hasAudio']),
      );
}

/// Resolves asset ids to absolute local paths (project media dir + cache).
abstract class AssetResolver {
  String pathOf(String assetId);
  MediaAsset asset(String assetId);
}

class MapAssetResolver implements AssetResolver {
  final Map<String, MediaAsset> assets;
  final String baseDir;
  MapAssetResolver(this.assets, this.baseDir);
  @override
  MediaAsset asset(String id) => assets[id] ?? (throw StateError('Brak materiału $id w projekcie'));
  @override
  String pathOf(String id) {
    final a = asset(id);
    if (a.localPath != null) return a.localPath!;
    return '$baseDir/${a.relPath}';
  }
}
