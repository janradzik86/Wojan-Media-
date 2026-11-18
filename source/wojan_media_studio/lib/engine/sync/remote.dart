import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class RemoteFile {
  final String id;
  final String name;
  final int size;
  final DateTime? modified;
  RemoteFile(this.id, this.name, this.size, [this.modified]);
}

class RemoteQuota {
  final int? limit; // null = unlimited / unknown
  final int usage;
  RemoteQuota(this.limit, this.usage);
  int? get free => limit == null ? null : limit! - usage;
}

enum SyncErrorKind { offline, auth, quota, notFound, conflict, server, revoked, other }

class SyncException implements Exception {
  final SyncErrorKind kind;
  final String message;
  SyncException(this.kind, this.message);
  @override
  String toString() => 'SyncException(${kind.name}): $message';
}

/// Persistent state of resumable uploads (survives app restarts).
class UploadSessionStore {
  final File file;
  Map<String, dynamic> _data = {};
  UploadSessionStore(this.file) {
    if (file.existsSync()) {
      try {
        _data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      } catch (_) {}
    }
  }
  String? get(String key) => _data[key] as String?;
  void put(String key, String session) {
    _data[key] = session;
    _flush();
  }

  void remove(String key) {
    _data.remove(key);
    _flush();
  }

  void _flush() {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(_data));
  }
}

/// Minimal storage contract used by the sync engine.
abstract class RemoteStore {
  Future<List<RemoteFile>> list(String prefix);
  Future<Uint8List> read(String name);
  Future<void> writeSmall(String name, Uint8List data); // create or replace
  /// Uploads a (possibly huge) file resumably. [onProgress] gets bytes sent.
  Future<void> uploadFile(String name, File f, {void Function(int sent, int total)? onProgress});
  /// Downloads into [dest] resumably (continues an existing `.part`).
  Future<void> downloadFile(String name, File dest, {void Function(int got, int total)? onProgress});
  Future<void> delete(String name);
  Future<bool> exists(String name);
  Future<RemoteQuota> quota();
}

/// Retry helper with exponential backoff + jitter.
Future<T> withRetry<T>(Future<T> Function() f, {int attempts = 5, Duration base = const Duration(milliseconds: 500), bool Function(Object e)? retryIf}) async {
  final rnd = math.Random();
  for (var i = 0;; i++) {
    try {
      return await f();
    } catch (e) {
      final retryable = retryIf?.call(e) ?? (e is SyncException ? (e.kind == SyncErrorKind.offline || e.kind == SyncErrorKind.server) : e is IOException);
      if (!retryable || i >= attempts - 1) rethrow;
      final ms = base.inMilliseconds * math.pow(2, i) + rnd.nextInt(base.inMilliseconds);
      await Future<void>.delayed(Duration(milliseconds: ms.toInt()));
    }
  }
}

/// Remote store backed by any synchronised folder (OneDrive/Dropbox/Google
/// Drive desktop folder, NAS, USB) – also used by the automated tests.
/// Writes are atomic (temp + rename); large copies resume from `.part`.
class FolderRemoteStore implements RemoteStore {
  final Directory root;
  final int chunk;
  /// Test hook: abort upload after N bytes to simulate interruption.
  int? failAfterBytes;
  bool stickyFail = false;
  int bytesWritten = 0; // statistics (tests / transfer control)
  FolderRemoteStore(this.root, {this.chunk = 1 << 20});

  File _f(String name) {
    if (name.contains('..') || name.startsWith('/')) throw SyncException(SyncErrorKind.other, 'Invalid name');
    return File('${root.path}/$name');
  }

  @override
  Future<List<RemoteFile>> list(String prefix) async {
    if (!root.existsSync()) return [];
    final out = <RemoteFile>[];
    for (final e in root.listSync(recursive: true).whereType<File>()) {
      final rel = e.path.substring(root.path.length + 1).replaceAll('\\', '/');
      if (rel.endsWith('.part') || rel.endsWith('.tmp')) continue;
      if (rel.startsWith(prefix)) out.add(RemoteFile(rel, rel, e.lengthSync(), e.lastModifiedSync()));
    }
    return out;
  }

  @override
  Future<Uint8List> read(String name) async {
    final f = _f(name);
    if (!f.existsSync()) throw SyncException(SyncErrorKind.notFound, name);
    return f.readAsBytes();
  }

  @override
  Future<void> writeSmall(String name, Uint8List data) async {
    final f = _f(name);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(data, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> uploadFile(String name, File src, {void Function(int sent, int total)? onProgress}) async {
    final f = _f(name);
    await f.parent.create(recursive: true);
    final part = File('${f.path}.part');
    final total = await src.length();
    var offset = part.existsSync() ? part.lengthSync() : 0;
    if (offset > total) {
      await part.delete();
      offset = 0;
    }
    final raf = await src.open();
    final out = await part.open(mode: FileMode.append);
    try {
      await raf.setPosition(offset);
      while (offset < total) {
        if (failAfterBytes != null && offset >= failAfterBytes!) {
          if (!stickyFail) failAfterBytes = null;
          throw SyncException(SyncErrorKind.offline, 'Simulated connection loss at $offset');
        }
        final buf = await raf.read(math.min(chunk, total - offset));
        await out.writeFrom(buf);
        offset += buf.length;
        bytesWritten += buf.length;
        onProgress?.call(offset, total);
      }
    } finally {
      await raf.close();
      await out.close();
    }
    await part.rename(f.path);
  }

  @override
  Future<void> downloadFile(String name, File dest, {void Function(int got, int total)? onProgress}) async {
    final f = _f(name);
    if (!f.existsSync()) throw SyncException(SyncErrorKind.notFound, name);
    await dest.parent.create(recursive: true);
    final part = File('${dest.path}.part');
    final total = f.lengthSync();
    var offset = part.existsSync() ? part.lengthSync() : 0;
    final raf = await f.open();
    final out = await part.open(mode: FileMode.append);
    try {
      await raf.setPosition(offset);
      while (offset < total) {
        final buf = await raf.read(math.min(chunk, total - offset));
        await out.writeFrom(buf);
        offset += buf.length;
        onProgress?.call(offset, total);
      }
    } finally {
      await raf.close();
      await out.close();
    }
    await part.rename(dest.path);
  }

  @override
  Future<void> delete(String name) async {
    final f = _f(name);
    if (f.existsSync()) await f.delete();
  }

  @override
  Future<bool> exists(String name) async => _f(name).existsSync();

  @override
  Future<RemoteQuota> quota() async => RemoteQuota(null, 0);
}
