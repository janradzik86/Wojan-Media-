import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('pl.wojan.mediastudio/native');

typedef _GetDiskFreeSpaceExNative = Int32 Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _GetDiskFreeSpaceExDart = int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);

/// Free disk space for [path] in bytes (null if unknown).
Future<int?> freeSpace(String path) async {
  try {
    if (Platform.isWindows) {
      final k32 = DynamicLibrary.open('kernel32.dll');
      final f = k32.lookupFunction<_GetDiskFreeSpaceExNative, _GetDiskFreeSpaceExDart>('GetDiskFreeSpaceExW');
      final p = path.toNativeUtf16();
      final a = calloc<Uint64>(), b = calloc<Uint64>(), c = calloc<Uint64>();
      try {
        if (f(p, a, b, c) != 0) return a.value;
      } finally {
        calloc.free(p);
        calloc.free(a);
        calloc.free(b);
        calloc.free(c);
      }
      return null;
    }
    if (Platform.isAndroid) {
      return await _channel.invokeMethod<int>('freeSpace', {'path': path});
    }
    final r = await Process.run('df', ['-B1', '--output=avail', path]);
    final lines = (r.stdout as String).trim().split('\n');
    return int.tryParse(lines.last.trim());
  } catch (_) {
    return null;
  }
}
