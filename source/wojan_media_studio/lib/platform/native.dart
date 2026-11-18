import 'dart:io';

import 'package:flutter/services.dart';

/// Thin wrapper over the Android native channel implemented in
/// MainActivity.kt (MediaStore, targeted share intents, APK install,
/// ringtones, connectivity, battery/thermal state).
class NativeBridge {
  static const _c = MethodChannel('pl.wojan.mediastudio/native');

  /// Saves a file to public storage via MediaStore (Movies/Music/Pictures
  /// /WoJan Media Studio). Returns content URI.
  static Future<String?> saveToGallery(String path, String mime, {String? displayName}) async {
    if (!Platform.isAndroid) return null;
    return _c.invokeMethod<String>('saveToMediaStore', {'path': path, 'mime': mime, 'name': displayName ?? path.split('/').last});
  }

  /// Apps able to receive [mime] via ACTION_SEND (package, label).
  static Future<List<Map<String, String>>> shareTargets(String mime) async {
    if (!Platform.isAndroid) return [];
    final l = await _c.invokeListMethod<Map>('shareTargets', {'mime': mime}) ?? [];
    return l.map((e) => e.map((k, v) => MapEntry('$k', '$v'))).toList();
  }

  /// Opens a specific app (e.g. TikTok) with the file attached.
  /// Note: this only HANDS OFF the file – publishing is completed by the user
  /// inside the target app.
  static Future<bool> shareToPackage(String path, String mime, String package, {String? text}) async {
    if (!Platform.isAndroid) return false;
    return await _c.invokeMethod<bool>('shareToPackage', {'path': path, 'mime': mime, 'package': package, 'text': text}) ?? false;
  }

  static Future<bool> installApk(String path) async {
    if (!Platform.isAndroid) return false;
    return await _c.invokeMethod<bool>('installApk', {'path': path}) ?? false;
  }

  static Future<bool> setRingtone(String path, {String type = 'ringtone'}) async {
    if (!Platform.isAndroid) return false;
    return await _c.invokeMethod<bool>('setRingtone', {'path': path, 'type': type}) ?? false;
  }

  static Future<bool> isUnmeteredNetwork() async {
    if (!Platform.isAndroid) return true;
    return await _c.invokeMethod<bool>('isUnmetered') ?? true;
  }

  static Future<bool> isPowerSaveOrHot() async {
    if (!Platform.isAndroid) return false;
    return await _c.invokeMethod<bool>('isPowerSaveOrHot') ?? false;
  }

  /// Files shared INTO the app from other apps (ACTION_SEND).
  static Future<List<String>> takeSharedFiles() async {
    if (!Platform.isAndroid) return [];
    return (await _c.invokeListMethod<String>('takeSharedFiles')) ?? [];
  }

  /// Windows: opens Explorer with the file selected.
  static Future<void> revealInFolder(String path) async {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', path.replaceAll('/', '\\')]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [File(path).parent.path]);
    }
  }
}
