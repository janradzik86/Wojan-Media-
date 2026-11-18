import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../sync/drive.dart' show TokenProvider;
import '../sync/remote.dart';
import 'history.dart';
import '../project/format.dart';

/// Official YouTube Data API v3 uploader (OAuth scope
/// `https://www.googleapis.com/auth/youtube.upload`). Uses resumable upload,
/// real byte progress, retries and status confirmation via videos.list.
///
/// Note (Google policy): videos uploaded by unverified API projects are
/// locked to *private* until the project passes Google's audit.
class YouTubeUploader {
  final TokenProvider token;
  final http.Client client;
  final UploadSessionStore sessions;
  final int chunk;
  YouTubeUploader({required this.token, http.Client? client, required this.sessions, this.chunk = 8 * 1024 * 1024}) : client = client ?? http.Client();

  Future<Map<String, String>> _h([Map<String, String>? x, bool refresh = false]) async => {'Authorization': 'Bearer ${await token(forceRefresh: refresh)}', ...?x};

  /// Sends a request; on HTTP 401 refreshes the token once and retries.
  Future<http.Response> _auth(Future<http.Response> Function(Map<String, String> h) f, [Map<String, String>? extra]) async {
    var r = await f(await _h(extra));
    if (r.statusCode == 401) r = await f(await _h(extra, true));
    return r;
  }

  void _check(http.Response r) {
    if (r.statusCode < 300 || r.statusCode == 308) return;
    final b = r.body;
    if (r.statusCode == 401) throw SyncException(SyncErrorKind.auth, 'Token wygasł – zaloguj się ponownie do YouTube');
    if (b.contains('quotaExceeded')) throw SyncException(SyncErrorKind.quota, 'Przekroczono dzienny limit API YouTube');
    if (b.contains('uploadLimitExceeded')) throw SyncException(SyncErrorKind.quota, 'Kanał osiągnął limit przesyłania');
    if (r.statusCode >= 500 || r.statusCode == 429) throw SyncException(SyncErrorKind.server, 'HTTP ${r.statusCode}');
    throw SyncException(SyncErrorKind.other, 'YouTube HTTP ${r.statusCode}: ${b.length > 400 ? b.substring(0, 400) : b}');
  }

  Future<List<Map<String, dynamic>>> channels() async {
    final r = await client.get(Uri.parse('https://www.googleapis.com/youtube/v3/channels?part=snippet&mine=true'), headers: await _h());
    _check(r);
    return ((jsonDecode(r.body) as Map)['items'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  /// Uploads [rec.filePath]; updates [rec] progress via [onUpdate].
  Future<PublishRecord> upload(PublishRecord rec, {String categoryId = '10', void Function(PublishRecord r)? onUpdate, String? thumbnailPath}) async {
    if (!rec.userApproved) throw StateError('Publikacja wymaga świadomego zatwierdzenia przez użytkownika');
    final f = File(rec.filePath);
    final total = await f.length();
    rec.bytesTotal = total;
    final status = <String, dynamic>{'privacyStatus': rec.scheduledAt != null ? 'private' : rec.visibility, 'selfDeclaredMadeForKids': false};
    if (rec.scheduledAt != null) status['publishAt'] = rec.scheduledAt!.toUtc().toIso8601String();
    final meta = {
      'snippet': {'title': rec.title.isEmpty ? 'Bez tytułu' : rec.title, 'description': [rec.description, rec.hashtags.join(' ')].where((e) => e.isNotEmpty).join('\n\n'), 'tags': rec.hashtags.map((e) => e.replaceAll('#', '')).toList(), 'categoryId': categoryId},
      'status': status,
    };
    final key = 'yt:${rec.id}';
    var session = sessions.get(key);
    var offset = 0;
    if (session != null) {
      final r = await client.put(Uri.parse(session), headers: await _h({'Content-Range': 'bytes */$total', 'Content-Length': '0'}));
      if (r.statusCode == 308) {
        final range = r.headers['range'];
        offset = range == null ? 0 : int.parse(range.split('-').last) + 1;
      } else if (r.statusCode == 200 || r.statusCode == 201) {
        return _finish(rec, r, key, onUpdate, thumbnailPath);
      } else {
        session = null;
      }
    }
    if (session == null) {
      final r = await _auth((h) => client.post(Uri.parse('https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status'), headers: h, body: jsonEncode(meta)),
          {'Content-Type': 'application/json; charset=UTF-8', 'X-Upload-Content-Length': '$total', 'X-Upload-Content-Type': 'video/*'});
      _check(r);
      session = r.headers['location']!;
      sessions.put(key, session);
    }
    rec.status = PublishStatus.uploading;
    onUpdate?.call(rec);
    final raf = await f.open();
    try {
      while (offset < total) {
        await raf.setPosition(offset);
        final buf = await raf.read(math.min(chunk, total - offset));
        final s = session;
        final r = await withRetry(() async {
          final resp = await _auth((h) => client.put(Uri.parse(s), headers: h, body: buf), {'Content-Range': 'bytes $offset-${offset + buf.length - 1}/$total'});
          _check(resp);
          return resp;
        });
        if (r.statusCode == 200 || r.statusCode == 201) {
          rec.bytesSent = total;
          return _finish(rec, r, key, onUpdate, thumbnailPath);
        }
        final range = r.headers['range'];
        offset = range == null ? 0 : int.parse(range.split('-').last) + 1;
        rec.bytesSent = offset;
        onUpdate?.call(rec);
      }
    } finally {
      await raf.close();
    }
    throw SyncException(SyncErrorKind.server, 'Przesyłanie nie zostało potwierdzone');
  }

  Future<PublishRecord> _finish(PublishRecord rec, http.Response r, String key, void Function(PublishRecord r)? onUpdate, String? thumb) async {
    sessions.remove(key);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    rec.remoteId = j['id'] as String?;
    rec.url = rec.remoteId == null ? null : 'https://www.youtube.com/watch?v=${rec.remoteId}';
    rec.status = PublishStatus.uploaded;
    onUpdate?.call(rec);
    if (thumb != null && rec.remoteId != null) {
      try {
        final tr = await client.post(Uri.parse('https://www.googleapis.com/upload/youtube/v3/thumbnails/set?videoId=${rec.remoteId}'), headers: await _h({'Content-Type': 'image/jpeg'}), body: await File(thumb).readAsBytes());
        _check(tr);
      } catch (e) {
        rec.error = 'Miniatura nie została ustawiona: $e';
      }
    }
    await confirmStatus(rec);
    onUpdate?.call(rec);
    return rec;
  }

  /// Confirms processing/privacy state via the API (no assumptions).
  Future<void> confirmStatus(PublishRecord rec) async {
    if (rec.remoteId == null) return;
    final r = await _auth((h) => client.get(Uri.parse('https://www.googleapis.com/youtube/v3/videos?part=status,processingDetails&id=${rec.remoteId}'), headers: h));
    _check(r);
    final items = (jsonDecode(r.body) as Map)['items'] as List? ?? [];
    if (items.isEmpty) return;
    final st = (items.first as Map)['status'] as Map<String, dynamic>;
    final upload = st['uploadStatus'];
    if (upload == 'rejected' || upload == 'failed') {
      rec.status = PublishStatus.error;
      rec.error = 'YouTube: ${st['rejectionReason'] ?? st['failureReason'] ?? upload}';
    } else if (st['publishAt'] != null) {
      rec.status = PublishStatus.scheduled;
    } else if (upload == 'processed' && st['privacyStatus'] == 'public') {
      rec.status = PublishStatus.published;
    } else {
      rec.status = PublishStatus.uploaded;
    }
  }
}
