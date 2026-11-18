import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../project/format.dart';
import '../project/store.dart';
import '../util/hash.dart';
import 'remote.dart';

/// Per-project sync states shown in the UI.
enum SyncState { synced, localChanges, waiting, uploading, downloading, conflict, noSpace, reauth, error }

const syncStateNames = <SyncState, String>{
  SyncState.synced: 'Zsynchronizowano',
  SyncState.localChanges: 'Zmiany lokalne',
  SyncState.waiting: 'Oczekuje na połączenie',
  SyncState.uploading: 'Wysyłanie',
  SyncState.downloading: 'Pobieranie',
  SyncState.conflict: 'Konflikt (zachowano obie wersje)',
  SyncState.noSpace: 'Brak miejsca',
  SyncState.reauth: 'Wymaga ponownego logowania',
  SyncState.error: 'Błąd',
};

class DeviceInfo {
  final String id, name, platform;
  final DateTime lastSeen;
  final bool revoked;
  DeviceInfo(this.id, this.name, this.platform, this.lastSeen, {this.revoked = false});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'platform': platform, 'lastSeen': lastSeen.toIso8601String(), 'revoked': revoked};
  factory DeviceInfo.fromJson(Map<String, dynamic> j) =>
      DeviceInfo(j['id'] as String, j['name'] as String? ?? '', j['platform'] as String? ?? '', DateTime.tryParse('${j['lastSeen']}') ?? DateTime(2000), revoked: j['revoked'] == true);
}

class SyncReport {
  int uploadedDocs = 0, downloadedDocs = 0, uploadedBlobs = 0, downloadedBlobs = 0, conflicts = 0;
  int bytesUp = 0, bytesDown = 0;
  final List<String> errors = [];
  SyncState overall = SyncState.synced;
  DateTime? finishedAt;
  @override
  String toString() => 'docs ↑$uploadedDocs ↓$downloadedDocs, blobs ↑$uploadedBlobs ↓$downloadedBlobs, conflicts $conflicts, errors ${errors.length}';
}

/// Small synchronised JSON documents (templates, presets, settings, publish
/// history). Stored locally under `kv/<collection>/<key>.json`.
class KvStore {
  final Directory root;
  KvStore(this.root);
  File _f(String col, String key) => File('${root.path}/$col/${key.replaceAll(RegExp(r'[^A-Za-z0-9_\-\.]'), '_')}.json');

  Map<String, dynamic>? getDoc(String col, String key) {
    final f = _f(col, key);
    if (!f.existsSync()) return null;
    return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  }

  Map<String, dynamic>? get(String col, String key) {
    final d = getDoc(col, key);
    if (d == null || d['deleted'] == true) return null;
    return (d['value'] as Map?)?.cast<String, dynamic>();
  }

  /// Saves a new revision of a value.
  void put(String col, String key, Map<String, dynamic> value, {bool deleted = false}) {
    final old = getDoc(col, key);
    final anc = <String>[...((old?['ancestors'] as List?)?.cast<String>() ?? const []), if (old != null) old['rev'] as String];
    _write(col, key, {'key': key, 'rev': const Uuid().v4(), 'ancestors': anc.length > 200 ? anc.sublist(anc.length - 200) : anc, 'deleted': deleted, 'value': value});
  }

  void remove(String col, String key) => put(col, key, {}, deleted: true);

  void _write(String col, String key, Map<String, dynamic> doc) {
    final f = _f(col, key);
    f.parent.createSync(recursive: true);
    final tmp = File('${f.path}.tmp');
    tmp.writeAsStringSync(jsonEncode(doc));
    tmp.renameSync(f.path);
  }

  List<String> keys(String col) {
    final d = Directory('${root.path}/$col');
    if (!d.existsSync()) return [];
    return d.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).map((f) => (jsonDecode(f.readAsStringSync()) as Map)['key'] as String).toList();
  }

  List<Map<String, dynamic>> values(String col) => [for (final k in keys(col)) ?get(col, k)];

  List<String> collections() => root.existsSync() ? root.listSync().whereType<Directory>().map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last).toList() : [];
}

