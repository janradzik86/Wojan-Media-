import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'remote.dart';

/// Supplies a fresh OAuth access token (scope drive.appdata).
typedef TokenProvider = Future<String> Function({bool forceRefresh});

/// Google Drive v3 REST backend storing everything in the hidden, per-app
/// `appDataFolder` (scope `https://www.googleapis.com/auth/drive.appdata`).
/// Both the Windows and Android builds must use OAuth clients from the SAME
/// Google Cloud project so they share the same appDataFolder.
class DriveRemoteStore implements RemoteStore {
  final TokenProvider token;
  final http.Client client;
  final UploadSessionStore sessions;
  final int chunkSize; // multiple of 256 KiB
  static const _api = 'https://www.googleapis.com/drive/v3';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3';
  final Map<String, String> _idCache = {};

  DriveRemoteStore({required this.token, http.Client? client, required this.sessions, this.chunkSize = 8 * 256 * 1024}) : client = client ?? http.Client();

  Future<Map<String, String>> _headers([Map<String, String>? extra, bool refresh = false]) async => {'Authorization': 'Bearer ${await token(forceRefresh: refresh)}', ...?extra};

  Future<http.Response> _send(Future<http.Response> Function(Map<String, String> h) f, {Map<String, String>? extra}) async {
    http.Response r;
    try {
      r = await f(await _headers(extra));
      if (r.statusCode == 401) r = await f(await _headers(extra, true));
    } on SocketException catch (e) {
      throw SyncException(SyncErrorKind.offline, e.message);
    } on http.ClientException catch (e) {
      throw SyncException(SyncErrorKind.offline, e.message);
    }
    _check(r);
    return r;
  }

  void _check(http.Response r) {
    if (r.statusCode < 300 || r.statusCode == 308) return;
    final body = r.body.length > 300 ? r.body.substring(0, 300) : r.body;
    if (r.statusCode == 401) throw SyncException(SyncErrorKind.auth, 'Wymaga ponownego logowania');
    if (r.statusCode == 403 && body.contains('storageQuotaExceeded')) throw SyncException(SyncErrorKind.quota, 'Brak miejsca na Dysku Google');
    if (r.statusCode == 403 && (body.contains('rateLimit') || body.contains('userRateLimit'))) throw SyncException(SyncErrorKind.server, 'Limit zapytań – ponowienie');
    if (r.statusCode == 404) throw SyncException(SyncErrorKind.notFound, body);
    if (r.statusCode == 429 || r.statusCode >= 500) throw SyncException(SyncErrorKind.server, 'HTTP ${r.statusCode}');
    throw SyncException(SyncErrorKind.other, 'HTTP ${r.statusCode}: $body');
  }

  String _q(String s) => s.replaceAll('\\', '\\\\').replaceAll("'", "\\'");

  @override
  Future<List<RemoteFile>> list(String prefix) async {
    final out = <RemoteFile>[];
    String? page;
    do {
      final uri = Uri.parse('$_api/files').replace(queryParameters: {
        'spaces': 'appDataFolder',
        'q': "name contains '${_q(prefix)}' and trashed = false",
        'fields': 'nextPageToken,files(id,name,size,modifiedTime)',
        'pageSize': '1000',
        if (page != null) 'pageToken': page,
      });
      final r = await withRetry(() => _send((h) => client.get(uri, headers: h)));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      for (final f in (j['files'] as List? ?? [])) {
        final m = f as Map<String, dynamic>;
        final name = m['name'] as String;
        if (!name.startsWith(prefix)) continue;
        _idCache[name] = m['id'] as String;
        out.add(RemoteFile(m['id'] as String, name, int.tryParse('${m['size'] ?? 0}') ?? 0, DateTime.tryParse('${m['modifiedTime']}')));
      }
      page = j['nextPageToken'] as String?;
    } while (page != null);
    return out;
  }

  Future<String?> _idOf(String name) async {
    final c = _idCache[name];
    if (c != null) return c;
    final uri = Uri.parse('$_api/files').replace(queryParameters: {'spaces': 'appDataFolder', 'q': "name = '${_q(name)}' and trashed = false", 'fields': 'files(id,name)', 'pageSize': '10'});
    final r = await withRetry(() => _send((h) => client.get(uri, headers: h)));
    final files = (jsonDecode(r.body) as Map<String, dynamic>)['files'] as List? ?? [];
    if (files.isEmpty) return null;
    return _idCache[name] = (files.first as Map)['id'] as String;
  }

  @override
  Future<bool> exists(String name) async => await _idOf(name) != null;

  @override
  Future<Uint8List> read(String name) async {
    final id = await _idOf(name);
    if (id == null) throw SyncException(SyncErrorKind.notFound, name);
    final r = await withRetry(() => _send((h) => client.get(Uri.parse('$_api/files/$id?alt=media'), headers: h)));
    return r.bodyBytes;
  }

