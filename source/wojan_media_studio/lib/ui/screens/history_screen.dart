import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../engine/project/format.dart';
import '../../engine/publish/history.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final recs = [...Services.i.publishHistory.records]..sort((a, b) => b.updated.compareTo(a.updated));
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text('Historia publikacji (${recs.length})', style: Theme.of(context).textTheme.titleLarge),
      if (recs.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Brak publikacji.')),
      for (final r in recs)
        Card(
          child: ListTile(
            leading: Icon(switch (r.status) {
              PublishStatus.published => Icons.public,
              PublishStatus.scheduled => Icons.schedule,
              PublishStatus.uploaded => Icons.cloud_done,
              PublishStatus.handedOff => Icons.send_to_mobile,
              PublishStatus.error => Icons.error,
              PublishStatus.uploading => Icons.cloud_upload,
              _ => Icons.drafts,
            }, color: r.status == PublishStatus.error ? WmsColors.error : WmsColors.accent),
            title: Text('${r.title.isEmpty ? r.filePath.split(RegExp(r'[\\/]')).last : r.title} → ${Services.i.profiles[r.platform]?.name ?? r.platform}'),
            subtitle: Text('${publishStatusNames[r.status]} • ${r.updated.toLocal().toString().substring(0, 16)}${r.scheduledAt != null ? ' • zaplanowano: ${r.scheduledAt!.toLocal().toString().substring(0, 16)}' : ''}${r.error != null ? '\n${r.error}' : ''}'),
            trailing: r.url == null ? null : IconButton(icon: const Icon(Icons.open_in_new), onPressed: () => launchUrl(Uri.parse(r.url!), mode: LaunchMode.externalApplication)),
          ),
        ),
    ]);
  }
}
