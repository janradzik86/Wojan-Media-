import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqf;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../engine/dsp/analysis.dart';
import '../engine/dsp/pcm.dart';
import '../engine/ffmpeg/runner.dart';
import '../engine/musicvideo/styles.dart';
import '../engine/project/store.dart';
import '../engine/publish/history.dart';
import '../engine/publish/platforms.dart';
import '../engine/render/queue.dart';
import '../engine/sync/drive.dart';
import '../engine/sync/engine.dart';
import '../engine/sync/remote.dart';
import '../engine/video/compiler.dart';
import '../platform/auth.dart';
import '../platform/disk.dart';
import '../platform/kit_runner.dart';
import '../platform/native.dart';
import 'l10n.dart';
import '../engine/video/vfx_library.dart';
import '../ui/preview/text_layer.dart';

const appVersion = String.fromEnvironment('WMS_VERSION', defaultValue: '1.0.4');

/// Application-wide settings (persisted, synchronised as KV doc).
class AppSettings extends ChangeNotifier {
  Map<String, dynamic> v = {
    'lang': 'pl',
    'theme': 'dark',
    'proMode': false,
    'autoSync': true,
    'wifiOnly': false,
    'syncRenders': false,
    'eagerDownloadMB': 64,
    'encoder': 'auto',
    'profile': 'balanced', // performance / balanced / battery
    'previewScale': 0.33,
    'autosaveSec': 20,
    'syncFolder': '',
    'updateUrl': const String.fromEnvironment('WMS_UPDATE_MANIFEST_URL'),
  };
  T get<T>(String k) => v[k] as T;
  void set(String k, Object? val) {
    v[k] = val;
    notifyListeners();
  }
}

/// Composition root: owns engine services for the whole app.
class Services {
  static late Services i;
  final Directory root;
  final MediaRunner runner;
  final ProjectStore store;
  final KvStore kv;
  final RenderQueue queue;
  final GoogleAuth auth = GoogleAuth();
  final AppSettings settings = AppSettings();
  final L10n l10n = L10n();
  final PlatformProfiles profiles = PlatformProfiles();
  late final PublishHistory publishHistory;
  final String fontsDir;
  final String deviceId;
  SyncEngine? sync;
  final syncStatus = ValueNotifier<String>('');
  final syncBusy = ValueNotifier<bool>(false);
  Timer? _syncTimer;
  final _analysisCache = <String, AudioAnalysis>{};

  Services._(this.root, this.runner, this.store, this.kv, this.queue, this.fontsDir, this.deviceId) {
    publishHistory = PublishHistory(File('${root.path}/publish_history.json'));
  }

