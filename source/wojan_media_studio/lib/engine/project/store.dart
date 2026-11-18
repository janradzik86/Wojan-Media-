import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common/utils/utils.dart' as sqlutils;

import '../ffmpeg/probe.dart';
import '../ffmpeg/runner.dart';
import '../util/hash.dart';
import 'archive.dart';
import 'asset.dart';
import 'format.dart';

enum SortBy { modified, created, name, duration, size }

class ProjectSummary {
  final String id, name, type, category, revision;
  final List<String> tags;
  final DateTime created, modified;
  final double duration;
  final int size;
  final bool favorite, archived, trashed;
  final String syncState, renderStatus, publishStatus;
  final String? thumb;
  ProjectSummary.fromRow(Map<String, Object?> r)
      : id = r['id'] as String,
        name = r['name'] as String,
        type = r['type'] as String,
        category = (r['category'] as String?) ?? '',
        revision = (r['revision'] as String?) ?? '',
        tags = ((r['tags'] as String?) ?? '').split(',').where((e) => e.isNotEmpty).toList(),
        created = DateTime.parse(r['created'] as String),
        modified = DateTime.parse(r['modified'] as String),
        duration = (r['duration'] as num?)?.toDouble() ?? 0,
        size = (r['size'] as int?) ?? 0,
        favorite = (r['favorite'] as int? ?? 0) == 1,
        archived = (r['archived'] as int? ?? 0) == 1,
        trashed = (r['trashed'] as int? ?? 0) == 1,
        syncState = (r['sync_state'] as String?) ?? 'local',
        renderStatus = (r['render_status'] as String?) ?? 'none',
        publishStatus = (r['publish_status'] as String?) ?? 'draft',
        thumb = r['thumb'] as String?;
}

/// Local-first project store: files on disk are the source of truth, the
/// SQLite database is a rebuildable index (never synchronised directly).
class ProjectStore {
  final Directory root;
  final DatabaseFactory dbFactory;
  final MediaRunner runner;
  final String deviceId;
  late Database db;
  static const historyLimit = 30;

  ProjectStore({required this.root, required this.dbFactory, required this.runner, required this.deviceId});

  Directory get projectsDir => Directory('${root.path}/projects');
  Directory get mediaDir => Directory('${root.path}/media');
  Directory get cacheDir => Directory('${root.path}/cache');
  Directory get exportsDir => Directory('${root.path}/exports');
  Directory projectDir(String id) => Directory('${projectsDir.path}/$id');
  File projectFile(String id) => File('${projectDir(id).path}/project.json');
  File autosaveFile(String id) => File('${projectDir(id).path}/autosave.json');
  File thumbFile(String id) => File('${projectDir(id).path}/thumb.jpg');

