import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../engine/ffmpeg/probe.dart';
import '../widgets/common.dart';
import 'render_result.dart';
import 'video_widgets.dart';

/// "Moje dzieło" – every file the app produced (exports, renders, audio
/// tools, batch output), newest first, split into audio and video.
class WorksScreen extends StatefulWidget {
  const WorksScreen({super.key});
  @override
  State<WorksScreen> createState() => _WorksScreenState();
}

class _WorksScreenState extends State<WorksScreen> {
  List<File> files = [];
  int tab = 0; // 0 wideo, 1 audio, 2 obrazy

  @override
  void initState() {
    super.initState();
    _scan();
  }

  void _scan() {
    final dir = Services.i.exportsDir;
    final all = dir.existsSync() ? dir.listSync(recursive: true).whereType<File>().where((f) => !f.path.endsWith('.tmp') && f.lengthSync() > 0).toList() : <File>[];
    all.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    setState(() => files = all);
  }

  bool _isVideo(String p) => videoExt.contains(extOf(p));
  bool _isAudio(String p) => audioExt.contains(extOf(p));

  @override
  Widget build(BuildContext context) {
    final shown = files.where((f) => tab == 0 ? _isVideo(f.path) : tab == 1 ? _isAudio(f.path) : !_isVideo(f.path) && !_isAudio(f.path)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(children: [
          Text('Moje dzieło', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          IconButton(tooltip: 'Odśwież', onPressed: _scan, icon: const Icon(Icons.refresh)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SegmentedButton<int>(
          segments: [
            ButtonSegment(value: 0, icon: const Icon(Icons.movie), label: Text('Wideo (${files.where((f) => _isVideo(f.path)).length})')),
            ButtonSegment(value: 1, icon: const Icon(Icons.audiotrack), label: Text('Audio (${files.where((f) => _isAudio(f.path)).length})')),
            const ButtonSegment(value: 2, icon: Icon(Icons.folder), label: Text('Inne')),
          ],
          selected: {tab},
          onSelectionChanged: (v) => setState(() => tab = v.first),
        ),
      ),
      Expanded(
        child: shown.isEmpty
            ? const Center(child: Text('Brak plików. Wyrenderowane filmy i zapisane nagrania pojawią się tutaj.', style: TextStyle(color: WmsColors.muted)))
            : ListView.builder(
                itemCount: shown.length,
                itemBuilder: (c, i) {
                  final f = shown[i];
                  final name = f.path.split(RegExp(r'[\\/]')).last;
                  final mb = f.lengthSync() / 1048576;
                  return ListTile(
                    leading: _isVideo(f.path) ? SizedBox(width: 64, height: 40, child: ClipThumb(path: f.path, at: 0.5, size: 64)) : Icon(_isAudio(f.path) ? Icons.audiotrack : Icons.insert_drive_file, size: 32),
                    title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${f.lastModifiedSync().toString().substring(0, 16)} • ${mb.toStringAsFixed(mb < 10 ? 2 : 1)} MB'),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RenderResultScreen(path: f.path))).then((_) => _scan()),
                    trailing: IconButton(
                      tooltip: 'Usuń plik',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Usunąć plik?'), content: Text(name), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anuluj')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Usuń'))]));
                        if (ok == true) {
                          await f.delete();
                          _scan();
                        }
                      },
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
