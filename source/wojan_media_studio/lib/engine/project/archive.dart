import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

import 'format.dart';

/// Validates entry names of untrusted archives (path traversal, absolute
/// paths, drive letters, unexpected files).
class SafeArchive {
  static final _allowed = [
    RegExp(r'^project\.json$'),
    RegExp(r'^thumb\.(jpg|png)$'),
    RegExp(r'^media/[a-f0-9]{64}\.[a-z0-9]{1,5}$'),
    RegExp(r'^history/[a-zA-Z0-9\-]{8,64}\.json$'),
  ];

  static bool isSafeName(String name) {
    if (name.isEmpty || name.length > 200) return false;
    if (name.startsWith('/') || name.startsWith('\\')) return false;
    if (RegExp(r'^[a-zA-Z]:').hasMatch(name)) return false;
    if (name.contains('\\')) return false;
    final parts = name.split('/');
    if (parts.any((p) => p == '..' || p == '.' || p.isEmpty)) return false;
    return _allowed.any((r) => r.hasMatch(name));
  }

  /// Total uncompressed size guard (zip bomb protection).
  static const maxTotalBytes = 50 * 1024 * 1024 * 1024; // 50 GB
}

/// Exports/imports portable `.wojanmedia` packages.
class ProjectArchiver {
  /// Writes a package containing the project and optionally its media.
  static Future<void> export(ProjectDoc doc, String outPath, {required String Function(String relPath) resolveMedia, bool includeMedia = true, String? thumbPath}) async {
    final enc = ZipFileEncoder();
    enc.create(outPath);
    try {
      final json = utf8.encode(doc.encode());
      enc.addArchiveFile(ArchiveFile('project.json', json.length, json));
      if (thumbPath != null && File(thumbPath).existsSync()) {
        await enc.addFile(File(thumbPath), 'thumb.jpg');
      }
      if (includeMedia) {
        final done = <String>{};
        for (final a in doc.assets.values) {
          if (!done.add(a.relPath)) continue;
          final f = File(resolveMedia(a.relPath));
          if (!f.existsSync()) continue;
          if (!SafeArchive.isSafeName(a.relPath)) continue;
          await enc.addFile(f, a.relPath, ZipFileEncoder.store); // media already compressed
        }
      }
    } finally {
      await enc.close();
    }
  }

  /// Reads only project.json (fast preview, no extraction).
  static ProjectDoc readProject(String path) {
    final input = InputFileStream(path);
    try {
      final arc = ZipDecoder().decodeStream(input);
      final f = arc.findFile('project.json');
      if (f == null) throw ProjectFormatException('Archiwum nie zawiera project.json');
      return ProjectDoc.decode(utf8.decode(f.content as List<int>));
    } finally {
      input.closeSync();
    }
  }

  /// Safely extracts media into [mediaDir] (content-addressed, verified by
  /// [verify] – e.g. SHA-256 check) and returns the project.
  static Future<ProjectDoc> import(String path, String mediaDir, {Future<bool> Function(File f, String expectedSha)? verify}) async {
    final input = InputFileStream(path);
    try {
      final arc = ZipDecoder().decodeStream(input);
      var total = 0;
      for (final e in arc.files) {
        if (!e.isFile) continue;
        if (!SafeArchive.isSafeName(e.name)) {
          throw ProjectFormatException('Niebezpieczna lub nieoczekiwana ścieżka w archiwum: ${e.name}');
        }
        total += e.size;
        if (total > SafeArchive.maxTotalBytes) throw ProjectFormatException('Archiwum jest zbyt duże');
      }
      final pj = arc.findFile('project.json');
      if (pj == null) throw ProjectFormatException('Archiwum nie zawiera project.json');
      final doc = ProjectDoc.decode(utf8.decode(pj.content as List<int>));
      await Directory(mediaDir).create(recursive: true);
      for (final e in arc.files) {
        if (!e.isFile || !e.name.startsWith('media/')) continue;
        final name = e.name.substring(6);
        final target = File('$mediaDir/$name');
        if (target.existsSync()) continue; // dedupe
        final tmp = File('${target.path}.part');
        final out = OutputFileStream(tmp.path);
        e.writeContent(out);
        await out.close();
        final sha = name.split('.').first;
        if (verify != null && !await verify(tmp, sha)) {
          await tmp.delete();
          throw ProjectFormatException('Suma kontrolna pliku $name nie zgadza się – archiwum uszkodzone');
        }
        await tmp.rename(target.path);
      }
      return doc;
    } finally {
      input.closeSync();
    }
  }
}
