import 'package:material_ui/material_ui.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../engine/ffmpeg/probe.dart';
import '../../engine/project/asset.dart';
import '../../engine/util/json_util.dart';
import '../widgets/common.dart';
import '../widgets/player.dart';
import 'video_widgets.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  MediaKind? kind;
  List<MediaAsset> items = [];
  String q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await Services.i.store.listMedia(kind: kind);
    setState(() => items = l.where((a) => q.isEmpty || a.name.toLowerCase().contains(q.toLowerCase())).toList());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(onPressed: () async {
          await importMedia(context, [...audioExt, ...videoExt, ...imageExt]);
          _load();
        }, icon: const Icon(Icons.add), label: Text(tr('import'))),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(width: 260, child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search)), onChanged: (v) => {q = v, _load()})),
              for (final k in [null, MediaKind.audio, MediaKind.video, MediaKind.image])
                ChoiceChip(label: Text(switch (k) { null => 'Wszystko', MediaKind.audio => 'Audio', MediaKind.video => 'Wideo', _ => 'Obrazy' }), selected: kind == k, onSelected: (_) => {kind = k, _load()}),
              TextButton.icon(onPressed: () async {
                final n = await Services.i.store.garbageCollectMedia();
                if (context.mounted) toast(context, 'Usunięto $n nieużywanych plików (oryginały poza aplikacją nie są nigdy usuwane)');
                _load();
              }, icon: const Icon(Icons.cleaning_services), label: const Text('Usuń nieużywane kopie')),
            ]),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200, childAspectRatio: 0.85, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: items.length,
              itemBuilder: (c, i) {
                final a = items[i];
                final path = Services.i.store.mediaPath(a.relPath);
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () async {
                      final info = MediaInfo.fromProbe(path, await Services.i.runner.probeJson(path));
                      if (!context.mounted) return;
                      showDialog<void>(
                        context: context,
                        builder: (d) => AlertDialog(
                          title: Text(a.name),
                          content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            if (a.kind != MediaKind.image) PreviewPlayer(path: path, audioOnly: a.kind == MediaKind.audio, aspect: (a.width ?? 16) / (a.height ?? 9)),
                            MediaInfoView(info),
                            Text('SHA-256: ${a.sha256}', style: const TextStyle(fontSize: 10, color: WmsColors.muted)),
                          ]))),
                          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
                        ),
                      );
                    },
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(child: a.kind == MediaKind.audio ? Container(color: WmsColors.panel2, child: const Icon(Icons.music_note, size: 48, color: WmsColors.accent)) : ClipThumb(path: path, size: 200)),
                      Padding(padding: const EdgeInsets.all(6), child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Padding(padding: const EdgeInsets.fromLTRB(6, 0, 6, 6), child: Text('${a.kind == MediaKind.image ? '${a.width}×${a.height}' : fmtTime(a.duration)} • ${fmtBytes(a.size)}', style: const TextStyle(fontSize: 11, color: WmsColors.muted))),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      );
}
