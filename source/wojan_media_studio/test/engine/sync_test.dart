import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wojan_media_studio/engine/audio/audio_project.dart';
import 'package:wojan_media_studio/engine/project/format.dart';
import 'package:wojan_media_studio/engine/project/store.dart';
import 'package:wojan_media_studio/engine/sync/engine.dart';
import 'package:wojan_media_studio/engine/sync/remote.dart';
import 'package:wojan_media_studio/engine/video/model.dart';

import 'test_media.dart';

/// Remote wrapper able to simulate going offline.
class FlakyRemote implements RemoteStore {
  final RemoteStore inner;
  bool offline = false;
  FlakyRemote(this.inner);
  T _g<T>(T Function() f) => offline ? throw SyncException(SyncErrorKind.offline, 'offline') : f();
  @override
  Future<void> delete(String name) => _g(() => inner.delete(name));
  @override
  Future<void> downloadFile(String name, File dest, {void Function(int got, int total)? onProgress}) => _g(() => inner.downloadFile(name, dest, onProgress: onProgress));
  @override
  Future<bool> exists(String name) => _g(() => inner.exists(name));
  @override
  Future<List<RemoteFile>> list(String prefix) => _g(() => inner.list(prefix));
  @override
  Future<RemoteQuota> quota() => _g(() => inner.quota());
  @override
  Future<Uint8List> read(String name) => _g(() => inner.read(name));
  @override
  Future<void> uploadFile(String name, File f, {void Function(int sent, int total)? onProgress}) => _g(() => inner.uploadFile(name, f, onProgress: onProgress));
  @override
  Future<void> writeSmall(String name, Uint8List data) => _g(() => inner.writeSmall(name, data));
}

class Device {
  final String id;
  late ProjectStore store;
  late SyncEngine sync;
  Device(this.id);
  Future<Device> init(Directory base, RemoteStore remote) async {
    sqfliteFfiInit();
    final root = Directory('${base.path}/$id');
    store = ProjectStore(root: root, dbFactory: databaseFactoryFfi, runner: TestMedia.runner, deviceId: id);
    await store.open();
    sync = SyncEngine(remote: remote, store: store, kv: KvStore(Directory('${root.path}/kv')), deviceId: id, deviceName: 'Urządzenie $id', platform: 'test', stateFile: File('${root.path}/sync_state.json'));
    return this;
  }
}

