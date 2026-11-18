import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Result of an FFmpeg/FFprobe execution.
class RunResult {
  final int code;
  final String log;
  final bool cancelled;
  RunResult(this.code, this.log, {this.cancelled = false});
  bool get ok => code == 0 && !cancelled;

  /// Last meaningful error lines for user-facing messages.
  String get errorSummary {
    final lines = log
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .where((e) => !e.startsWith('frame=') && !e.startsWith('size='))
        .toList();
    return lines.length <= 6 ? lines.join('\n') : lines.sublist(lines.length - 6).join('\n');
  }
}

class CancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void onCancel(void Function() f) => _listeners.add(f);
}

class MediaEngineException implements Exception {
  final String message;
  final String? details;
  MediaEngineException(this.message, [this.details]);
  @override
  String toString() => details == null ? message : '$message\n$details';
}

/// Progress callback receives processed media time in seconds.
typedef ProgressCb = void Function(double seconds);

/// Platform abstraction for running FFmpeg. Arguments are ALWAYS passed as a
/// list – no shell is involved anywhere.
abstract class MediaRunner {
  Future<RunResult> ffmpeg(List<String> args,
      {ProgressCb? onProgress, CancelToken? cancel});
  Future<RunResult> ffprobe(List<String> args);

  /// Raw ffprobe JSON describing [path].
  Future<Map<String, dynamic>> probeJson(String path) async {
    final r = await ffprobe([
      '-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', path
    ]);
    if (!r.ok) {
      throw MediaEngineException('Nie można odczytać pliku: $path', r.errorSummary);
    }
    final start = r.log.indexOf('{');
    if (start < 0) throw MediaEngineException('Brak danych FFprobe dla $path');
    return jsonDecode(r.log.substring(start)) as Map<String, dynamic>;
  }

  /// Runs ffmpeg and throws a readable exception on failure.
  Future<void> run(List<String> args, {ProgressCb? onProgress, CancelToken? cancel, String? what}) async {
    final r = await ffmpeg(args, onProgress: onProgress, cancel: cancel);
    if (r.cancelled) throw MediaEngineException('Operacja anulowana');
    if (!r.ok) {
      throw MediaEngineException(what ?? 'Błąd silnika multimedialnego (FFmpeg kod ${r.code})', r.errorSummary);
    }
  }
}

final _timeRe = RegExp(r'time=(\d+):(\d+):(\d+(?:\.\d+)?)');
final _outTimeRe = RegExp(r'out_time_us=(\d+)');

double? parseProgressTime(String line) {
  final m = _outTimeRe.firstMatch(line);
  if (m != null) return int.parse(m.group(1)!) / 1e6;
  final t = _timeRe.firstMatch(line);
  if (t != null) {
    return int.parse(t.group(1)!) * 3600 + int.parse(t.group(2)!) * 60 + double.parse(t.group(3)!);
  }
  return null;
}

/// Runner based on external ffmpeg/ffprobe executables (Linux tests,
/// optional desktop fallback). Uses Process.start with an argument list.
class ProcessRunner extends MediaRunner {
  final String ffmpegPath;
  final String ffprobePath;
  ProcessRunner({this.ffmpegPath = 'ffmpeg', this.ffprobePath = 'ffprobe'});

  @override
  Future<RunResult> ffmpeg(List<String> args, {ProgressCb? onProgress, CancelToken? cancel}) async {
    final full = ['-hide_banner', '-nostdin', '-y', ...args];
    final p = await Process.start(ffmpegPath, full, runInShell: false);
    final buf = StringBuffer();
    var cancelled = false;
    cancel?.onCancel(() {
      cancelled = true;
      p.kill();
    });
    final done = Completer<void>();
    var pending = 2;
    void fin() {
      if (--pending == 0) done.complete();
    }

    p.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
      buf.writeln(l);
      if (onProgress != null) {
        for (final part in l.split('\r')) {
          final t = parseProgressTime(part);
          if (t != null) onProgress(t);
        }
      }
    }, onDone: fin);
    p.stdout.transform(utf8.decoder).listen(buf.write, onDone: fin);
    final code = await p.exitCode;
    await done.future;
    return RunResult(code, buf.toString(), cancelled: cancelled);
  }

  @override
  Future<RunResult> ffprobe(List<String> args) async {
    final r = await Process.run(ffprobePath, args, runInShell: false, stdoutEncoding: utf8, stderrEncoding: utf8);
    return RunResult(r.exitCode, '${r.stdout}\n${r.stderr}');
  }
}
