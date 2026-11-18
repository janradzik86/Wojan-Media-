import 'package:material_ui/material_ui.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../engine/render/queue.dart';
import '../widgets/common.dart';
import 'render_result.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final q = Services.i.queue;
    return StreamBuilder<RenderJob>(
      stream: q.changes,
      builder: (c, _) => ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          Text('Zadania: ${q.jobs.length}', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          TextButton(onPressed: () => {q.clearFinished(), (c as Element).markNeedsBuild()}, child: const Text('Wyczyść zakończone')),
        ]),
        if (q.jobs.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Kolejka jest pusta. Renderowanie działa w tle – możesz dalej edytować.'))),
        for (final j in q.jobs.reversed)
          Card(
            child: ListTile(
              leading: Icon(switch (j.state) {
                JobState.queued => Icons.schedule,
                JobState.running => Icons.autorenew,
                JobState.done => Icons.check_circle,
                JobState.failed => Icons.error,
                JobState.cancelled => Icons.cancel,
              }, color: j.state == JobState.failed ? WmsColors.error : j.state == JobState.done ? WmsColors.accent : null),
              title: Text(j.title),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (j.state == JobState.running) LinearProgressIndicator(value: j.progress > 0 ? j.progress : null),
                Text(switch (j.state) {
                  JobState.running => '${(j.progress * 100).toStringAsFixed(1)}%${j.eta != null ? ' • pozostało ok. ${j.eta!.inMinutes} min ${j.eta!.inSeconds % 60} s' : ''}',
                  JobState.failed => 'Błąd: ${j.error}',
                  JobState.done => 'Gotowe • ${j.outputPath}',
                  JobState.cancelled => 'Anulowano',
                  JobState.queued => 'W kolejce • szac. ${fmtBytesSafe(j.estimatedBytes)}',
                }, maxLines: 3, overflow: TextOverflow.ellipsis),
              ]),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (j.state == JobState.running || j.state == JobState.queued) IconButton(tooltip: 'Anuluj', icon: const Icon(Icons.stop), onPressed: () => q.cancel(j)),
                if (j.state == JobState.failed || j.state == JobState.cancelled) IconButton(tooltip: 'Ponów', icon: const Icon(Icons.replay), onPressed: () => q.retry(j)),
                if (j.state == JobState.done) IconButton(tooltip: 'Otwórz', icon: const Icon(Icons.open_in_new), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RenderResultScreen(path: j.outputPath)))),
              ]),
            ),
          ),
      ]),
    );
  }
}

String fmtBytesSafe(int b) => b <= 0 ? '?' : '${(b / 1048576).toStringAsFixed(0)} MB';
