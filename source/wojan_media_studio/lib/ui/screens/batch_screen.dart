import 'package:material_ui/material_ui.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../engine/batch/batch.dart';
import '../../engine/dsp/analysis.dart';
import '../../engine/musicvideo/auto.dart';
import '../../engine/musicvideo/styles.dart';
import '../../engine/project/asset.dart';
import '../../engine/project/format.dart';
import '../../engine/render/queue.dart';
import '../widgets/common.dart';

/// Batch production: many songs + covers → a queue of complete music videos
/// for several platforms/resolutions with one shared template.
class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key});
  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  final songs = <MediaAsset>[];
  final covers = <MediaAsset>[];
  late StyleTemplate style = factoryStyles.first;
  MusicVideoMode mode = MusicVideoMode.animatedCover;
  final platforms = <String>{'youtube', 'tiktok'};
  List<BatchItem> pairs = [];
  String status = '';

  void _pair() => setState(() => pairs = BatchPlanner.pair(songs, covers));

  Future<void> _start() async {
    final s = Services.i;
    final analyses = <String, AudioAnalysis>{};
    for (var i = 0; i < songs.length; i++) {
      setState(() => status = 'Analiza ${i + 1}/${songs.length}: ${songs[i].name}');
      analyses[songs[i].id] = await s.analyze(s.store.mediaPath(songs[i].relPath), songs[i].sha256);
    }
    final plan = BatchPlanner.plan(items: pairs, analyses: analyses, style: style, mode: mode, platforms: [for (final p in platforms) s.profiles[p]!]);
    for (final o in plan) {
      final d = await s.store.create('${o.item.title} – ${o.platform?.name ?? '${o.settings.height}p'}', ProjectType.musicVideo);
      d.video = o.project;
      d.assets[o.item.song.id] = o.item.song;
      for (final c in o.item.covers) {
        d.assets[c.id] = c;
      }
      d.category = 'Wsad';
      d.tags = [style.name];
      await s.store.save(d);
      final out = '${s.exportsDir.path}/batch/${o.fileName}';
      s.queue.add(RenderJob(
        title: d.name,
        outputPath: out,
        expectedDuration: o.project.duration,
        estimatedBytes: o.settings.estimateBytes(o.project.duration),
        run: (p, c) => s.videoRenderer().render(o.project, s.store.resolver(d), o.settings, out, music: analyses[o.item.song.id], onProgress: p, cancel: c),
      ));
    }
    setState(() => status = 'Dodano ${plan.length} zadań do kolejki renderowania');
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
        Section(title: 'Utwory (${songs.length}) i okładki (${covers.length})', children: [
          Wrap(spacing: 8, children: [
            FilledButton.icon(onPressed: () async {
              songs.addAll(await importMedia(context, audioExt));
              _pair();
            }, icon: const Icon(Icons.queue_music), label: const Text('Dodaj utwory')),
            OutlinedButton.icon(onPressed: () async {
              covers.addAll(await importMedia(context, imageExt));
              _pair();
            }, icon: const Icon(Icons.image), label: const Text('Dodaj okładki')),
            TextButton(onPressed: () => setState(() => {songs.clear(), covers.clear(), pairs.clear()}), child: const Text('Wyczyść')),
          ]),
          const Text('Okładki są dopasowywane do utworów po nazwie pliku (np. utwor1.mp3 ↔ utwor1.jpg), a pozostałe kolejno.', style: TextStyle(color: WmsColors.muted, fontSize: 12)),
          for (final p in pairs) ListTile(dense: true, leading: const Icon(Icons.music_note), title: Text(p.song.name), subtitle: Text(p.covers.isEmpty ? 'bez okładki' : 'okładka: ${p.covers.first.name}')),
        ]),
        Section(title: 'Szablon i tryb', children: [
          Wrap(spacing: 6, runSpacing: 6, children: [for (final s in [...factoryStyles, ...Services.i.userStyles()]) ChoiceChip(label: Text(s.name), selected: style.id == s.id, onSelected: (_) => setState(() => style = s))]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final m in MusicVideoMode.values.where((m) => m != MusicVideoMode.album)) ChoiceChip(label: Text(musicVideoModeNames[m]!), selected: mode == m, onSelected: (_) => setState(() => mode = m))]),
        ]),
        Section(title: 'Wersje (platformy / rozdzielczości)', children: [
          Wrap(spacing: 6, runSpacing: 6, children: [for (final p in Services.i.profiles.all) FilterChip(label: Text('${p.name} ${p.width}×${p.height}'), selected: platforms.contains(p.id), onSelected: (v) => setState(() => v ? platforms.add(p.id) : platforms.remove(p.id)))]),
        ]),
        FilledButton.icon(onPressed: pairs.isEmpty || platforms.isEmpty ? null : _start, icon: const Icon(Icons.play_arrow), label: Text('Utwórz ${pairs.length * platforms.length} teledysków')),
        if (status.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(status)),
      ]);
}