  Future<void> open() async {
    for (final d in [projectsDir, mediaDir, cacheDir, exportsDir]) {
      await d.create(recursive: true);
    }
    db = await dbFactory.openDatabase('${root.path}/library.db',
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, v) async {
            await db.execute('''CREATE TABLE projects(
              id TEXT PRIMARY KEY, name TEXT, type TEXT, category TEXT, tags TEXT,
              created TEXT, modified TEXT, revision TEXT, duration REAL, size INTEGER,
              favorite INTEGER, archived INTEGER, trashed INTEGER, trashed_at TEXT,
              sync_state TEXT, render_status TEXT, publish_status TEXT, thumb TEXT)''');
            await db.execute('''CREATE TABLE media(
              sha256 TEXT PRIMARY KEY, name TEXT, kind TEXT, rel_path TEXT, size INTEGER,
              duration REAL, width INTEGER, height INTEGER, has_audio INTEGER, imported TEXT)''');
          },
        ));
    final n = sqlutils.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM projects')) ?? 0;
    if (n == 0) await rebuildIndex();
  }

  Future<void> close() => db.close();

  /// Rebuilds the index from project files (e.g. after sync or corruption).
  Future<void> rebuildIndex() async {
    if (!projectsDir.existsSync()) return;
    for (final d in projectsDir.listSync().whereType<Directory>()) {
      final f = File('${d.path}/project.json');
      if (!f.existsSync()) continue;
      try {
        await _index(ProjectDoc.decode(await f.readAsString()));
      } catch (_) {/* skip unreadable */}
    }
  }

  int _projectSize(ProjectDoc d) => d.assets.values.fold(0, (s, a) => s + a.size);

  Future<void> _index(ProjectDoc d, {String? syncState}) async {
    final existing = await db.query('projects', columns: ['sync_state'], where: 'id=?', whereArgs: [d.id]);
    await db.insert(
        'projects',
        {
          'id': d.id,
          'name': d.name,
          'type': d.type.name,
          'category': d.category,
          'tags': d.tags.join(','),
          'created': d.created.toIso8601String(),
          'modified': d.modified.toIso8601String(),
          'revision': d.revision,
          'duration': d.duration,
          'size': _projectSize(d),
          'favorite': d.favorite ? 1 : 0,
          'archived': d.archived ? 1 : 0,
          'trashed': d.trashed ? 1 : 0,
          'trashed_at': d.trashedAt?.toIso8601String(),
          'sync_state': syncState ?? (existing.isEmpty ? 'local' : (existing.first['sync_state'] as String? ?? 'local')),
          'render_status': d.renderStatus.name,
          'publish_status': d.publishStatus.name,
          'thumb': thumbFile(d.id).existsSync() ? thumbFile(d.id).path : null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setSyncState(String id, String state) => db.update('projects', {'sync_state': state}, where: 'id=?', whereArgs: [id]);

  // --------------------------------------------------------------- media
  /// Imports a file into the content-addressed media store (deduplicated).
  Future<MediaAsset> importMedia(String path, {String? displayName}) async {
    final src = File(path);
    if (!src.existsSync()) throw MediaEngineException('Plik nie istnieje: $path');
    final sha = await sha256File(src);
    final ext = extOf(path).replaceAll(RegExp(r'[^a-z0-9]'), '');
    final rel = 'media/$sha.${ext.isEmpty ? 'bin' : ext}';
    final dst = File('${root.path}/$rel');
    if (!dst.existsSync()) {
      final tmp = File('${dst.path}.part');
      await src.copy(tmp.path);
      await tmp.rename(dst.path);
    }
    final info = await Prober(runner).probe(dst.path);
    final name = displayName ?? path.split(RegExp(r'[\\/]')).last;
    final asset = MediaAsset(
      id: sha.substring(0, 16),
      name: name,
      kind: info.kind,
      sha256: sha,
      size: info.sizeBytes > 0 ? info.sizeBytes : dst.lengthSync(),
      relPath: rel,
      duration: info.duration,
      width: info.displayWidth,
      height: info.displayHeight,
      hasAudio: info.hasAudio,
    );
    await db.insert(
        'media',
        {
          'sha256': sha,
          'name': name,
          'kind': info.kind.name,
          'rel_path': rel,
          'size': asset.size,
          'duration': info.duration,
          'width': asset.width,
          'height': asset.height,
          'has_audio': info.hasAudio ? 1 : 0,
          'imported': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    return asset;
  }

  Future<List<MediaAsset>> listMedia({MediaKind? kind}) async {
    final rows = await db.query('media', where: kind == null ? null : 'kind=?', whereArgs: kind == null ? null : [kind.name], orderBy: 'imported DESC');
    return rows
        .map((r) => MediaAsset(
              id: (r['sha256'] as String).substring(0, 16),
              name: r['name'] as String,
              kind: MediaKind.values.firstWhere((k) => k.name == r['kind'], orElse: () => MediaKind.unknown),
              sha256: r['sha256'] as String,
              size: r['size'] as int? ?? 0,
              relPath: r['rel_path'] as String,
              duration: (r['duration'] as num?)?.toDouble() ?? 0,
              width: r['width'] as int?,
              height: r['height'] as int?,
              hasAudio: (r['has_audio'] as int? ?? 0) == 1,
            ))
        .toList();
  }

  AssetResolver resolver(ProjectDoc d) => MapAssetResolver(d.assets, root.path);
  String mediaPath(String rel) => '${root.path}/$rel';

  // ------------------------------------------------------------ projects
  Future<ProjectDoc> create(String name, ProjectType type) async {
    final d = ProjectDoc(name: name, type: type, deviceId: deviceId);
    await save(d, bump: false);
    return d;
  }

  /// Atomic save with revision history.
  Future<void> save(ProjectDoc d, {bool bump = true, String? syncState}) async {
    if (bump) d.bumpRevision(deviceId);
    final dir = projectDir(d.id);
    await Directory('${dir.path}/history').create(recursive: true);
    final f = projectFile(d.id);
    final tmp = File('${f.path}.tmp');
    final text = d.encode();
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(f.path);
    await File('${dir.path}/history/${d.revision}.json').writeAsString(text);
    // prune history
    final hist = Directory('${dir.path}/history').listSync().whereType<File>().toList()..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final h in hist.skip(historyLimit)) {
      await h.delete();
    }
    final auto = autosaveFile(d.id);
    if (auto.existsSync()) await auto.delete();
    await _index(d, syncState: syncState ?? 'localChanges');
  }

  /// Lightweight autosave used for crash recovery (does not bump revision).
  Future<void> autosave(ProjectDoc d) async {
    final f = autosaveFile(d.id);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(d.toJson()), flush: true);
    await tmp.rename(f.path);
  }

  /// Returns autosaved state if it is newer than the last explicit save.
  Future<ProjectDoc?> recoverable(String id) async {
    final a = autosaveFile(id), p = projectFile(id);
    if (!a.existsSync()) return null;
    if (p.existsSync() && p.lastModifiedSync().isAfter(a.lastModifiedSync())) return null;
    try {
      return ProjectDoc.decode(await a.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<ProjectDoc> load(String id) async {
    final f = projectFile(id);
    if (!f.existsSync()) throw ProjectFormatException('Projekt $id nie istnieje');
    return ProjectDoc.decode(await f.readAsString());
  }

  Future<List<String>> history(String id) async {
    final d = Directory('${projectDir(id).path}/history');
    if (!d.existsSync()) return [];
    final files = d.listSync().whereType<File>().toList()..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files.map((f) => f.uri.pathSegments.last.replaceAll('.json', '')).toList();
  }

  Future<ProjectDoc> loadRevision(String id, String rev) async => ProjectDoc.decode(await File('${projectDir(id).path}/history/$rev.json').readAsString());

  Future<List<ProjectSummary>> list({String query = '', String? category, String? tag, bool favorites = false, bool archived = false, bool trash = false, SortBy sort = SortBy.modified, bool desc = true}) async {
    final where = <String>['trashed=?'];
    final args = <Object?>[trash ? 1 : 0];
    if (!trash) {
      where.add('archived=?');
      args.add(archived ? 1 : 0);
    }
    if (query.isNotEmpty) {
      where.add('(name LIKE ? OR tags LIKE ? OR category LIKE ?)');
      args.addAll(['%$query%', '%$query%', '%$query%']);
    }
    if (category != null && category.isNotEmpty) {
      where.add('category=?');
      args.add(category);
    }
    if (tag != null && tag.isNotEmpty) {
      where.add("(','||tags||',') LIKE ?");
      args.add('%,$tag,%');
    }
    if (favorites) where.add('favorite=1');
    final col = switch (sort) { SortBy.modified => 'modified', SortBy.created => 'created', SortBy.name => 'name COLLATE NOCASE', SortBy.duration => 'duration', SortBy.size => 'size' };
    final rows = await db.query('projects', where: where.join(' AND '), whereArgs: args, orderBy: '$col ${desc ? 'DESC' : 'ASC'}');
    return rows.map(ProjectSummary.fromRow).toList();
  }

  Future<ProjectDoc> duplicate(String id) async {
    final d = await load(id);
    final copy = ProjectDoc.fromJson({...d.toJson(), 'id': null, 'revision': null, 'parentRevision': null});
    copy.id = ProjectDoc(name: '', type: d.type).id;
    copy.name = '${d.name} (kopia)';
    copy.ancestors = [];
    copy.created = DateTime.now().toUtc();
    await save(copy, bump: false);
    if (thumbFile(id).existsSync()) await thumbFile(id).copy(thumbFile(copy.id).path);
    return copy;
  }

  Future<void> trash(String id) async {
    final d = await load(id);
    d.trashed = true;
    d.trashedAt = DateTime.now().toUtc();
    await save(d);
  }

  Future<void> restore(String id) async {
    final d = await load(id);
    d.trashed = false;
    d.trashedAt = null;
    await save(d);
  }

  /// Permanently deletes project metadata. Media files are NOT deleted here
  /// (they may be shared); use [garbageCollectMedia].
  Future<void> purge(String id) async {
    final dir = projectDir(id);
    if (dir.existsSync()) await dir.delete(recursive: true);
    await db.delete('projects', where: 'id=?', whereArgs: [id]);
  }

  Future<int> emptyTrash({Duration olderThan = Duration.zero}) async {
    final rows = await list(trash: true);
    var n = 0;
    for (final r in rows) {
      final d = await load(r.id);
      if (d.trashedAt == null || DateTime.now().toUtc().difference(d.trashedAt!) >= olderThan) {
        await purge(r.id);
        n++;
      }
    }
    return n;
  }

  /// Removes media no longer referenced by any project (incl. trash).
  Future<int> garbageCollectMedia() async {
    final used = <String>{};
    for (final d in projectsDir.listSync().whereType<Directory>()) {
      final f = File('${d.path}/project.json');
      if (!f.existsSync()) continue;
      final doc = ProjectDoc.decode(f.readAsStringSync());
      used.addAll(doc.assets.values.map((a) => a.relPath));
    }
    var n = 0;
    for (final f in mediaDir.listSync().whereType<File>()) {
      final rel = 'media/${f.uri.pathSegments.last}';
      if (!used.contains(rel) && !f.path.endsWith('.part')) {
        await f.delete();
        await db.delete('media', where: 'rel_path=?', whereArgs: [rel]);
        n++;
      }
    }
    return n;
  }

  /// Generates a project thumbnail from its first visual.
  Future<void> makeThumbnail(ProjectDoc d) async {
    String? src;
    double at = 0;
    final v = d.video;
    if (v != null && v.clips.isNotEmpty && v.clips.first.assetId != null) {
      src = resolver(d).pathOf(v.clips.first.assetId!);
      at = v.clips.first.isVideo ? v.clips.first.srcIn + 0.5 : 0;
    } else {
      final img = d.assets.values.where((a) => a.kind == MediaKind.image).firstOrNull;
      final aud = d.assets.values.where((a) => a.kind == MediaKind.audio).firstOrNull;
      if (img != null) {
        src = resolver(d).pathOf(img.id);
      } else if (aud != null) {
        final out = thumbFile(d.id).path;
        await runner.ffmpeg(['-i', resolver(d).pathOf(aud.id), '-filter_complex', 'aformat=channel_layouts=mono,showwavespic=s=480x270:colors=0x35D0BA', '-frames:v', '1', '-update', '1', out]);
        await _index(d);
        return;
      }
    }
    if (src == null) return;
    await runner.ffmpeg([if (at > 0) ...['-ss', at.toStringAsFixed(2)], '-i', src, '-vf', 'scale=480:-2', '-frames:v', '1', '-update', '1', '-q:v', '4', thumbFile(d.id).path]);
    await _index(d);
  }

  // ------------------------------------------------------------ archives
  Future<void> exportPackage(String id, String outPath, {bool includeMedia = true}) async {
    final d = await load(id);
    await ProjectArchiver.export(d, outPath, resolveMedia: mediaPath, includeMedia: includeMedia, thumbPath: thumbFile(id).path);
  }

  /// Imports a package; if a project with the same id exists, the imported
  /// one is kept as a separate copy (no silent overwrite).
  Future<ProjectDoc> importPackage(String path) async {
    final d = await ProjectArchiver.import(path, mediaDir.path, verify: (f, sha) async => await sha256File(f) == sha);
    if (projectFile(d.id).existsSync()) {
      final existing = await load(d.id);
      if (existing.revision != d.revision) {
        d.id = ProjectDoc(name: '', type: d.type).id;
        d.name = '${d.name} (zaimportowany)';
      }
    }
    for (final a in d.assets.values) {
      final f = File(mediaPath(a.relPath));
      if (f.existsSync()) {
        await db.insert('media', {'sha256': a.sha256, 'name': a.name, 'kind': a.kind.name, 'rel_path': a.relPath, 'size': a.size, 'duration': a.duration, 'width': a.width, 'height': a.height, 'has_audio': a.hasAudio ? 1 : 0, 'imported': DateTime.now().toUtc().toIso8601String()},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    await save(d, bump: false);
    return d;
  }

  /// Media referenced by a project but missing locally (to fetch via sync).
  List<MediaAsset> missingMedia(ProjectDoc d) => d.assets.values.where((a) => !File(mediaPath(a.relPath)).existsSync()).toList();
}
