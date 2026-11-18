import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../engine/ffmpeg/probe.dart';
import '../../engine/project/format.dart';
import '../../engine/publish/history.dart';
import '../../engine/publish/package.dart';
import '../../engine/publish/platforms.dart';
import '../../engine/publish/youtube.dart';
import '../../engine/render/queue.dart';
import '../../engine/sync/remote.dart';
import '../../engine/util/hash.dart';
import '../../engine/util/json_util.dart';
import '../../engine/video/model.dart';
import '../../platform/auth.dart';
import '../../platform/native.dart';
import '../widgets/common.dart';
import 'render_result.dart';

class PublisherScreen extends StatefulWidget {
  final String? initialFile;
  final ProjectDoc? project;
  final bool schedule;
  const PublisherScreen({super.key, this.initialFile, this.project, this.schedule = false});
  @override
  State<PublisherScreen> createState() => _PublisherScreenState();
}

class _PublisherScreenState extends State<PublisherScreen> {
  String? file;
  MediaInfo? info;
  ProjectDoc? project;
  final title = TextEditingController();
  final desc = TextEditingController();
  final tags = TextEditingController();
  final selected = <String>{};
  String visibility = 'private';
  DateTime? when;
  final versions = <String, String>{}; // platform → rendered file
  final progress = <String, double>{};
  final installed = <String>{};

  @override
  void initState() {
    super.initState();
    project = widget.project;
    final d = project?.publish;
    title.text = d?.title ?? '';
    desc.text = d?.description ?? '';
    tags.text = (d?.hashtags ?? []).join(' ');
    selected.addAll(d?.platforms ?? []);
    visibility = d?.visibility ?? 'private';
    when = d?.scheduledAt;
    if (widget.schedule && when == null) when = DateTime.now().add(const Duration(days: 1));
    if (widget.initialFile != null) _setFile(widget.initialFile!);
    _detectApps();
  }

  Future<void> _detectApps() async {
    final t = await NativeBridge.shareTargets('video/*');
    setState(() => installed.addAll(t.map((e) => e['package']!)));
  }

  Future<void> _setFile(String f) async {
    final i = MediaInfo.fromProbe(f, await Services.i.runner.probeJson(f));
    setState(() {
      file = f;
      info = i;
    });
  }

  List<String> get hashtags => normalizeHashtags(tags.text);

  Future<void> _saveDraft() async {
    final p = project;
    if (p == null) return;
    p.publish
      ..title = title.text
      ..description = desc.text
      ..hashtags = hashtags
      ..platforms = selected.toList()
      ..visibility = visibility
      ..scheduledAt = when;
    p.publishStatus = PublishStatus.ready;
    await Services.i.store.save(p);
  }

  /// JEDEN PROJEKT — WIELE PLATFORM: renders a version per platform.
  Future<void> _renderVersions() async {
    final p = project;
    if (p?.video == null) return;
    for (final id in selected) {
      final prof = Services.i.profiles[id]!;
      final v = VideoProject.fromJson(p!.video!.toJson())
        ..width = prof.width
        ..height = prof.height
        ..fps = prof.fps;
      if (prof.maxDurationSec > 0 && v.duration > prof.maxDurationSec) v.fixedDuration = prof.maxDurationSec.toDouble();
      final copy = ProjectDoc.fromJson(p.toJson())..video = v;
      final out = exportPath('${p.name}_${prof.id}', 'mp4');
      setState(() => progress[id] = 0.001);
      final job = RenderJob(title: '${p.name} → ${prof.name}', outputPath: out, expectedDuration: v.duration, estimatedBytes: prof.exportSettings().estimateBytes(v.duration), run: (pr, c) async {
        final music = v.musicAssetId == null ? null : await Services.i.analyze(Services.i.store.resolver(copy).pathOf(v.musicAssetId!), copy.assets[v.musicAssetId]!.sha256);
        await Services.i.videoRenderer().render(v, Services.i.store.resolver(copy), prof.exportSettings(), out, music: music, onProgress: (t) {
          pr(t);
          if (mounted) setState(() => progress[id] = (t / v.duration).clamp(0, 1));
        }, cancel: c);
      });
      Services.i.queue.add(job);
      Services.i.queue.changes.firstWhere((j) => j == job && (j.state == JobState.done || j.state == JobState.failed)).then((j) {
        if (!mounted) return;
        setState(() {
          progress.remove(id);
          if (j.state == JobState.done) versions[id] = out;
        });
      });
    }
  }

