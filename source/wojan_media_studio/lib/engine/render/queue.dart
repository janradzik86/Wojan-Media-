import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../ffmpeg/runner.dart';

enum JobState { queued, running, done, failed, cancelled }

/// Free disk space provider (platform specific implementation injected).
typedef FreeSpaceFn = Future<int?> Function(String path);

class RenderJob {
  final String id = const Uuid().v4();
  final String title;
  final String outputPath;
  final double expectedDuration; // media seconds (progress basis)
  final int estimatedBytes;
  final Future<void> Function(ProgressCb onProgress, CancelToken cancel) run;
  JobState state = JobState.queued;
  double progress = 0; // 0..1
  DateTime? started, finished;
  String? error;
  CancelToken cancel = CancelToken();
  int attempts = 0;
  RenderJob({required this.title, required this.outputPath, required this.expectedDuration, required this.run, this.estimatedBytes = 0});

  /// Estimated remaining time based on measured throughput.
  Duration? get eta {
    if (started == null || progress <= 0.01 || state != JobState.running) return null;
    final el = DateTime.now().difference(started!);
    return Duration(milliseconds: (el.inMilliseconds * (1 - progress) / progress).round());
  }
}

/// Sequential render queue (one heavy job at a time keeps devices cool and
/// the UI responsive; FFmpeg itself is multi-threaded).
class RenderQueue {
  final List<RenderJob> jobs = [];
  final FreeSpaceFn freeSpace;
  final _changes = StreamController<RenderJob>.broadcast();
  bool _running = false;
  bool paused = false;
  RenderQueue({required this.freeSpace});

  Stream<RenderJob> get changes => _changes.stream;

  void add(RenderJob j) {
    jobs.add(j);
    _changes.add(j);
    _pump();
  }

  void cancel(RenderJob j) {
    if (j.state == JobState.queued) {
      j.state = JobState.cancelled;
      _changes.add(j);
    } else if (j.state == JobState.running) {
      j.cancel.cancel();
    }
  }

  void retry(RenderJob j) {
    if (j.state == JobState.failed || j.state == JobState.cancelled) {
      j.state = JobState.queued;
      j.progress = 0;
      j.error = null;
      j.cancel = CancelToken();
      _changes.add(j);
      _pump();
    }
  }

  void clearFinished() => jobs.removeWhere((j) => j.state == JobState.done || j.state == JobState.cancelled);

  Future<void> _pump() async {
    if (_running || paused) return;
    _running = true;
    try {
      while (!paused) {
        final next = jobs.where((j) => j.state == JobState.queued).firstOrNull;
        if (next == null) break;
        await _runJob(next);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _runJob(RenderJob j) async {
    j.state = JobState.running;
    j.started = DateTime.now();
    j.attempts++;
    _changes.add(j);
    try {
      final free = await freeSpace(File(j.outputPath).parent.path);
      if (free != null && j.estimatedBytes > 0 && free < j.estimatedBytes * 1.5 + 200 * 1024 * 1024) {
        throw MediaEngineException('Za mało miejsca na dysku: wolne ${(free / 1048576).round()} MB, potrzeba ok. ${(j.estimatedBytes * 1.5 / 1048576).round()} MB');
      }
      await File(j.outputPath).parent.create(recursive: true);
      final tmpOut = j.outputPath;
      await j.run((t) {
        if (j.expectedDuration > 0) {
          j.progress = (t / j.expectedDuration).clamp(0.0, 0.999);
          _changes.add(j);
        }
      }, j.cancel);
      if (!File(tmpOut).existsSync() || File(tmpOut).lengthSync() == 0) throw MediaEngineException('Plik wynikowy nie powstał');
      j.progress = 1;
      j.state = JobState.done;
    } on MediaEngineException catch (e) {
      j.state = j.cancel.isCancelled ? JobState.cancelled : JobState.failed;
      j.error = e.toString();
      _cleanupPartial(j);
    } catch (e) {
      j.state = j.cancel.isCancelled ? JobState.cancelled : JobState.failed;
      j.error = '$e';
      _cleanupPartial(j);
    }
    j.finished = DateTime.now();
    _changes.add(j);
  }

  void _cleanupPartial(RenderJob j) {
    // Remove only the (incomplete) OUTPUT file – never source material.
    final f = File(j.outputPath);
    if (f.existsSync()) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }
}