  @override
  Future<void> writeSmall(String name, Uint8List data) async {
    final id = await _idOf(name);
    if (id != null) {
      await withRetry(() => _send((h) => client.patch(Uri.parse('$_upload/files/$id?uploadType=media'), headers: h, body: data), extra: {'Content-Type': 'application/octet-stream'}));
      return;
    }
    const boundary = 'wojanmedia_boundary_7f3a';
    final meta = jsonEncode({'name': name, 'parents': ['appDataFolder']});
    final body = BytesBuilder()
      ..add(utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n--$boundary\r\nContent-Type: application/octet-stream\r\n\r\n'))
      ..add(data)
      ..add(utf8.encode('\r\n--$boundary--'));
    final r = await withRetry(() => _send((h) => client.post(Uri.parse('$_upload/files?uploadType=multipart&fields=id'), headers: h, body: body.toBytes()), extra: {'Content-Type': 'multipart/related; boundary=$boundary'}));
    _idCache[name] = (jsonDecode(r.body) as Map)['id'] as String;
  }

  Future<String> _startSession(String name, int total) async {
    final r = await withRetry(() => _send(
        (h) => client.post(Uri.parse('$_upload/files?uploadType=resumable&fields=id'), headers: h, body: jsonEncode({'name': name, 'parents': ['appDataFolder']})),
        extra: {'Content-Type': 'application/json; charset=UTF-8', 'X-Upload-Content-Type': 'application/octet-stream', 'X-Upload-Content-Length': '$total'}));
    final loc = r.headers['location'];
    if (loc == null) throw SyncException(SyncErrorKind.server, 'Brak adresu sesji przesyłania');
    return loc;
  }

  /// Asks the server how many bytes of a session it already has.
  Future<int> _sessionOffset(String session, int total) async {
    final r = await _send((h) => client.put(Uri.parse(session), headers: h), extra: {'Content-Range': 'bytes */$total', 'Content-Length': '0'});
    if (r.statusCode == 200 || r.statusCode == 201) return total;
    final range = r.headers['range'];
    if (range == null) return 0;
    return int.parse(range.split('-').last) + 1;
  }

  @override
  Future<void> uploadFile(String name, File f, {void Function(int sent, int total)? onProgress}) async {
    final total = await f.length();
    final key = 'up:$name:$total';
    var session = sessions.get(key);
    var offset = 0;
    if (session != null) {
      try {
        offset = await _sessionOffset(session, total);
      } on SyncException catch (e) {
        if (e.kind == SyncErrorKind.notFound || e.kind == SyncErrorKind.other) {
          session = null;
          offset = 0;
        } else {
          rethrow;
        }
      }
    }
    session ??= await _startSession(name, total);
    sessions.put(key, session);
    final raf = await f.open();
    try {
      while (offset < total) {
        await raf.setPosition(offset);
        final len = math.min(chunkSize, total - offset);
        final buf = await raf.read(len);
        final end = offset + buf.length - 1;
        final s = session;
        final r = await withRetry(() => _send((h) => client.put(Uri.parse(s), headers: h, body: buf), extra: {'Content-Range': 'bytes $offset-$end/$total', 'Content-Length': '${buf.length}'}));
        if (r.statusCode == 200 || r.statusCode == 201) {
          _idCache[name] = (jsonDecode(r.body) as Map)['id'] as String;
          offset = total;
        } else {
          final range = r.headers['range'];
          offset = range == null ? 0 : int.parse(range.split('-').last) + 1;
        }
        onProgress?.call(offset, total);
      }
      if (total == 0) {
        await writeSmall(name, Uint8List(0));
      }
    } finally {
      await raf.close();
    }
    sessions.remove(key);
  }

  @override
  Future<void> downloadFile(String name, File dest, {void Function(int got, int total)? onProgress}) async {
    final id = await _idOf(name);
    if (id == null) throw SyncException(SyncErrorKind.notFound, name);
    await dest.parent.create(recursive: true);
    final part = File('${dest.path}.part');
    var offset = part.existsSync() ? part.lengthSync() : 0;
    final req = http.Request('GET', Uri.parse('$_api/files/$id?alt=media'));
    req.headers.addAll(await _headers({if (offset > 0) 'Range': 'bytes=$offset-'}));
    http.StreamedResponse resp;
    try {
      resp = await client.send(req);
    } on SocketException catch (e) {
      throw SyncException(SyncErrorKind.offline, e.message);
    }
    if (resp.statusCode == 416) {
      await part.rename(dest.path);
      return;
    }
    if (resp.statusCode >= 300) {
      _check(http.Response('', resp.statusCode));
    }
    if (resp.statusCode == 200 && offset > 0) offset = 0; // server ignored range
    final total = offset + (resp.contentLength ?? 0);
    final sink = part.openWrite(mode: offset > 0 ? FileMode.append : FileMode.write);
    try {
      await for (final c in resp.stream) {
        sink.add(c);
        offset += c.length;
        onProgress?.call(offset, total);
      }
    } on Object catch (e) {
      await sink.close();
      throw SyncException(SyncErrorKind.offline, '$e');
    }
    await sink.close();
    await part.rename(dest.path);
  }

  @override
  Future<void> delete(String name) async {
    final id = await _idOf(name);
    if (id == null) return;
    await withRetry(() => _send((h) => client.delete(Uri.parse('$_api/files/$id'), headers: h)));
    _idCache.remove(name);
  }

  @override
  Future<RemoteQuota> quota() async {
    final r = await withRetry(() => _send((h) => client.get(Uri.parse('$_api/about?fields=storageQuota'), headers: h)));
    final q = (jsonDecode(r.body) as Map<String, dynamic>)['storageQuota'] as Map<String, dynamic>;
    return RemoteQuota(q['limit'] == null ? null : int.parse('${q['limit']}'), int.parse('${q['usage'] ?? 0}'));
  }
}
