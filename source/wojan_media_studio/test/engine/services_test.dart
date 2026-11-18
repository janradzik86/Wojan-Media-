import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wojan_media_studio/engine/batch/batch.dart';
import 'package:wojan_media_studio/engine/dsp/analysis.dart';
import 'package:wojan_media_studio/engine/dsp/pcm.dart';
import 'package:wojan_media_studio/engine/ffmpeg/escape.dart';
import 'package:wojan_media_studio/engine/ffmpeg/probe.dart';
import 'package:wojan_media_studio/engine/ffmpeg/runner.dart';
import 'package:wojan_media_studio/engine/lyrics/lyrics.dart';
import 'package:wojan_media_studio/engine/musicvideo/auto.dart';
import 'package:wojan_media_studio/engine/musicvideo/styles.dart';
import 'package:wojan_media_studio/engine/project/archive.dart';
import 'package:wojan_media_studio/engine/project/asset.dart';
import 'package:wojan_media_studio/engine/project/format.dart';
import 'package:wojan_media_studio/engine/publish/history.dart';
import 'package:wojan_media_studio/engine/publish/package.dart';
import 'package:wojan_media_studio/engine/publish/platforms.dart';
import 'package:wojan_media_studio/engine/publish/youtube.dart';
import 'package:wojan_media_studio/engine/render/queue.dart';
import 'package:wojan_media_studio/engine/sync/drive.dart';
import 'package:wojan_media_studio/engine/sync/remote.dart';
import 'package:wojan_media_studio/engine/update/updater.dart';

import 'test_media.dart';