/// Local-first synchronisation engine.
///
/// Remote layout (any [RemoteStore]):
///   blobs/<sha256>.<ext>            immutable, content addressed media
///   revs/<projectId>/<rev>.json     immutable project revisions
///   heads/<projectId>/<device>.json head pointer written only by that device
///   kv/<collection>/<key>/<rev>.json + kvheads/<collection>/<key>/<device>.json
///   devices/<device>.json           authorised devices
///
/// Because every device only ever writes its OWN head file and revisions are
/// immutable, no remote compare-and-swap is required. Ordering is decided by
/// revision ancestry (never by clock time). Concurrent edits (neither
/// revision descends from the other) are resolved by keeping BOTH versions.
class SyncEngine {
  final RemoteStore remote;
  final ProjectStore store;
  final KvStore kv;
  final String deviceId, deviceName, platform;
  final File stateFile;
  Map<String, dynamic> _state = {};
  /// Download policy for media: eagerly fetch blobs up to this size (bytes);
  /// larger files are fetched on demand when the project is opened.
  int eagerDownloadLimit;
  void Function(String projectId, SyncState s)? onState;
  void Function(String msg)? onLog;

  SyncEngine({required this.remote, required this.store, required this.kv, required this.deviceId, required this.deviceName, required this.platform, required this.stateFile, this.eagerDownloadLimit = 64 << 20}) {
    if (stateFile.existsSync()) {
      try {
        _state = jsonDecode(stateFile.readAsStringSync()) as Map<String, dynamic>;
      } catch (_) {}
    }
  }

  DateTime? get lastSuccess => _state['lastSuccess'] == null ? null : DateTime.tryParse(_state['lastSuccess'] as String);

  void _saveState() {
    stateFile.parent.createSync(recursive: true);
    stateFile.writeAsStringSync(jsonEncode(_state));
  }

  Uint8List _bytes(Object o) => Uint8List.fromList(utf8.encode(jsonEncode(o)));
  Map<String, dynamic> _json(Uint8List b) => jsonDecode(utf8.decode(b)) as Map<String, dynamic>;

  void _set(String id, SyncState s) {
    onState?.call(id, s);
    store.setSyncState(id, s.name);
  }

  // ------------------------------------------------------------ devices
  Future<void> registerDevice() async {
    final existing = await _device(deviceId);
    if (existing != null && existing.revoked) throw SyncException(SyncErrorKind.revoked, 'To urządzenie zostało odłączone od konta');
    await remote.writeSmall('devices/$deviceId.json', _bytes(DeviceInfo(deviceId, deviceName, platform, DateTime.now().toUtc()).toJson()));
  }

  Future<DeviceInfo?> _device(String id) async {
    try {
      return DeviceInfo.fromJson(_json(await remote.read('devices/$id.json')));
    } on SyncException catch (e) {
      if (e.kind == SyncErrorKind.notFound) return null;
      rethrow;
    }
  }

  Future<List<DeviceInfo>> devices() async {
    final out = <DeviceInfo>[];
    for (final f in await remote.list('devices/')) {
      try {
        out.add(DeviceInfo.fromJson(_json(await remote.read(f.name))));
      } catch (_) {}
    }
    return out;
  }

  /// Marks a device as revoked; it will refuse to sync from then on.
  Future<void> revokeDevice(String id) async {
    final d = await _device(id);
    if (d == null) return;
    await remote.writeSmall('devices/$id.json', _bytes(DeviceInfo(d.id, d.name, d.platform, d.lastSeen, revoked: true).toJson()));
  }

  // ------------------------------------------------------------ blobs
  Set<String>? _remoteBlobs;
  Future<Set<String>> _blobs() async => _remoteBlobs ??= (await remote.list('blobs/')).map((f) => f.name).toSet();

