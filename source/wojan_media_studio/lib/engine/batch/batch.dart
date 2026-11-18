import '../dsp/analysis.dart';
import '../export/video_export.dart';
import '../musicvideo/auto.dart';
import '../musicvideo/styles.dart';
import '../project/asset.dart';
import '../publish/platforms.dart';
import '../video/model.dart';

/// One item of a batch music-video production.
class BatchItem {
  final MediaAsset song;
  final List<MediaAsset> covers;
  final String title, artist;
  final String? lyrics;
  BatchItem({required this.song, required this.covers, this.title = '', this.artist = '', this.lyrics});
}

class BatchOutput {
  final BatchItem item;
  final VideoProject project;
  final PlatformProfile? platform;
  final VideoExportSettings settings;
  final String fileName;
  BatchOutput(this.item, this.project, this.platform, this.settings, this.fileName);
}

/// Plans a batch: every song × every requested platform/resolution with a
/// shared style template; songs get their matching covers (substitution).
class BatchPlanner {
  static List<BatchOutput> plan({
    required List<BatchItem> items,
    required Map<String, AudioAnalysis> analyses, // by song asset id
    required StyleTemplate style,
    required MusicVideoMode mode,
    required List<PlatformProfile> platforms,
    List<int> extraShortSides = const [],
  }) {
    final out = <BatchOutput>[];
    for (final it in items) {
      final a = analyses[it.song.id]!;
      final targets = <(PlatformProfile?, int, int)>[
        for (final p in platforms) (p, p.width, p.height),
        for (final s in extraShortSides) (null, (s * 16 / 9).round() ~/ 2 * 2, s),
      ];
      if (targets.isEmpty) targets.add((null, 1080, 1920));
      for (final (p, w, h) in targets) {
        final req = MusicVideoRequest(music: it.song, visuals: it.covers, title: it.title, artist: it.artist, lyrics: it.lyrics, style: style, mode: mode, width: w, height: h);
        final proj = MusicVideoGenerator().generate(req, a);
        final s = p?.exportSettings() ?? VideoExportSettings(width: w, height: h);
        final safe = (it.title.isEmpty ? it.song.name : it.title).replaceAll(RegExp(r'[^\p{L}\p{N}\-_ ]', unicode: true), '').trim().replaceAll(' ', '_');
        out.add(BatchOutput(it, proj, p, s, '${safe}_${p?.id ?? '${h}p'}.${s.extension}'));
      }
    }
    return out;
  }

  /// Pairs songs with covers by matching file-name stems (e.g. `song1.mp3`
  /// ↔ `song1.jpg`), otherwise in order.
  static List<BatchItem> pair(List<MediaAsset> songs, List<MediaAsset> covers) {
    String stem(String n) => n.contains('.') ? n.substring(0, n.lastIndexOf('.')).toLowerCase() : n.toLowerCase();
    final used = <MediaAsset>{};
    final out = <BatchItem>[];
    for (var i = 0; i < songs.length; i++) {
      final s = songs[i];
      var c = covers.where((c) => stem(c.name) == stem(s.name)).firstOrNull;
      c ??= covers.where((c) => !used.contains(c)).firstOrNull ?? (covers.isEmpty ? null : covers[i % covers.length]);
      if (c != null) used.add(c);
      out.add(BatchItem(song: s, covers: c == null ? [] : [c], title: stem(s.name)));
    }
    return out;
  }
}