  String _fileFor(String platform) => versions[platform] ?? file!;

  Future<PublishRecord> _record(String platform, PublishStatus st) async {
    final f = _fileFor(platform);
    final r = PublishRecord(projectId: project?.id ?? '', platform: platform, fileSha256: await sha256File(File(f)), filePath: f, title: title.text, description: desc.text, hashtags: hashtags, visibility: visibility, status: st, scheduledAt: when);
    Services.i.publishHistory.upsert(r);
    return r;
  }

  Future<void> _handOff(PlatformProfile prof) async {
    final f = _fileFor(prof.id);
    final text = [title.text, desc.text, hashtags.join(' ')].where((e) => e.isNotEmpty).join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    var ok = false;
    if (Platform.isAndroid && prof.androidPackage != null && installed.contains(prof.androidPackage)) {
      ok = await NativeBridge.shareToPackage(f, 'video/mp4', prof.androidPackage!, text: text);
    }
    if (!ok) {
      final r = await SharePlus.instance.share(ShareParams(files: [XFile(f, mimeType: 'video/mp4')], text: text, subject: title.text));
      ok = r.status != ShareResultStatus.dismissed;
    }
    if (ok) {
      await _record(prof.id, PublishStatus.handedOff);
      if (mounted) toast(context, 'Przekazano plik do ${prof.name}. Opis skopiowano do schowka – dokończ publikację w aplikacji docelowej.');
    }
  }