  String _blobName(String relPath) => 'blobs/${relPath.split('/').last}';

  Future<void> _uploadBlobs(ProjectDoc d, SyncReport rep) async {
    final have = await _blobs();
    for (final a in d.assets.values) {
      final name = _blobName(a.relPath);
      if (have.contains(name)) continue;
      final f = File(store.mediaPath(a.relPath));
      if (!f.existsSync()) continue; // not available on this device
      _set(d.id, SyncState.uploading);
      await withRetry(() => remote.uploadFile(name, f));
      have.add(name);
      rep.uploadedBlobs++;
      rep.bytesUp += f.lengthSync();
    }
  }

  /// Downloads missing media of a project (on demand or eager).
  Future<int> fetchMedia(ProjectDoc d, {bool all = true, void Function(int got, int total)? onProgress, SyncReport? rep}) async {
    var n = 0;
    for (final a in store.missingMedia(d)) {
      if (!all && a.size > eagerDownloadLimit) continue;
      final dest = File(store.mediaPath(a.relPath));
      _set(d.id, SyncState.downloading);
      await withRetry(() => remote.downloadFile(_blobName(a.relPath), dest, onProgress: onProgress));
      if (a.sha256.isNotEmpty && await sha256File(dest) != a.sha256) {
        await dest.delete();
        throw SyncException(SyncErrorKind.other, 'Uszkodzony plik ${a.name} (SHA-256 nie zgadza się)');
      }
      n++;
      rep?.downloadedBlobs++;
      rep?.bytesDown += a.size;
    }
    return n;
  }

  // ------------------------------------------------------------ projects
  Future<ProjectDoc?> _remoteRev(String id, String rev) async {
    try {
      return ProjectDoc.fromJson(_json(await remote.read('revs/$id/$rev.json')));
    } on SyncException catch (e) {
      if (e.kind == SyncErrorKind.notFound) return null;
      rethrow;
    }
  }

  Future<void> _push(ProjectDoc d, SyncReport rep) async {
    await _uploadBlobs(d, rep);
    _set(d.id, SyncState.uploading);
    if (!await remote.exists('revs/${d.id}/${d.revision}.json')) {
      await remote.writeSmall('revs/${d.id}/${d.revision}.json', _bytes(d.toJson()));
      rep.uploadedDocs++;
    }
    await remote.writeSmall('heads/${d.id}/$deviceId.json', _bytes({'rev': d.revision, 'device': deviceId, 'at': DateTime.now().toUtc().toIso8601String()}));
  }

  /// Picks revisions not superseded by any other (ancestry based).
  List<ProjectDoc> _maximal(List<ProjectDoc> docs) {
    final uniq = <String, ProjectDoc>{for (final d in docs) d.revision: d};
    return uniq.values.where((a) => !uniq.values.any((b) => b.revision != a.revision && b.descendsFrom(a.revision))).toList();
  }