void main() {
  late Directory base;
  late FlakyRemote remote;
  late FolderRemoteStore folder;
  late Device win, android;
  late String projectId;

  setUpAll(() async {
    await TestMedia.init();
    base = await Directory.systemTemp.createTemp('wms_sync_');
    folder = FolderRemoteStore(Directory('${base.path}/cloud'), chunk: 64 * 1024);
    remote = FlakyRemote(folder);
    win = await Device('windows-pc').init(base, remote);
    android = await Device('android-phone').init(base, remote);
  });

  test('1-5: save on Windows, auto download on Android, edit there, update on Windows', () async {
    final song = await win.store.importMedia(await TestMedia.clickTrack(100, 8));
    final img = await win.store.importMedia(await TestMedia.image('cover', 'red'));
    final d = await win.store.create('Teledysk testowy', ProjectType.musicVideo);
    d.assets[song.id] = song;
    d.assets[img.id] = img;
    d.video = VideoProject()..clips.add(VisualClip(kind: ClipKind.image, assetId: img.id, imageDuration: 4));
    d.video!.audio.tracks.first.clips.add(AudioClip(assetId: song.id, srcIn: 0, srcOut: song.duration));
    await win.store.save(d);
    projectId = d.id;
    final r1 = await win.sync.syncAll();
    expect(r1.errors, isEmpty);
    expect(r1.uploadedBlobs, 2);
    final r2 = await android.sync.syncAll();
    expect(r2.errors, isEmpty);
    expect(r2.downloadedDocs, greaterThanOrEqualTo(1));
    final onPhone = await android.store.load(projectId);
    expect(onPhone.name, 'Teledysk testowy');
    expect(android.store.missingMedia(onPhone), isEmpty, reason: 'media must be fetched & verified');
    onPhone.name = 'Teledysk – poprawiony na telefonie';
    onPhone.video!.clips.first.imageDuration = 6;
    await android.store.save(onPhone);
    await android.sync.syncAll();
    final r3 = await win.sync.syncAll();
    expect(r3.downloadedDocs, greaterThanOrEqualTo(1));
    final onPc = await win.store.load(projectId);
    expect(onPc.name, 'Teledysk – poprawiony na telefonie');
    expect(onPc.video!.clips.first.imageDuration, 6);
    expect(onPc.revision, onPhone.revision);
  });

  test('6-9: offline editing then reconnect', () async {
    remote.offline = true;
    final d = await android.store.load(projectId);
    d.tags.add('offline');
    await android.store.save(d);
    final r = await android.sync.syncAll();
    expect(r.overall, SyncState.waiting);
    remote.offline = false;
    final r2 = await android.sync.syncAll();
    expect(r2.errors, isEmpty);
    await win.sync.syncAll();
    expect((await win.store.load(projectId)).tags, contains('offline'));
  });

  test('10-11: controlled conflict keeps both versions', () async {
    final a = await win.store.load(projectId);
    a.name = 'Wersja z komputera';
    await win.store.save(a);
    final b = await android.store.load(projectId);
    b.name = 'Wersja z telefonu';
    await android.store.save(b);
    await win.sync.syncAll();
    final r = await android.sync.syncAll();
    expect(r.conflicts, 1);
    await win.sync.syncAll();
    final namesPhone = (await android.store.list()).map((s) => s.name).toList();
    final namesPc = (await win.store.list()).map((s) => s.name).toList();
    expect(namesPhone.where((n) => n.contains('Wersja z telefonu')), isNotEmpty);
    expect(namesPhone.where((n) => n.contains('Wersja z komputera')), isNotEmpty);
    expect(namesPc.where((n) => n.contains('Wersja z telefonu')), isNotEmpty);
    expect(namesPc.where((n) => n.contains('Wersja z komputera')), isNotEmpty);
    // further syncs are stable (no new conflicts)
    final r2 = await win.sync.syncAll();
    final r3 = await android.sync.syncAll();
    expect(r2.conflicts + r3.conflicts, 0);
  });

  test('12-13: interrupted large upload resumes', () async {
    final big = File('${base.path}/big.wav');
    await TestMedia.runner.run(['-f', 'lavfi', '-i', 'anoisesrc=d=60:c=pink', '-ac', '2', '-ar', '48000', big.path]); // ~11 MB
    final asset = await win.store.importMedia(big.path);
    final d = await win.store.load(projectId);
    d.assets[asset.id] = asset;
    await win.store.save(d);
    folder.failAfterBytes = 3 * 1024 * 1024;
    folder.stickyFail = true; // connection stays down for all retries
    final r = await win.sync.syncAll();
    expect(r.overall, SyncState.waiting, reason: 'simulated connection loss');
    final part = File('${base.path}/cloud/blobs/${asset.relPath.split('/').last}.part');
    expect(part.existsSync(), isTrue);
    final partial = part.lengthSync();
    expect(partial, greaterThan(0));
    folder.failAfterBytes = null;
    folder.stickyFail = false;
    final before = folder.bytesWritten;
    final r2 = await win.sync.syncAll();
    expect(folder.bytesWritten - before, big.lengthSync() - partial, reason: 'only the remaining bytes are sent (resume)');
    expect(r2.errors, isEmpty);
    expect(File('${base.path}/cloud/blobs/${asset.relPath.split('/').last}').lengthSync(), big.lengthSync());
  });

  test('14-17: fresh device recovers everything with zero configuration', () async {
    final fresh = await Device('new-phone').init(base, remote);
    final r = await fresh.sync.syncAll();
    expect(r.errors, isEmpty);
    final pcList = await win.store.list();
    final newList = await fresh.store.list();
    expect(newList.map((e) => e.id).toSet(), pcList.map((e) => e.id).toSet());
    final d = await fresh.store.load(projectId);
    // big file (>64MB?) no – all small enough to be eager
    expect(fresh.store.missingMedia(d), isEmpty);
    final devs = await fresh.sync.devices();
    expect(devs.map((e) => e.id), containsAll(['windows-pc', 'android-phone', 'new-phone']));
  });

  test('templates/presets (kv) sync and conflict, deletion tombstones, device revoke', () async {
    win.sync.kv.put('templates', 'moj_styl', {'name': 'Mój styl', 'cut': 4});
    await win.sync.syncAll();
    await android.sync.syncAll();
    expect(android.sync.kv.get('templates', 'moj_styl')!['name'], 'Mój styl');
    // delete project everywhere
    final tmp = await win.store.create('Do usunięcia', ProjectType.audio);
    await win.sync.syncAll();
    await android.sync.syncAll();
    expect(android.store.projectFile(tmp.id).existsSync(), isTrue);
    await win.sync.deleteEverywhere(tmp.id);
    await android.sync.syncAll();
    expect(android.store.projectFile(tmp.id).existsSync(), isFalse);
    // revoke
    await win.sync.revokeDevice('android-phone');
    final r = await android.sync.syncAll();
    expect(r.overall, SyncState.reauth);
  });
}