  Future<void> _youtube(PlatformProfile prof) async {
    final auth = Services.i.auth;
    if (!auth.hasScope(scopeYouTubeUpload)) {
      try {
        await auth.signIn([scopeYouTubeUpload, scopeYouTubeRead]);
      } catch (e) {
        if (mounted) toast(context, 'Logowanie YouTube: $e', error: true);
        return;
      }
    }
    final f = _fileFor(prof.id);
    final sha = await sha256File(File(f));
    final dup = Services.i.publishHistory.duplicateOf(sha, prof.id, account: auth.email);
    if (dup != null && mounted && !await confirm(context, 'Duplikat', 'Ten plik został już przesłany na ${prof.name} (${dup.url ?? dup.status.name}). Przesłać ponownie?')) return;
    if (!mounted) return;
    final ok = await confirm(context, 'Potwierdź publikację', 'Plik: ${f.split(RegExp(r'[\\/]')).last}\nKonto: ${auth.email}\nTytuł: ${title.text}\nWidoczność: $visibility${when != null ? '\nPublikacja zaplanowana: $when (harmonogram po stronie YouTube)' : ''}\n\nCzy na pewno przesłać?');
    if (!ok) return;
    final rec = await _record(prof.id, PublishStatus.pending)
      ..userApproved = true
      ..account = auth.email
      ..title = prof.id == 'youtube_shorts' && !title.text.toLowerCase().contains('#shorts') ? '${title.text} #shorts' : title.text;
    final up = YouTubeUploader(token: ({bool forceRefresh = false}) => auth.accessToken(forceRefresh: forceRefresh, scopes: [scopeYouTubeUpload, scopeYouTubeRead]), sessions: UploadSessionStore(File('${Services.i.root.path}/yt_sessions.json')));
    final thumb = '${Services.i.store.cacheDir.path}/yt_thumb.jpg';
    await Services.i.runner.ffmpeg(['-ss', '1', '-i', f, '-frames:v', '1', '-update', '1', '-q:v', '2', thumb]);
    try {
      await up.upload(rec, onUpdate: (r) {
        Services.i.publishHistory.upsert(r);
        if (mounted) setState(() => progress[prof.id] = r.bytesTotal == 0 ? 0 : r.bytesSent / r.bytesTotal);
      }, thumbnailPath: prof.id == 'youtube' ? thumb : null);
      if (mounted) toast(context, 'YouTube: ${publishStatusNames[rec.status]} ${rec.url ?? ''}');
    } catch (e) {
      rec
        ..status = PublishStatus.error
        ..error = '$e';
      Services.i.publishHistory.upsert(rec);
      if (mounted) toast(context, 'YouTube: $e', error: true);
    } finally {
      if (mounted) setState(() => progress.remove(prof.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profs = Services.i.profiles.all;
    return Scaffold(
      appBar: widget.initialFile != null ? AppBar(title: const Text('Social Publisher')) : null,
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Section(title: 'Materiał', trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          OutlinedButton.icon(onPressed: () async {
            final f = await pickFiles(extensions: [...videoExt, ...audioExt, ...imageExt], multiple: false);
            if (f.isNotEmpty) _setFile(f.first);
          }, icon: const Icon(Icons.folder_open), label: const Text('Plik')),
          const SizedBox(width: 6),
          OutlinedButton.icon(onPressed: () async {
            final list = await Services.i.store.list();
            if (!context.mounted) return;
            final id = await showDialog<String>(context: context, builder: (c) => SimpleDialog(title: const Text('Projekt'), children: [for (final p in list) SimpleDialogOption(onPressed: () => Navigator.pop(c, p.id), child: Text(p.name))]));
            if (id == null) return;
            final d = await Services.i.store.load(id);
            setState(() {
              project = d;
              title.text = d.publish.title.isEmpty ? d.name : d.publish.title;
              desc.text = d.publish.description;
              tags.text = d.publish.hashtags.join(' ');
            });
            final last = d.extra['lastRender'] as String?;
            if (last != null && File(last).existsSync()) _setFile(last);
          }, icon: const Icon(Icons.dashboard), label: const Text('Projekt')),
        ]), children: [
          if (file == null) const Text('Wybierz wyrenderowany plik lub projekt.', style: TextStyle(color: WmsColors.muted)),
          if (file != null) Text(file!.split(RegExp(r'[\\/]')).last, style: const TextStyle(fontWeight: FontWeight.bold)),
          if (info != null) MediaInfoView(info!),
        ]),
        Section(title: 'Opis publikacji', children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Tytuł')),
          const SizedBox(height: 6),
          TextField(controller: desc, maxLines: 4, minLines: 2, decoration: const InputDecoration(labelText: 'Opis')),
          const SizedBox(height: 6),
          TextField(controller: tags, decoration: const InputDecoration(labelText: 'Hashtagi'), onChanged: (_) => setState(() {})),
          Wrap(spacing: 4, children: [for (final h in hashtags) Chip(label: Text(h))]),
          Row(children: [
            const Text('Widoczność (API): '),
            DropdownButton<String>(value: visibility, items: const [DropdownMenuItem(value: 'private', child: Text('Prywatny')), DropdownMenuItem(value: 'unlisted', child: Text('Niepubliczny')), DropdownMenuItem(value: 'public', child: Text('Publiczny'))], onChanged: (v) => setState(() => visibility = v!)),
            const Spacer(),
            TextButton.icon(onPressed: () async {
              final d = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: when ?? DateTime.now());
              if (d == null || !context.mounted) return;
              final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(when ?? DateTime.now()));
              if (t != null) setState(() => when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
            }, icon: const Icon(Icons.schedule), label: Text(when == null ? 'Zaplanuj' : when.toString().substring(0, 16))),
            if (when != null) IconButton(onPressed: () => setState(() => when = null), icon: const Icon(Icons.close)),
          ]),
          if (when != null) const Text('Harmonogram działa po stronie platformy tylko dla YouTube (API publishAt – urządzenie może być wyłączone). Dla pozostałych platform aplikacja przypomni o publikacji, gdy będzie uruchomiona – nie publikuje autonomicznie.', style: TextStyle(color: WmsColors.warn, fontSize: 12)),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: '${title.text}\n\n${desc.text}')), icon: const Icon(Icons.copy), label: Text(tr('copy_desc'))),
            OutlinedButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: hashtags.join(' '))), icon: const Icon(Icons.tag), label: Text(tr('copy_tags'))),
            if (project != null) OutlinedButton.icon(onPressed: _saveDraft, icon: const Icon(Icons.save), label: const Text('Zapisz szkic')),
          ]),
        ]),
        Section(title: 'Platformy', children: [
          Wrap(spacing: 6, runSpacing: 6, children: [for (final p in profs) FilterChip(label: Text(p.name), selected: selected.contains(p.id), onSelected: (v) => setState(() => v ? selected.add(p.id) : selected.remove(p.id)))]),
          if (project?.video != null && selected.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 8), child: FilledButton.tonalIcon(onPressed: _renderVersions, icon: const Icon(Icons.auto_awesome_motion), label: Text('Jeden projekt — wiele platform: przygotuj ${selected.length} wersji'))),
        ]),
        if (file != null)
          for (final id in selected) _platformCard(Services.i.profiles[id]!),
        if (file != null)
          Section(title: 'Pakiet publikacyjny', children: [
            const Text('Teledysk.mp4, Audio.mp3, Okladka.png, Miniatura.jpg, Opis.txt, Hashtagi.txt, Napisy.srt, Metadane.json (+ ZIP)'),
            FilledButton.icon(onPressed: () async {
              final dir = exportPath('Pakiet_${title.text}', 'pkg').replaceAll('.pkg', '');
              final d = await runBusy(context, 'Tworzenie pakietu…', () => PublicationPackager(Services.i.runner).build(videoPath: file!, outDir: dir, title: title.text, description: desc.text, hashtags: hashtags, lyrics: project?.video?.lyrics, zip: true, extraMeta: {'platforms': selected.toList()}));
              if (d == null || !context.mounted) return;
              if (isDesktop) {
                NativeBridge.revealInFolder('$dir.zip');
              } else {
                await SharePlus.instance.share(ShareParams(files: [XFile('$dir.zip', mimeType: 'application/zip')]));
              }
            }, icon: const Icon(Icons.inventory_2), label: const Text('Eksportuj pakiet ZIP')),
          ]),
      ]),
    );
  }

  Widget _platformCard(PlatformProfile p) {
    final f = _fileFor(p.id);
    final issues = info == null ? <PublishIssue>[] : checkForPlatform(p, versions.containsKey(p.id) ? MediaInfo.fromProbe(f, {'format': {'duration': info!.duration}, 'streams': [{'codec_type': 'video', 'width': p.width, 'height': p.height, 'codec_name': 'h264', 'avg_frame_rate': '30/1'}, {'codec_type': 'audio', 'codec_name': 'aac'}]}) : info!, title: title.text, description: desc.text, hashtags: hashtags);
    final api = p.apiPublishing && OAuthConfig.configured;
    return Section(title: p.name, trailing: versions.containsKey(p.id) ? const Chip(label: Text('wersja gotowa')) : null, children: [
      for (final i in issues)
        Row(children: [
          Icon(i.level == IssueLevel.ok ? Icons.check_circle : i.level == IssueLevel.warning ? Icons.warning_amber : Icons.error, size: 16, color: i.level == IssueLevel.ok ? WmsColors.accent : i.level == IssueLevel.warning ? WmsColors.warn : WmsColors.error),
          const SizedBox(width: 6),
          Expanded(child: Text(i.message, style: const TextStyle(fontSize: 12))),
        ]),
      if (p.notes.isNotEmpty) Text(p.notes, style: const TextStyle(fontSize: 11, color: WmsColors.muted)),
      if (progress[p.id] != null) LinearProgressIndicator(value: progress[p.id]! > 0.002 ? progress[p.id] : null),
      Wrap(spacing: 8, children: [
        if (api) FilledButton.icon(onPressed: () => _youtube(p), icon: const Icon(Icons.cloud_upload), label: Text(when == null ? 'Opublikuj przez API' : 'Prześlij i zaplanuj')),
        FilledButton.tonalIcon(onPressed: () => _handOff(p), icon: const Icon(Icons.send), label: Text(Platform.isAndroid && p.androidPackage != null && installed.contains(p.androidPackage) ? 'Otwórz w aplikacji ${p.name}' : 'Udostępnij')),
        if (p.uploadUrl.isNotEmpty) OutlinedButton.icon(onPressed: () async {
          await Clipboard.setData(ClipboardData(text: [title.text, desc.text, hashtags.join(' ')].join('\n\n')));
          await launchUrl(Uri.parse(p.uploadUrl), mode: LaunchMode.externalApplication);
          if (isDesktop) NativeBridge.revealInFolder(f);
          await _record(p.id, PublishStatus.needsApproval);
        }, icon: const Icon(Icons.open_in_browser), label: const Text('Oficjalny panel publikacji')),
        if (versions.containsKey(p.id)) TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RenderResultScreen(path: f, project: project))), child: const Text('Podgląd wersji')),
      ]),
    ]);
  }
}