void main() {
  setUpAll(() async => TestMedia.init());

  group('lyrics', () {
    test('LRC enhanced / SRT / VTT round trip with Polish characters', () {
      final t = LyricsTrack(lines: LyricsTrack.splitText('Zażółć gęślą jaźń\n\n[Refren]\nŁódź płynie po Wiśle bardzo długo i daleko aż do samego morza bałtyckiego'));
      expect(t.lines.length, 3); // long line wrapped, section marker removed
      t.tap(0, 1.0);
      t.tap(1, 4.5);
      t.tap(2, 8.0);
      t.finalizeTiming(songDuration: 12);
      final srt = t.toSrt();
      expect(srt, contains('00:00:01,000 --> 00:00:04,500'));
      final back = LyricsTrack.parse(srt, ext: 'srt');
      expect(back.lines.first.text, 'Zażółć gęślą jaźń');
      final vtt = LyricsTrack.parse(t.toVtt(), ext: 'vtt');
      expect(vtt.lines[1].start, closeTo(4.5, 0.001));
      final lrc = LyricsTrack.parse(t.toLrc(enhanced: true), ext: 'lrc');
      expect(lrc.lines.length, 3);
      expect(lrc.lines.first.words.first.text, 'Zażółć');
      expect(lrc.lines.first.words.first.start, closeTo(1.0, 0.011));
      t.shift(0.5, stretch: 1.0);
      expect(t.lines.first.start, closeTo(1.5, 1e-9));
      t.snapToBeats([1.45, 5.0, 8.6], tolerance: 0.2);
      expect(t.lines.first.start, 1.45);
    });
  });

  group('security', () {
    test('filter escaping & archive path traversal protection', () async {
      expect(FfEscape.escapeFilterValue("C:/a'b,[c];d"), "'C\\:/a\\'\\''b,[c];d'");
      expect(() => FfEscape.color('red;rm -rf'), throwsArgumentError);
      for (final bad in ['../evil', '/etc/passwd', 'C:/x', 'media/../../x', 'media\\a', 'media/abc.mp3', 'script.sh']) {
        expect(SafeArchive.isSafeName(bad), isFalse, reason: bad);
      }
      expect(SafeArchive.isSafeName('media/${'a' * 64}.mp3'), isTrue);
      // malicious archive is rejected
      final p = '${TestMedia.dir.path}/evil.wojanmedia';
      final enc = ZipFileEncoder()..create(p);
      enc.addArchiveFile(ArchiveFile('project.json', 2, utf8.encode('{}')));
      enc.addArchiveFile(ArchiveFile('../../evil.sh', 4, utf8.encode('boom')));
      await enc.close();
      expect(() => ProjectArchiver.import(p, '${TestMedia.dir.path}/m'), throwsA(isA<ProjectFormatException>()));
      expect(File('${TestMedia.dir.path}/../evil.sh').existsSync(), isFalse);
    });

    test('project migration v1 -> v2 and newer-version refusal', () {
      final v1 = {'format': 'wojanmedia', 'version': 1, 'id': 'p1', 'name': 'Stary', 'type': 'video', 'assets': {'a1': {'name': 'x.mp3', 'kind': 'audio', 'sha256': 'ab', 'path': 'media/ab.mp3'}}};
      final d = ProjectDoc.fromJson(v1);
      expect(d.assets['a1']!.relPath, 'media/ab.mp3');
      expect(d.toJson()['version'], kProjectFormatVersion);
      expect(() => ProjectDoc.fromJson({'format': 'wojanmedia', 'version': 99}), throwsA(isA<ProjectFormatException>()));
    });
  });

  group('publisher', () {
    test('platform checks, hashtags, package, duplicate prevention', () async {
      final v = await TestMedia.video('pub', 4, w: 1920, h: 1080);
      final info = MediaInfo.fromProbe(v, await TestMedia.runner.probeJson(v));
      final profiles = PlatformProfiles();
      final tiktok = checkForPlatform(profiles['tiktok']!, info);
      expect(tiktok.any((i) => i.level == IssueLevel.warning && i.message.contains('Proporcje')), isTrue);
      final yt = checkForPlatform(profiles['youtube']!, info, title: 'x' * 120);
      expect(yt.any((i) => i.level == IssueLevel.error), isTrue);
      expect(normalizeHashtags('muzyka, #Polska  #polska rap-pl'), ['#muzyka', '#Polska', '#rappl']);
      expect(profiles.updateFromJson(jsonEncode({'version': 2, 'profiles': [{'id': 'tiktok', 'name': 'TikTok', 'aspect': [9, 16], 'size': [1080, 1920], 'maxDurationSec': 1200}]})), isTrue);
      expect(profiles['tiktok']!.maxDurationSec, 1200);
      final dir = await PublicationPackager(TestMedia.runner).build(videoPath: v, outDir: '${TestMedia.dir.path}/pakiet', title: 'Mój teledysk', description: 'Opis', hashtags: ['#a'], lyrics: LyricsTrack(lines: [LyricLine(0, 2, 'Wers')]), zip: true);
      for (final n in ['Teledysk.mp4', 'Audio.mp3', 'Okladka.png', 'Miniatura.jpg', 'Opis.txt', 'Hashtagi.txt', 'Napisy.srt', 'Metadane.json']) {
        expect(File('${dir.path}/$n').existsSync(), isTrue, reason: n);
      }
      expect(File('${dir.path}.zip').lengthSync(), greaterThan(1000));
      final h = PublishHistory(File('${TestMedia.dir.path}/history.json'));
      h.upsert(PublishRecord(projectId: 'p', platform: 'youtube', fileSha256: 'abc', filePath: v, status: PublishStatus.uploaded));
      expect(h.duplicateOf('abc', 'youtube'), isNotNull);
      expect(h.duplicateOf('abc', 'tiktok'), isNull);
      expect(PublishHistory(h.file).records.length, 1);
    });

    test('YouTube resumable upload protocol, token refresh, status confirmation (mock server)', () async {
      final file = File('${TestMedia.dir.path}/yt.bin')..writeAsBytesSync(Uint8List(300 * 1024));
      var received = 0;
      var refreshed = false;
      var first = true;
      final client = MockClient((req) async {
        final auth = req.headers['Authorization'];
        if (req.url.path.endsWith('/videos') && req.method == 'POST') {
          if (first) {
            first = false;
            return http.Response('{"error":"expired"}', 401);
          }
          expect(auth, 'Bearer fresh');
          final meta = jsonDecode(req.body) as Map;
          expect(meta['status']['privacyStatus'], 'private');
          expect(meta['status']['publishAt'], isNotNull);
          return http.Response('', 200, headers: {'location': 'https://upload.example/session1'});
        }
        if (req.url.host == 'upload.example') {
          final cr = req.headers['Content-Range']!;
          final m = RegExp(r'bytes (\d+)-(\d+)/(\d+)').firstMatch(cr)!;
          received = int.parse(m.group(2)!) + 1;
          if (received < int.parse(m.group(3)!)) return http.Response('', 308, headers: {'range': 'bytes=0-${received - 1}'});
          return http.Response('{"id":"VID123"}', 200);
        }
        if (req.url.path.endsWith('/videos') && req.method == 'GET') {
          return http.Response(jsonEncode({'items': [{'status': {'uploadStatus': 'uploaded', 'privacyStatus': 'private', 'publishAt': '2030-01-01T10:00:00Z'}}]}), 200);
        }
        return http.Response('not found', 404);
      });
      final up = YouTubeUploader(token: ({bool forceRefresh = false}) async {
        if (forceRefresh) refreshed = true;
        return refreshed ? 'fresh' : 'stale';
      }, client: _RetryOn401(client, () => refreshed = true), sessions: UploadSessionStore(File('${TestMedia.dir.path}/yt_sessions.json')), chunk: 100 * 1024);
      final rec = PublishRecord(projectId: 'p', platform: 'youtube', fileSha256: 's', filePath: file.path, title: 'Test', scheduledAt: DateTime.utc(2030), userApproved: true);
      final progress = <int>[];
      final done = await up.upload(rec, onUpdate: (r) => progress.add(r.bytesSent));
      expect(received, 300 * 1024);
      expect(done.remoteId, 'VID123');
      expect(done.status, PublishStatus.scheduled);
      expect(progress.where((p) => p > 0 && p < 300 * 1024), isNotEmpty, reason: 'real intermediate progress');
      expect(refreshed, isTrue, reason: 'expired token was refreshed automatically');
      expect(() => up.upload(PublishRecord(projectId: 'p', platform: 'youtube', fileSha256: 's', filePath: file.path)), throwsStateError);
      // fully revoked token → readable re-login error
      final dead = YouTubeUploader(token: ({bool forceRefresh = false}) async => 'x', client: MockClient((r) async => http.Response('', 401)), sessions: UploadSessionStore(File('${TestMedia.dir.path}/yt2.json')));
      expect(() => dead.upload(PublishRecord(projectId: 'p', platform: 'youtube', fileSha256: 's2', filePath: file.path, userApproved: true)), throwsA(isA<SyncException>().having((e) => e.kind, 'kind', SyncErrorKind.auth)));
    });

    test('Drive appDataFolder resumable upload & ranged download (mock server)', () async {
      final store = <String, Uint8List>{};
      final client = MockClient((req) async {
        final q = req.url.queryParameters;
        if (req.url.path == '/drive/v3/files' && req.method == 'GET') {
          final name = RegExp(r"name (?:=|contains) '([^']+)'").firstMatch(q['q']!)!.group(1)!;
          final files = store.keys.where((k) => k.startsWith(name)).map((k) => {'id': k, 'name': k, 'size': '${store[k]!.length}'}).toList();
          return http.Response(jsonEncode({'files': files}), 200);
        }
        if (req.url.path == '/upload/drive/v3/files' && q['uploadType'] == 'resumable') {
          final name = (jsonDecode(req.body) as Map)['name'] as String;
          expect((jsonDecode(req.body) as Map)['parents'], ['appDataFolder']);
          store['$name.part'] = Uint8List(0);
          return http.Response('', 200, headers: {'location': 'https://up.example/$name'});
        }
        if (req.url.host == 'up.example') {
          final name = req.url.path.substring(1);
          final cur = store['$name.part']!;
          final total = int.parse(req.headers['Content-Range']!.split('/').last);
          final merged = Uint8List.fromList([...cur, ...req.bodyBytes]);
          store['$name.part'] = merged;
          if (merged.length < total) return http.Response('', 308, headers: {'range': 'bytes=0-${merged.length - 1}'});
          store[name] = merged;
          store.remove('$name.part');
          return http.Response(jsonEncode({'id': name}), 200);
        }
        if (req.url.path.startsWith('/drive/v3/files/') && q['alt'] == 'media') {
          final id = Uri.decodeComponent(req.url.path.substring('/drive/v3/files/'.length));
          final data = store[id]!;
          final range = req.headers['Range'];
          if (range != null) {
            final from = int.parse(range.substring(6, range.length - 1));
            return http.Response.bytes(data.sublist(from), 206);
          }
          return http.Response.bytes(data, 200);
        }
        if (req.url.path == '/drive/v3/about') return http.Response(jsonEncode({'storageQuota': {'limit': '16106127360', 'usage': '1000'}}), 200);
        return http.Response('?', 404);
      });
      final drive = DriveRemoteStore(token: ({bool forceRefresh = false}) async => 't', client: client, sessions: UploadSessionStore(File('${TestMedia.dir.path}/ds.json')), chunkSize: 256 * 1024);
      final src = File('${TestMedia.dir.path}/blob.bin')..writeAsBytesSync(List.generate(700 * 1024, (i) => i % 251));
      await drive.uploadFile('blobs/x.bin', src);
      expect(store['blobs/x.bin']!.length, 700 * 1024);
      final dest = File('${TestMedia.dir.path}/dl/x.bin');
      // simulate partial previous download
      File('${dest.path}.part')
        ..createSync(recursive: true)
        ..writeAsBytesSync(store['blobs/x.bin']!.sublist(0, 1000));
      await drive.downloadFile('blobs/x.bin', dest);
      expect(dest.readAsBytesSync(), store['blobs/x.bin']);
      final q = await drive.quota();
      expect(q.free, greaterThan(0));
    });
  });

  group('updater', () {
    test('signed manifest verification and sha256 check', () async {
      final kp = await Ed25519().newKeyPair();
      final pub = (await kp.extractPublicKey()).bytes;
      final file = File('${TestMedia.dir.path}/setup.exe')..writeAsBytesSync(List.filled(1000, 7));
      final sha = (await TestMedia.runner.ffprobe(['-version'])).ok ? await _sha(file) : '';
      final manifest = await Updater.signManifest({'version': '1.1.0', 'build': 2, 'windows': {'url': 'https://example.com/setup.exe', 'sha256': sha, 'size': 1000}}, kp);
      final m = await Updater.verifyManifest(manifest, pub);
      expect(m['version'], '1.1.0');
      final tampered = manifest.replaceFirst(RegExp(r'"signature": "[A-Za-z0-9+/]'), '"signature": "A');
      expect(() => Updater.verifyManifest(tampered, pub), throwsA(isA<UpdateException>()));
      final up = Updater(manifestUrl: 'https://example.com/m.json', publicKey: pub, client: MockClient((r) async {
        if (r.url.path.endsWith('m.json')) return http.Response(manifest, 200);
        return http.Response.bytes(file.readAsBytesSync(), 200);
      }));
      final info = await up.check('1.0.0');
      expect(info!.version, '1.1.0');
      expect(await up.check('1.1.0'), isNull);
      final f = await up.download(info.windows!, '${TestMedia.dir.path}/dl_setup.exe');
      expect(f.lengthSync(), 1000);
      final bad = Updater(manifestUrl: 'x', publicKey: pub, client: MockClient((r) async => http.Response.bytes(List.filled(1000, 8), 200)));
      expect(() => bad.download(info.windows!, '${TestMedia.dir.path}/bad.exe'), throwsA(isA<UpdateException>()));
    });
  });

  group('render queue & batch', () {
    test('queue progress, cancel, retry, disk space guard', () async {
      final q = RenderQueue(freeSpace: (_) async => 10 * 1024 * 1024 * 1024);
      final out = '${TestMedia.dir.path}/q1.wav';
      final j = RenderJob(title: 'a', outputPath: out, expectedDuration: 5, run: (p, c) => TestMedia.runner.run(['-f', 'lavfi', '-i', 'sine=d=5', out], onProgress: p, cancel: c));
      q.add(j);
      await q.changes.firstWhere((e) => e == j && (e.state == JobState.done || e.state == JobState.failed));
      expect(j.state, JobState.done, reason: j.error);
      final out2 = '${TestMedia.dir.path}/q2.mp4';
      final j2 = RenderJob(title: 'b', outputPath: out2, expectedDuration: 600, run: (p, c) => TestMedia.runner.run(['-f', 'lavfi', '-i', 'testsrc2=s=1920x1080:d=600', '-c:v', 'libx264', '-preset', 'veryslow', out2], onProgress: p, cancel: c));
      q.add(j2);
      await q.changes.firstWhere((e) => e == j2 && e.state == JobState.running);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      q.cancel(j2);
      await q.changes.firstWhere((e) => e == j2 && e.state != JobState.running);
      expect(j2.state, JobState.cancelled);
      expect(File(out2).existsSync(), isFalse);
      final q2 = RenderQueue(freeSpace: (_) async => 1000);
      final j3 = RenderJob(title: 'c', outputPath: '${TestMedia.dir.path}/q3.mp4', expectedDuration: 1, estimatedBytes: 10000000, run: (p, c) async {});
      q2.add(j3);
      await q2.changes.firstWhere((e) => e == j3 && e.state == JobState.failed);
      expect(j3.error, contains('miejsca'));
    });

    test('batch planning pairs songs with covers and targets platforms', () async {
      final song = await TestMedia.clickTrack(110, 8);
      final info = MediaInfo.fromProbe(song, await TestMedia.runner.probeJson(song));
      final a = AudioAnalyzer.analyze(await PcmDecoder(TestMedia.runner, TestMedia.dir).decode(song));
      final s1 = MediaAsset(id: 's1', name: 'utwor1.mp3', kind: MediaKind.audio, sha256: '', size: 0, relPath: '', duration: info.duration, localPath: song);
      final s2 = MediaAsset(id: 's2', name: 'utwor2.mp3', kind: MediaKind.audio, sha256: '', size: 0, relPath: '', duration: info.duration, localPath: song);
      final c2 = MediaAsset(id: 'c2', name: 'utwor2.jpg', kind: MediaKind.image, sha256: '', size: 0, relPath: '');
      final c1 = MediaAsset(id: 'c1', name: 'okladka.jpg', kind: MediaKind.image, sha256: '', size: 0, relPath: '');
      final items = BatchPlanner.pair([s1, s2], [c1, c2]);
      expect(items[1].covers.first.id, 'c2');
      expect(items[0].covers.first.id, 'c1');
      final plan = BatchPlanner.plan(items: items, analyses: {'s1': a, 's2': a}, style: styleById('phonk'), mode: MusicVideoMode.dynamic, platforms: [PlatformProfiles()['tiktok']!, PlatformProfiles()['youtube']!]);
      expect(plan.length, 4);
      expect(plan.map((e) => e.settings.width).toSet(), {1080, 1920});
    });
  });
}

Future<String> _sha(File f) async {
  final r = await Process.run('sha256sum', [f.path]);
  return (r.stdout as String).split(' ').first;
}

/// Simulates an HTTP client wrapper: first 401 triggers token refresh.
class _RetryOn401 extends http.BaseClient {
  final http.Client inner;
  final void Function() onRefresh;
  _RetryOn401(this.inner, this.onRefresh);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => inner.send(request);
}
