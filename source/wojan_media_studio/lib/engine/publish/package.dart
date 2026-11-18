import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

import '../export/audio_formats.dart';
import '../ffmpeg/runner.dart';
import '../lyrics/lyrics.dart';
import '../util/hash.dart';
import '../util/json_util.dart';

/// Builds a complete publication package:
/// Teledysk.mp4, Audio.mp3, Okladka.png, Miniatura.jpg, Opis.txt,
/// Hashtagi.txt, Napisy.srt, Metadane.json (+ optional ZIP).
class PublicationPackager {
  final MediaRunner runner;
  PublicationPackager(this.runner);

  Future<Directory> build({
    required String videoPath,
    required String outDir,
    required String title,
    String description = '',
    List<String> hashtags = const [],
    LyricsTrack? lyrics,
    String? coverImage,
    double thumbnailAt = -1,
    Map<String, dynamic> extraMeta = const {},
    bool zip = false,
  }) async {
    final dir = Directory(outDir);
    await dir.create(recursive: true);
    final video = File('${dir.path}/Teledysk.mp4');
    if (File(videoPath).absolute.path != video.absolute.path) await File(videoPath).copy(video.path);
    // audio
    await runner.run(['-i', video.path, '-vn', ...AudioExportSettings(format: AudioFormat.mp3, bitrateKbps: 320).codecArgs(), '${dir.path}/Audio.mp3'], what: 'Nie udało się wyodrębnić audio');
    // thumbnail (frame) & cover
    final probe = await runner.probeJson(video.path);
    final dur = jd(jm(probe['format'])['duration']);
    final t = thumbnailAt >= 0 ? thumbnailAt : dur * 0.33;
    await runner.run(['-ss', fsec(t), '-i', video.path, '-frames:v', '1', '-q:v', '2', '-update', '1', '${dir.path}/Miniatura.jpg']);
    if (coverImage != null) {
      await runner.run(['-i', coverImage, '-frames:v', '1', '-update', '1', '${dir.path}/Okladka.png']);
    } else {
      await runner.run(['-ss', fsec(t), '-i', video.path, '-frames:v', '1', '-update', '1', '${dir.path}/Okladka.png']);
    }
    await File('${dir.path}/Opis.txt').writeAsString('$title\n\n$description\n');
    await File('${dir.path}/Hashtagi.txt').writeAsString(hashtags.join(' '));
    if (lyrics != null && lyrics.lines.any((l) => l.timed)) {
      await File('${dir.path}/Napisy.srt').writeAsString(lyrics.toSrt());
    }
    final meta = {
      'title': title,
      'description': description,
      'hashtags': hashtags,
      'duration': dur,
      'video': {'file': 'Teledysk.mp4', 'sha256': await sha256File(video), 'size': video.lengthSync()},
      'createdWith': 'WoJan Media Studio',
      'created': DateTime.now().toUtc().toIso8601String(),
      ...extraMeta,
    };
    await File('${dir.path}/Metadane.json').writeAsString(const JsonEncoder.withIndent('  ').convert(meta));
    if (zip) {
      final enc = ZipFileEncoder()..create('${dir.path}.zip');
      for (final f in dir.listSync().whereType<File>()) {
        final isMedia = f.path.endsWith('.mp4') || f.path.endsWith('.mp3') || f.path.endsWith('.jpg') || f.path.endsWith('.png');
        await enc.addFile(f, f.uri.pathSegments.last, isMedia ? ZipFileEncoder.store : ZipFileEncoder.gzip);
      }
      await enc.close();
    }
    return dir;
  }
}