  Future<void> syncProject(String id, SyncReport rep) async {
    ProjectDoc? local;
    if (store.projectFile(id).existsSync()) local = await store.load(id);
    final heads = await remote.list('heads/$id/');
    final docs = <ProjectDoc>[];
    final seen = <String>{};
    for (final h in heads) {
      final rev = _json(await remote.read(h.name))['rev'] as String;
      if (!seen.add(rev)) continue;
      if (local != null && rev == local.revision) {
        docs.add(local);
        continue;
      }
      final d = await _remoteRev(id, rev);
      if (d != null) docs.add(d);
    }
    if (local != null) docs.add(local);
    if (docs.isEmpty) return;
    final max = _maximal(docs);
    if (max.length == 1) {
      final winner = max.first;
      if (local == null || winner.revision != local.revision) {
        // fast-forward
        _set(id, SyncState.downloading);
        if (winner.deleted) {
          await store.purge(id);
          rep.downloadedDocs++;
          await remote.writeSmall('heads/$id/$deviceId.json', _bytes({'rev': winner.revision, 'device': deviceId, 'at': DateTime.now().toUtc().toIso8601String()}));
          return;
        }
        await store.save(winner, bump: false, syncState: SyncState.synced.name);
        rep.downloadedDocs++;
        await fetchMedia(winner, all: false, rep: rep);
        await store.makeThumbnail(winner).catchError((_) {});
        await remote.writeSmall('heads/$id/$deviceId.json', _bytes({'rev': winner.revision, 'device': deviceId, 'at': DateTime.now().toUtc().toIso8601String()}));
      } else {
        await _push(local, rep);
      }
      _set(id, store.missingMedia(winner).isEmpty || winner.deleted ? SyncState.synced : SyncState.synced);
      return;
    }
    // Conflict: keep local (or newest) as the main line, save others as copies.
    rep.conflicts++;
    _set(id, SyncState.conflict);
    final main = local != null && max.any((m) => m.revision == local!.revision) ? local : max.first;
    final others = max.where((m) => m.revision != main.revision).toList();
    for (final o in others) {
      final copy = ProjectDoc.fromJson(o.toJson());
      copy.id = const Uuid().v4();
      copy.ancestors = [];
      copy.parentRevision = null;
      copy.revision = const Uuid().v4();
      final when = o.modified.toLocal();
      copy.name = '${o.name} (konflikt – ${o.deviceId.length > 6 ? o.deviceId.substring(0, 6) : o.deviceId}, ${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')})';
      copy.extra['conflictOf'] = id;
      await store.save(copy, bump: false, syncState: SyncState.conflict.name);
      await fetchMedia(copy, all: false, rep: rep);
      await _push(copy, rep);
    }
    // New revision on the main line that supersedes all conflicting heads.
    main.ancestors.addAll(others.map((o) => o.revision));
    main.ancestors.addAll(others.expand((o) => o.ancestors));
    main.ancestors = main.ancestors.toSet().toList();
    main.extra['conflictResolvedAt'] = DateTime.now().toUtc().toIso8601String();
    await store.save(main, syncState: SyncState.conflict.name);
    await _push(main, rep);
  }

  /// Writes a tombstone so other devices also delete the project.
  Future<void> deleteEverywhere(String id) async {
    final d = await store.load(id);
    d.deleted = true;
    d.bumpRevision(deviceId);
    await remote.writeSmall('revs/$id/${d.revision}.json', _bytes(d.toJson()));
    await remote.writeSmall('heads/$id/$deviceId.json', _bytes({'rev': d.revision, 'device': deviceId, 'at': DateTime.now().toUtc().toIso8601String()}));
    await store.purge(id);
  }

  // ------------------------------------------------------------ kv docs
  Future<void> _syncKv(String col, String key, SyncReport rep) async {
    final local = kv.getDoc(col, key);
    final heads = await remote.list('kvheads/$col/$key/');
    final docs = <Map<String, dynamic>>[if (local != null) local];
    for (final h in heads) {
      final rev = _json(await remote.read(h.name))['rev'] as String;
      if (docs.any((d) => d['rev'] == rev)) continue;
      try {
        docs.add(_json(await remote.read('kv/$col/$key/$rev.json')));
      } catch (_) {}
    }
    if (docs.isEmpty) return;
    bool desc(Map a, String rev) => a['rev'] == rev || ((a['ancestors'] as List?)?.contains(rev) ?? false);
    final max = docs.where((a) => !docs.any((b) => b['rev'] != a['rev'] && desc(b, a['rev'] as String))).toList();
    Future<void> push(Map<String, dynamic> d) async {
      if (!await remote.exists('kv/$col/$key/${d['rev']}.json')) {
        await remote.writeSmall('kv/$col/$key/${d['rev']}.json', _bytes(d));
        rep.uploadedDocs++;
      }
      await remote.writeSmall('kvheads/$col/$key/$deviceId.json', _bytes({'rev': d['rev']}));
    }

    if (max.length == 1) {
      final w = max.first;
      if (local == null || w['rev'] != local['rev']) {
        kv._write(col, key, w);
        rep.downloadedDocs++;
        await remote.writeSmall('kvheads/$col/$key/$deviceId.json', _bytes({'rev': w['rev']}));
      } else {
        await push(local);
      }
      return;
    }
    rep.conflicts++;
    final main = local ?? max.first;
    for (final o in max.where((m) => m['rev'] != main['rev'])) {
      if (o['deleted'] != true) kv.put(col, '${key}_konflikt_${(o['rev'] as String).substring(0, 6)}', (o['value'] as Map).cast<String, dynamic>());
    }
    final merged = {...main, 'rev': const Uuid().v4(), 'ancestors': {...(main['ancestors'] as List), main['rev'], ...max.map((m) => m['rev']), ...max.expand((m) => m['ancestors'] as List)}.toList()};
    kv._write(col, key, merged);
    await push(merged);
  }

  // ------------------------------------------------------------ all
  Future<SyncReport> syncAll() async {
    final rep = SyncReport();
    _remoteBlobs = null;
    try {
      await registerDevice();
      // Space check before uploading
      final q = await remote.quota();
      final localIds = store.projectsDir.existsSync() ? store.projectsDir.listSync().whereType<Directory>().map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last).where((id) => store.projectFile(id).existsSync()).toSet() : <String>{};
      final remoteIds = (await remote.list('heads/')).map((f) => f.name.split('/')[1]).toSet();
      if (q.free != null) {
        var need = 0;
        final have = await _blobs();
        for (final id in localIds) {
          final d = await store.load(id);
          for (final a in d.assets.values) {
            if (!have.contains(_blobName(a.relPath))) need += a.size;
          }
        }
        if (need > q.free!) {
          rep.overall = SyncState.noSpace;
          rep.errors.add('Brak miejsca w chmurze: potrzeba ${(need / 1e6).toStringAsFixed(0)} MB, wolne ${(q.free! / 1e6).toStringAsFixed(0)} MB');
          for (final id in localIds) {
            _set(id, SyncState.noSpace);
          }
          return rep;
        }
      }
      for (final id in {...localIds, ...remoteIds}) {
        try {
          await syncProject(id, rep);
        } on SyncException catch (e) {
          rep.errors.add('$id: ${e.message}');
          _set(id, e.kind == SyncErrorKind.offline ? SyncState.waiting : e.kind == SyncErrorKind.auth ? SyncState.reauth : e.kind == SyncErrorKind.quota ? SyncState.noSpace : SyncState.error);
          if (e.kind == SyncErrorKind.offline || e.kind == SyncErrorKind.auth || e.kind == SyncErrorKind.revoked) rethrow;
        }
      }
      final kvRemote = (await remote.list('kvheads/')).map((f) => f.name.split('/')).where((p) => p.length >= 4).map((p) => '${p[1]}/${p[2]}').toSet();
      final kvLocal = {for (final c in kv.collections()) for (final k in kv.keys(c)) '$c/$k'};
      for (final ck in {...kvRemote, ...kvLocal}) {
        final i = ck.indexOf('/');
        await _syncKv(ck.substring(0, i), ck.substring(i + 1), rep);
      }
      _state['lastSuccess'] = DateTime.now().toUtc().toIso8601String();
      _saveState();
      rep.overall = rep.conflicts > 0 ? SyncState.conflict : SyncState.synced;
    } on SyncException catch (e) {
      rep.errors.add(e.message);
      rep.overall = switch (e.kind) {
        SyncErrorKind.offline => SyncState.waiting,
        SyncErrorKind.auth || SyncErrorKind.revoked => SyncState.reauth,
        SyncErrorKind.quota => SyncState.noSpace,
        _ => SyncState.error,
      };
    }
    rep.finishedAt = DateTime.now();
    return rep;
  }
}