  static Future<Services> init() async {
    final docs = await getApplicationSupportDirectory();
    final root = Directory('${docs.path}/WoJanMediaStudio');
    await root.create(recursive: true);
    // Device identity (random, not hardware-derived; no telemetry).
    final idFile = File('${root.path}/device_id');
    if (!idFile.existsSync()) idFile.writeAsStringSync(const Uuid().v4());
    final deviceId = idFile.readAsStringSync().trim();
    // Bundled OFL fonts → fonts dir (libass/fontconfig)
    final fontsDir = Directory('${root.path}/fonts');
    await fontsDir.create(recursive: true);
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final a in manifest.listAssets().where((a) => a.startsWith('assets/fonts/'))) {
      final f = File('${fontsDir.path}/${a.split('/').last}');
      if (!f.existsSync()) {
        final data = await rootBundle.load(a);
        await f.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      }
    }
    // Effect textures (original artwork) → fx dir for the FFmpeg renderer.
    final fxDir = Directory('${root.path}/fx');
    await fxDir.create(recursive: true);
    for (final a in manifest.listAssets().where((a) => a.startsWith('assets/fx/'))) {
      final data = await rootBundle.load(a);
      final f = File('${fxDir.path}/${a.split('/').last}');
      if (!f.existsSync() || f.lengthSync() != data.lengthInBytes) {
        await f.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      }
    }
    FxAssets.dir = fxDir.path;
    PreviewFonts.ensure(userFontsDir: fontsDir.path);
    MediaRunner runner;
    if (Platform.isAndroid || Platform.isWindows || Platform.isMacOS) {
      await KitRunner.init(fontsDir: fontsDir.path);
      runner = KitRunner();
    } else {
      runner = ProcessRunner();
    }
    sqf.DatabaseFactory factory;
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      factory = sqf.databaseFactory;
    } else {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    }
    final store = ProjectStore(root: root, dbFactory: factory, runner: runner, deviceId: deviceId);
    await store.open();
    final kv = KvStore(Directory('${root.path}/kv'));
    final s = Services._(root, runner, store, kv, RenderQueue(freeSpace: freeSpace), fontsDir.path, deviceId);
    i = s;
    final saved = kv.get('settings', 'app');
    if (saved != null) s.settings.v.addAll(saved);
    s.l10n.setLang(s.settings.get<String>('lang'));
    s.settings.addListener(() {
      kv.put('settings', 'app', s.settings.v);
      s.l10n.setLang(s.settings.get<String>('lang'));
    });
    final prof = kv.get('profiles', 'platforms');
    if (prof != null) s.profiles.updateFromJson(jsonEncode(prof));
    try {
      await s.auth.restore();
    } catch (_) {/* secure storage unavailable – stay signed out */}
    await s._setupSync();
    return s;
  }

  String t(String k) => l10n.t(k);

  VideoRenderer videoRenderer() => VideoRenderer(runner, Directory('${store.cacheDir.path}/render'), fontsDir);

  Directory get exportsDir => store.exportsDir;

  /// Cached music analysis per asset (stored as JSON in cache).
  Future<AudioAnalysis> analyze(String path, String cacheKey) async {
    final c = _analysisCache[cacheKey];
    if (c != null) return c;
    final f = File('${store.cacheDir.path}/analysis_$cacheKey.json');
    if (f.existsSync()) {
      try {
        return _analysisCache[cacheKey] = AudioAnalysis.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      } catch (_) {}
    }
    final pcm = await PcmDecoder(runner, Directory('${store.cacheDir.path}/pcm')).decode(path);
    final a = await compute(_analyzeIsolate, pcm);
    await f.writeAsString(jsonEncode(a.toJson()));
    return _analysisCache[cacheKey] = a;
  }

  List<StyleTemplate> userStyles() => kv.values('templates').map(StyleTemplate.fromJson).toList();

  // ---------------------------------------------------------------- sync
  Future<void> _setupSync() async {
    RemoteStore? remote;
    final folder = settings.get<String>('syncFolder');
    if (folder.isNotEmpty) {
      remote = FolderRemoteStore(Directory(folder));
    } else if (auth.signedIn) {
      remote = DriveRemoteStore(token: ({bool forceRefresh = false}) => auth.accessToken(forceRefresh: forceRefresh), sessions: UploadSessionStore(File('${root.path}/upload_sessions.json')));
    }
    if (remote == null) {
      sync = null;
      return;
    }
    sync = SyncEngine(
      remote: remote,
      store: store,
      kv: kv,
      deviceId: deviceId,
      deviceName: Platform.isAndroid ? 'Android' : Platform.isWindows ? 'Windows ${Platform.localHostname}' : Platform.localHostname,
      platform: Platform.operatingSystem,
      stateFile: File('${root.path}/sync_state.json'),
      eagerDownloadLimit: (settings.get<num>('eagerDownloadMB') * 1024 * 1024).round(),
    );
    _syncTimer?.cancel();
    if (settings.get<bool>('autoSync')) {
      _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) => syncNow(silent: true));
      Timer(const Duration(seconds: 3), () => syncNow(silent: true));
    }
  }

  Future<void> reconfigureSync() => _setupSync();

  Future<SyncReport?> syncNow({bool silent = false}) async {
    final s = sync;
    if (s == null || syncBusy.value) return null;
    if (settings.get<bool>('wifiOnly') && !await NativeBridge.isUnmeteredNetwork()) {
      syncStatus.value = 'Oczekuje na Wi-Fi (włączono „tylko Wi-Fi”)';
      return null;
    }
    syncBusy.value = true;
    syncStatus.value = 'Synchronizacja…';
    try {
      final rep = await s.syncAll();
      syncStatus.value = '${syncStateNames[rep.overall]} • $rep';
      return rep;
    } catch (e) {
      syncStatus.value = 'Błąd: $e';
      return null;
    } finally {
      syncBusy.value = false;
    }
  }
}

AudioAnalysis _analyzeIsolate(PcmData p) => AudioAnalyzer.analyze(p);
