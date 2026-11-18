import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/services.dart';
import '../../engine/dsp/analysis.dart';
import '../../engine/export/video_export.dart';
import '../../engine/ffmpeg/probe.dart';
import '../../engine/project/format.dart';
import '../../engine/render/queue.dart';
import '../../engine/util/json_util.dart';
import '../../platform/native.dart';
import '../shell.dart';
import '../widgets/common.dart';
import '../widgets/player.dart';
import 'publisher_screen.dart';

/// Queues a project render and opens the result screen when it finishes.
Future<void> queueVideoRender(BuildContext context, ProjectDoc doc, VideoExportSettings s, {String? outPath, bool openResult = true}) async {
  final svc = Services.i;
  final v = doc.video!;
  final out = outPath ?? exportPath(doc.name, s.extension);
  AudioAnalysis? music;
  if (v.musicAssetId != null && doc.assets.containsKey(v.musicAssetId)) {
    music = await svc.analyze(svc.store.resolver(doc).pathOf(v.musicAssetId!), doc.assets[v.musicAssetId]!.sha256);
  }
  final musicClip = v.audio.tracks.expand((t) => t.clips).where((c) => c.assetId == v.musicAssetId).firstOrNull;
  final offset = musicClip == null ? 0.0 : musicClip.position - musicClip.srcIn;
  final job = RenderJob(
    title: doc.name,
    outputPath: out,
    expectedDuration: (s.rangeEnd ?? v.duration) - (s.rangeStart ?? 0),
    estimatedBytes: s.estimateBytes(v.duration),
    run: (p, c) async {
      s.encoder = EncoderPreference.values.firstWhere((e) => e.name == svc.settings.get<String>('encoder'), orElse: () => EncoderPreference.auto);
      await svc.videoRenderer().render(v, svc.store.resolver(doc), s, out, music: music, musicOffset: offset, onProgress: p, cancel: c);
    },
  );
  doc.renderStatus = RenderStatus.queued;
  await svc.store.save(doc);
  svc.queue.add(job);
  if (!context.mounted) return;
  toast(context, 'Dodano do kolejki renderowania: ${doc.name}');
  if (!openResult) return;
  final done = await svc.queue.changes.firstWhere((j) => j == job && (j.state == JobState.done || j.state == JobState.failed || j.state == JobState.cancelled));
  doc.renderStatus = done.state == JobState.done ? RenderStatus.done : RenderStatus.failed;
  doc.extra['lastRender'] = done.state == JobState.done ? out : null;
  await svc.store.save(doc);
  if (!context.mounted) return;
  if (done.state == JobState.done) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => RenderResultScreen(path: out, project: doc)));
  } else if (done.state == JobState.failed) {
    toast(context, 'Renderowanie nie powiodło się: ${done.error}', error: true);
  }
}

/// Screen shown after rendering (requirement §11 "Ekran po renderowaniu").
class RenderResultScreen extends StatefulWidget {
  final String path;
  final ProjectDoc? project;
  const RenderResultScreen({super.key, required this.path, this.project});
  @override
  State<RenderResultScreen> createState() => _RenderResultScreenState();
}

class _RenderResultScreenState extends State<RenderResultScreen> {
  MediaInfo? info;
  bool get isAudio => ['mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg', 'opus', 'wma', 'aiff'].contains(extOf(widget.path));

  @override
  void initState() {
    super.initState();
    Services.i.runner.probeJson(widget.path).then((j) => setState(() => info = MediaInfo.fromProbe(widget.path, j))).catchError((_) {});
  }

  String get mime => isAudio ? 'audio/*' : (widget.path.endsWith('.gif') ? 'image/gif' : 'video/*');

  @override
  Widget build(BuildContext context) {
    final d = widget.project?.publish;
    final aspect = info?.displayWidth != null ? info!.displayWidth! / info!.displayHeight! : 16 / 9;
    return Scaffold(
      appBar: AppBar(title: const Text('Gotowe!')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ConstrainedBox(constraints: const BoxConstraints(maxHeight: 520), child: Center(child: PreviewPlayer(path: widget.path, audioOnly: isAudio, aspect: aspect))),
        const SizedBox(height: 12),
        if (info != null) Section(title: 'Plik', children: [SelectableText(widget.path), const SizedBox(height: 6), MediaInfoView(info!)]),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(icon: const Icon(Icons.save_alt), label: Text(tr('save_device')), onPressed: _save),
          FilledButton.icon(icon: const Icon(Icons.share), label: Text(tr('share')), onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile(widget.path)], text: d?.title))),
          FilledButton.tonalIcon(icon: const Icon(Icons.public), label: Text(tr('publish')), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PublisherScreen(initialFile: widget.path, project: widget.project)))),
          FilledButton.tonalIcon(icon: const Icon(Icons.schedule), label: Text(tr('schedule')), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PublisherScreen(initialFile: widget.path, project: widget.project, schedule: true)))),
          OutlinedButton.icon(icon: const Icon(Icons.copy), label: Text(tr('copy_desc')), onPressed: () {
            Clipboard.setData(ClipboardData(text: '${d?.title ?? ''}\n\n${d?.description ?? ''}'));
            toast(context, 'Skopiowano opis');
          }),
          OutlinedButton.icon(icon: const Icon(Icons.tag), label: Text(tr('copy_tags')), onPressed: () {
            Clipboard.setData(ClipboardData(text: (d?.hashtags ?? []).join(' ')));
            toast(context, 'Skopiowano hashtagi');
          }),
          if (isDesktop) OutlinedButton.icon(icon: const Icon(Icons.folder_open), label: Text(tr('open_folder')), onPressed: () => NativeBridge.revealInFolder(widget.path)),
          if (widget.project != null)
            OutlinedButton.icon(icon: const Icon(Icons.edit), label: Text(tr('back_to_project')), onPressed: () {
              Navigator.pop(context);
              Nav.openProject(widget.project!);
            }),
          if (widget.project != null)
            OutlinedButton.icon(icon: const Icon(Icons.copy_all), label: Text(tr('new_version')), onPressed: () async {
              final copy = await Services.i.store.duplicate(widget.project!.id);
              if (!context.mounted) return;
              Navigator.pop(context);
              Nav.openProject(copy);
            }),
        ]),
        const SizedBox(height: 8),
        if (info != null) Text('Rozmiar: ${fmtBytes(File(widget.path).lengthSync())} • bez znaku wodnego', style: const TextStyle(color: Colors.grey)),
      ]),
    );
  }

  Future<void> _save() async {
    if (Platform.isAndroid) {
      final uri = await NativeBridge.saveToGallery(widget.path, isAudio ? 'audio/${extOf(widget.path)}' : (widget.path.endsWith('.gif') ? 'image/gif' : 'video/mp4'));
      if (mounted) toast(context, uri == null ? 'Nie udało się zapisać' : 'Zapisano w ${isAudio ? 'Muzyka' : 'Filmy'}/WoJan Media Studio');
    } else {
      final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Wybierz folder docelowy');
      if (dir == null || dir.isEmpty) return;
      final dest = '$dir${Platform.pathSeparator}${widget.path.split(RegExp(r'[\\/]')).last}';
      await File(dest).parent.create(recursive: true);
      await File(widget.path).copy(dest);
      if (mounted) toast(context, 'Zapisano: $dest');
    }
  }
}
