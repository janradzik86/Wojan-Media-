import 'dart:async';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../engine/ffmpeg/runner.dart';

/// FFmpegKit based runner (Android / Windows): FFmpeg runs in-process,
/// arguments are passed as a list (no shell, no injection).
class KitRunner extends MediaRunner {
  static Future<void> init({String? fontsDir}) async {
    await FFmpegKitConfig.enableLogs();
    if (fontsDir != null) {
      await FFmpegKitConfig.setFontDirectoryList([fontsDir], {});
    }
  }

  @override
  Future<RunResult> ffmpeg(List<String> args, {ProgressCb? onProgress, CancelToken? cancel}) async {
    final buf = StringBuffer();
    final done = Completer<RunResult>();
    final full = ['-hide_banner', '-nostdin', '-y', ...args];
    final session = await FFmpegKit.executeWithArgumentsAsync(
      full,
      (s) async {
        final rc = await s.getReturnCode();
        // Log callbacks are asynchronous and may arrive after completion –
        // read the complete session log (waits for pending entries).
        final all = await s.getAllLogsAsString(5000) ?? '';
        done.complete(RunResult(rc?.getValue() ?? -1, all.length >= buf.length ? all : buf.toString(), cancelled: ReturnCode.isCancel(rc)));
      },
      (log) => buf.write(log.getMessage()),
      (stat) {
        final t = stat.getTime();
        if (onProgress != null && t > 0) onProgress(t / 1000.0);
      },
    );
    final id = session.getSessionId();
    cancel?.onCancel(() {
      if (id != null) FFmpegKit.cancel(id);
    });
    return done.future;
  }

  @override
  Future<RunResult> ffprobe(List<String> args) async {
    final s = await FFprobeKit.executeWithArguments(args);
    final rc = await s.getReturnCode();
    final out = await s.getOutput() ?? '';
    return RunResult(rc?.getValue() ?? -1, out);
  }
}
