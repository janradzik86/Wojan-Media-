import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Easing;
import 'package:record/record.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../engine/audio/audio_project.dart';
import '../../engine/dsp/analysis.dart';
import '../../engine/export/video_export.dart';
import '../../engine/ffmpeg/probe.dart';
import '../../engine/lyrics/lyrics.dart';
import '../../engine/project/asset.dart';
import '../../engine/project/format.dart';
import '../../engine/util/expr.dart';
import '../../engine/util/fontname.dart';
import '../../engine/util/json_util.dart';
import '../../engine/util/undo.dart';
import '../../engine/video/color.dart';
import '../../engine/video/model.dart';
import '../../engine/video/vfx.dart';
import '../../engine/video/visualizer.dart';
import '../shell.dart';
import '../widgets/common.dart';
import '../widgets/player.dart';
import 'render_result.dart';
import 'video_widgets.dart';

class VideoStudioScreen extends StatefulWidget {
  const VideoStudioScreen({super.key});
  @override
  State<VideoStudioScreen> createState() => _VideoStudioScreenState();
}

enum _SelKind { clip, overlay, text, vfx, vis, audio }

class _VideoStudioScreenState extends State<VideoStudioScreen> {
  ProjectDoc? doc;
  VideoProject get p => doc!.video!;
  final undo = UndoStack();
  _SelKind selKind = _SelKind.clip;
  int sel = -1;
  double zoom = 60; // px per second
  String? previewPath;
  bool safeZones = false;
  bool previewBusy = false;
  double previewProgress = 0;
  AudioAnalysis? music;
  Timer? _autosave;
  bool dirty = false;
  final recorder = AudioRecorder();
  bool recording = false;
  double recordAt = 0;

  @override
  void initState() {
    super.initState();
    _open();
    _autosave = Timer.periodic(Duration(seconds: (Services.i.settings.get<num>('autosaveSec')).toInt()), (_) {
      if (dirty && doc != null) Services.i.store.autosave(doc!);
    });
  }

  @override
  void dispose() {
    _autosave?.cancel();
    recorder.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final id = Nav.openProjectId;
    if (id == null || !Services.i.store.projectFile(id).existsSync()) return;
    final d = await Services.i.store.load(id);
    if (d.video == null) {
      if (d.type == ProjectType.audio) return;
      d.video = VideoProject();
    }
    setState(() => doc = d);
    _loadMusic();
  }

  Future<void> _loadMusic() async {
    final id = p.musicAssetId;
    if (id == null || !doc!.assets.containsKey(id)) return;
    final a = await Services.i.analyze(resolver.pathOf(id), doc!.assets[id]!.sha256);
    if (mounted) setState(() => music = a);
  }

  AssetResolver get resolver => Services.i.store.resolver(doc!);

  void _edit(void Function() f) {
    undo.push(p.toJson());
    setState(f);
    dirty = true;
  }

  Future<void> _save() async {
    await Services.i.store.save(doc!);
    dirty = false;
    Services.i.store.makeThumbnail(doc!).catchError((_) {});
    if (mounted) toast(context, 'Zapisano');
  }

  Future<void> _new() async {
    final fmt = await showDialog<(int, int)>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('Format nowego filmu'), children: [
        for (final e in formatPresets.entries) SimpleDialogOption(onPressed: () => Navigator.pop(c, e.value), child: Text('${e.key}  (${e.value.$1}×${e.value.$2})')),
      ]),
    );
    if (fmt == null) return;
    final d = await Services.i.store.create('Film ${DateTime.now().toString().substring(0, 16)}', ProjectType.video);
    d.video = VideoProject(width: fmt.$1, height: fmt.$2);
    await Services.i.store.save(d);
    Nav.openProjectId = d.id;
    setState(() => doc = d);
  }

  // ------------------------------------------------------------ adding
  Future<void> _addVisuals() async {
    final a = await importMedia(context, [...imageExt, ...videoExt]);
    if (a.isEmpty) return;
    _edit(() {
      for (final x in a) {
        doc!.assets[x.id] = x;
        final isVideo = x.kind == MediaKind.video;
        p.clips.add(VisualClip(kind: isVideo ? ClipKind.video : ClipKind.image, assetId: x.id, srcOut: isVideo ? x.duration : 0, imageDuration: 3, motion: Motion(preset: isVideo ? MotionPreset.none : MotionPreset.kenBurnsIn), fit: _autoFit(x), transition: Transition(type: 'fade', duration: 0.5)));
      }
      selKind = _SelKind.clip;
      sel = p.clips.length - 1;
    });
  }

  FitMode _autoFit(MediaAsset a) {
    if (a.width == null || a.height == null) return FitMode.cover;
    final srcPortrait = a.height! > a.width!;
    final dstPortrait = p.height > p.width;
    return srcPortrait == dstPortrait ? FitMode.cover : FitMode.blurBackground;
  }

  Future<void> _addMusic() async {
    final a = await importMedia(context, [...audioExt, ...videoExt], multiple: false);
    if (a.isEmpty) return;
    final m = a.first;
    _edit(() {
      doc!.assets[m.id] = m;
      final t = p.audio.tracks.first;
      t.clips
        ..clear()
        ..add(AudioClip(assetId: m.id, srcIn: 0, srcOut: m.duration, fadeOut: 1.5));
      p.musicAssetId = m.id;
    });
    _loadMusic();
    // One photo (or only photos) + music → film lasts as long as the song.
    if (p.clips.isNotEmpty && p.clips.every((c) => c.kind != ClipKind.video) && (p.clips.length == 1 || p.visualDuration < p.audioDuration)) {
      await _fitToAudio(ask: false);
    }
  }

  Future<void> _addOverlay() async {
    final a = await importMedia(context, [...imageExt, ...videoExt], multiple: false);
    if (a.isEmpty) return;
    _edit(() {
      doc!.assets[a.first.id] = a.first;
      p.overlays.add(OverlayItem(assetId: a.first.id, name: a.first.name, start: 0, duration: math.min(5, math.max(1, p.duration)), mute: true));
      selKind = _SelKind.overlay;
      sel = p.overlays.length - 1;
    });
  }

  Future<void> _toggleVoiceover() async {
    if (recording) {
      final path = await recorder.stop();
      setState(() => recording = false);
      if (path == null) return;
      final a = await Services.i.store.importMedia(path, displayName: 'Lektor.wav');
      _edit(() {
        doc!.assets[a.id] = a;
        final t = p.audio.tracks.length > 1 ? p.audio.tracks[1] : p.audio.addTrack('Lektor');
        t.clips.add(AudioClip(assetId: a.id, srcIn: 0, srcOut: a.duration, position: recordAt));
      });
      return;
    }
    if (!await recorder.hasPermission()) return;
    recordAt = 0;
    await recorder.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 48000), path: '${Services.i.store.cacheDir.path}/vo_${DateTime.now().millisecondsSinceEpoch}.wav');
    setState(() => recording = true);
  }

  /// "Dostosuj do długości audio" – timing only, the picture is never distorted.
  Future<void> _fitToAudio({bool ask = true}) async {
    if (p.audioDuration <= 0) {
      toast(context, 'Najpierw dodaj muzykę lub nagranie.');
      return;
    }
    if (p.clips.isEmpty) {
      toast(context, 'Dodaj zdjęcie lub klip.');
      return;
    }
    var fit = FitMode.blurBackground;
    if (ask) {
      final f = await showDialog<FitMode>(
        context: context,
        builder: (c) => SimpleDialog(title: Text('Dostosuj do długości audio (${fmtTime(p.audioDuration)})'), children: [
          const Padding(padding: EdgeInsets.fromLTRB(24, 0, 24, 8), child: Text('Zmieniany jest tylko czas wyświetlania – obraz nie jest rozciągany ani zniekształcany. Jak dopasować kadr do formatu filmu?', style: TextStyle(fontSize: 13))),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, FitMode.blurBackground), child: const ListTile(leading: Icon(Icons.blur_on), title: Text('Całe zdjęcie na rozmytym tle'), subtitle: Text('zalecane – nic nie jest ucinane'))),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, FitMode.cover), child: const ListTile(leading: Icon(Icons.crop), title: Text('Wypełnij kadr'), subtitle: Text('przycina brzegi, bez pasów'))),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, FitMode.contain), child: const ListTile(leading: Icon(Icons.fit_screen), title: Text('Zmieść z pasami'), subtitle: Text('całe zdjęcie, pasy w kolorze tła'))),
        ]),
      );
      if (f == null) return;
      fit = f;
    }
    _edit(() {
      for (final c in p.clips) {
        if (c.kind != ClipKind.video || ask) c.fit = fit;
      }
      p.fitToAudio(fit: fit);
    });
    toast(context, 'Film dopasowano do długości audio: ${fmtTime(p.duration)}');
  }

  // ------------------------------------------------------------ beat tools
  /// Snaps clip boundaries to the nearest beats (cuts on rhythm).
  void _snapCutsToBeats() {
    final beats = music?.beats ?? p.beatMarkers;
    if (beats.isEmpty) {
      toast(context, 'Najpierw dodaj muzykę – analiza rytmu działa lokalnie.');
      return;
    }
    _edit(() {
      final starts = p.clipStarts();
      for (var i = 1; i < p.clips.length; i++) {
        final target = beats.reduce((a, b) => (a - starts[i]).abs() < (b - starts[i]).abs() ? a : b);
        final delta = target - starts[i];
        final prev = p.clips[i - 1];
        if (prev.kind == ClipKind.video) {
          prev.srcOut = (prev.srcOut + delta * prev.speed).clamp(prev.srcIn + 0.2, doc!.assets[prev.assetId]!.duration);
        } else {
          prev.imageDuration = math.max(0.3, prev.imageDuration + delta);
        }
        for (var k = i; k < starts.length; k++) {
          starts[k] += delta;
        }
      }
      p.beatMarkers = [...beats];
    });
  }

  // ------------------------------------------------------------ preview
  Future<void> _renderPreview() async {
    if (doc == null || p.duration <= 0) return;
    setState(() {
      previewBusy = true;
      previewProgress = 0;
    });
    final scale = Services.i.settings.get<num>('previewScale').toDouble();
    final out = '${Services.i.store.cacheDir.path}/preview_${doc!.id}_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final mc = p.audio.tracks.expand((t) => t.clips).where((c) => c.assetId == p.musicAssetId).firstOrNull;
    try {
      await Services.i.videoRenderer().render(p, resolver, VideoExportSettings(width: (p.width * scale / 2).round() * 2, height: (p.height * scale / 2).round() * 2, fps: math.min(p.fps, 24), preset: 'ultrafast', crf: 30, encoder: EncoderPreference.auto), out,
          music: music, musicOffset: mc == null ? 0 : mc.position - mc.srcIn, onProgress: (t) => setState(() => previewProgress = (t / p.duration).clamp(0, 1)));
      setState(() => previewPath = out);
    } catch (e) {
      if (mounted) toast(context, 'Podgląd: $e', error: true);
    } finally {
      if (mounted) setState(() => previewBusy = false);
    }
  }

  Future<void> _export() async {
    final s = await showVideoExportDialog(context, p, initial: doc!.exportSettings['video'] == null ? null : VideoExportSettings.fromJson(jm(doc!.exportSettings['video'])));
    if (s == null || !mounted) return;
    doc!.exportSettings['video'] = s.toJson();
    await queueVideoRender(context, doc!, s);
  }

  // ------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    if (doc == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.movie_edit, size: 64, color: WmsColors.accent),
          const SizedBox(height: 12),
          const Text('Otwórz projekt wideo z Centrum projektów lub utwórz nowy.'),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add), label: const Text('Nowy film / pokaz slajdów')),
        ]),
      );
    }
    final wide = MediaQuery.sizeOf(context).width > 1100;
    final preview = _previewPane();
    final timeline = _timeline();
    final inspector = _inspector();
    final pro = Services.i.settings.get<bool>('proMode');
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () => _undo(),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () => _redo(),
        const SingleActivator(LogicalKeyboardKey.delete): () => _deleteSel(),
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): () => _duplicateSel(),
      },
      child: Focus(
        autofocus: true,
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(children: [
                    _topBar(pro),
                    Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(8), child: preview)),
                    SizedBox(height: 262, child: timeline),
                  ]),
                ),
                const VerticalDivider(width: 1),
                SizedBox(width: 400, child: inspector),
              ])
            : ListView(children: [_topBar(pro), preview, SizedBox(height: 230, child: timeline), SizedBox(height: 700, child: inspector)]),
      ),
    );
  }

  void _undo() {
    final s = undo.undo(p.toJson());
    if (s != null) setState(() => doc!.video = VideoProject.fromJson(s));
  }

  void _redo() {
    final s = undo.redo(p.toJson());
    if (s != null) setState(() => doc!.video = VideoProject.fromJson(s));
  }

  void _deleteSel() {
    if (sel < 0) return;
    _edit(() {
      switch (selKind) {
        case _SelKind.clip:
          p.clips.removeAt(sel);
        case _SelKind.overlay:
          p.overlays.removeAt(sel);
        case _SelKind.text:
          p.texts.removeAt(sel);
        case _SelKind.vfx:
          p.vfx.removeAt(sel);
        case _SelKind.vis:
          p.visualizers.removeAt(sel);
        case _SelKind.audio:
          break;
      }
      sel = -1;
    });
  }

  void _duplicateSel() {
    if (sel < 0) return;
    _edit(() {
      switch (selKind) {
        case _SelKind.clip:
          p.duplicateClip(sel);
        case _SelKind.overlay:
          p.overlays.add(OverlayItem.fromJson(p.overlays[sel].toJson(), newIdentity: true)..start = p.overlays[sel].end);
        case _SelKind.text:
          p.texts.add(TextItem.fromJson({...p.texts[sel].toJson(), 'id': newId()})..start = p.texts[sel].end);
        default:
          break;
      }
    });
  }

  Widget _topBar(bool pro) => Material(
        color: Theme.of(context).cardTheme.color,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 2, children: [
            SizedBox(width: 220, child: Text(doc!.name, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
            IconButton(tooltip: tr('undo'), icon: const Icon(Icons.undo), onPressed: undo.canUndo ? _undo : null),
            IconButton(tooltip: tr('redo'), icon: const Icon(Icons.redo), onPressed: undo.canRedo ? _redo : null),
            IconButton(tooltip: tr('save'), icon: const Icon(Icons.save), onPressed: _save),
            IconButton(tooltip: 'Dodaj zdjęcia / klipy', icon: const Icon(Icons.add_photo_alternate), onPressed: _addVisuals),
            IconButton(tooltip: 'Muzyka', icon: const Icon(Icons.library_music), onPressed: _addMusic),
            IconButton(tooltip: recording ? 'Zatrzymaj nagrywanie lektora' : 'Nagraj lektora', icon: Icon(recording ? Icons.stop_circle : Icons.record_voice_over), onPressed: _toggleVoiceover),
            IconButton(tooltip: 'Nakładka / logo / PIP', icon: const Icon(Icons.layers), onPressed: _addOverlay),
            IconButton(tooltip: 'Tekst', icon: const Icon(Icons.title), onPressed: () => _edit(() {
                  p.texts.add(TextItem(text: 'Twój tekst', start: 0, duration: math.max(2, math.min(4, p.duration))));
                  selKind = _SelKind.text;
                  sel = p.texts.length - 1;
                })),
            IconButton(tooltip: 'Efekt', icon: const Icon(Icons.auto_awesome), onPressed: () => _edit(() {
                  p.vfx.add(VfxItem(type: 'snow'));
                  selKind = _SelKind.vfx;
                  sel = p.vfx.length - 1;
                })),
            IconButton(tooltip: 'Wizualizator', icon: const Icon(Icons.equalizer), onPressed: () => _edit(() {
                  p.visualizers.add(VisualizerItem());
                  selKind = _SelKind.vis;
                  sel = p.visualizers.length - 1;
                })),
            IconButton(tooltip: 'Importuj napisy SRT/VTT/LRC', icon: const Icon(Icons.subtitles), onPressed: () async {
              final f = await pickFiles(extensions: subExt, multiple: false);
              if (f.isEmpty) return;
              final t = LyricsTrack.parse(await File(f.first).readAsString(), ext: extOf(f.first));
              _edit(() => p.lyrics = t
                ..mode = t.mode == LyricsMode.karaoke ? LyricsMode.karaoke : LyricsMode.subtitles
                ..style = TextStyleSpec(size: 52).toJson());
            }),
            IconButton(tooltip: 'Cięcia do rytmu muzyki', icon: const Icon(Icons.av_timer), onPressed: _snapCutsToBeats),
            TextButton.icon(onPressed: _fitToAudio, icon: const Icon(Icons.straighten), label: const Text('Dostosuj do długości audio')),
            IconButton(tooltip: 'Strefy bezpieczne', icon: Icon(safeZones ? Icons.crop_free : Icons.crop_din), onPressed: () => setState(() => safeZones = !safeZones)),
            PopupMenuButton<(int, int)>(
              tooltip: 'Format',
              icon: const Icon(Icons.aspect_ratio),
              onSelected: (v) => _edit(() {
                p.width = v.$1;
                p.height = v.$2;
              }),
              itemBuilder: (c) => [for (final e in formatPresets.entries) PopupMenuItem(value: e.value, child: Text(e.key))],
            ),
            Text('${p.width}×${p.height} • ${p.fps.round()} fps • ${fmtTime(p.duration)}', style: const TextStyle(color: WmsColors.muted, fontSize: 12)),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(onPressed: previewBusy ? null : _renderPreview, icon: const Icon(Icons.preview), label: Text(tr('preview'))),
            const SizedBox(width: 6),
            FilledButton.icon(onPressed: _export, icon: const Icon(Icons.movie_creation), label: Text(tr('render'))),
          ]),
        ),
      );

  Widget _previewPane() {
    final aspect = p.width / p.height;
    return Column(children: [
      ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
        child: AspectRatio(
          aspectRatio: aspect * 0.92,
          child: Stack(children: [
            Positioned.fill(child: previewPath == null ? Container(color: Colors.black, alignment: Alignment.center, child: const Text('Naciśnij „Podgląd”, aby wygenerować rzeczywisty podgląd\n(ten sam silnik co końcowy render, niższa rozdzielczość)', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54))) : PreviewPlayer(key: ValueKey(previewPath), path: previewPath, aspect: aspect)),
            if (safeZones) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: SafeZonePainter(p.height > p.width)))),
            if (previewBusy) Positioned.fill(child: Container(color: Colors.black54, alignment: Alignment.center, child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(value: previewProgress > 0 ? previewProgress : null), const SizedBox(height: 8), Text('Podgląd ${(previewProgress * 100).round()}%')]))),
          ]),
        ),
      ),
    ]);
  }

  Widget _timeline() {
    final starts = p.clipStarts();
    final total = math.max(p.duration, 1.0);
    Widget lane(String label, List<(double, double, String, VoidCallback, bool)> items, {Color color = WmsColors.accent2}) => SizedBox(
          height: 26,
          child: Row(children: [
            SizedBox(width: 70, child: Text(label, style: const TextStyle(fontSize: 11, color: WmsColors.muted))),
            Expanded(
              child: Stack(children: [
                for (final it in items)
                  Positioned(
                    left: it.$1 * zoom,
                    width: math.max(8, (it.$2 - it.$1) * zoom),
                    top: 2,
                    bottom: 2,
                    child: InkWell(onTap: it.$4, child: Container(decoration: BoxDecoration(color: color.withValues(alpha: it.$5 ? 0.9 : 0.45), borderRadius: BorderRadius.circular(4)), padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(it.$3, style: const TextStyle(fontSize: 10), overflow: TextOverflow.clip, maxLines: 1))),
                  ),
              ]),
            ),
          ]),
        );
    return Card(
      margin: EdgeInsets.zero,
      child: Column(children: [
        Row(children: [
          const SizedBox(width: 8),
          const Icon(Icons.zoom_in, size: 18),
          SizedBox(width: 160, child: Slider(value: zoom, min: 10, max: 300, onChanged: (v) => setState(() => zoom = v))),
          Text('Klipy: ${p.clips.length} • nakładki: ${p.overlays.length} • teksty: ${p.texts.length} • efekty: ${p.vfx.length}', style: const TextStyle(fontSize: 12, color: WmsColors.muted)),
          const Spacer(),
          if (music != null) Text('♪ ${music!.bpm.toStringAsFixed(1)} BPM ', style: const TextStyle(color: WmsColors.accent)),
        ]),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: total * zoom + 120,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // beat ruler
                SizedBox(
                  height: 14,
                  child: Row(children: [
                    const SizedBox(width: 70),
                    Expanded(child: CustomPaint(painter: _RulerPainter(total, zoom, music?.beats ?? p.beatMarkers))),
                  ]),
                ),
                SizedBox(
                  height: 80,
                  child: Row(children: [
                    const SizedBox(width: 70, child: Text('Obraz', style: TextStyle(fontSize: 11, color: WmsColors.muted))),
                    Expanded(
                      child: ReorderableListView.builder(
                        scrollDirection: Axis.horizontal,
                        buildDefaultDragHandles: false,
                        itemCount: p.clips.length,
                        onReorder: (a, b) => _edit(() => p.moveClip(a, b > a ? b - 1 : b)),
                        itemBuilder: (c, i) {
                          final cl = p.clips[i];
                          final w = math.max(40.0, (cl.duration - (i < p.clips.length - 1 ? p.effectiveTransition(i) : 0)) * zoom);
                          final selected = selKind == _SelKind.clip && sel == i;
                          return ReorderableDragStartListener(
                            key: ValueKey(cl.id),
                            index: i,
                            child: GestureDetector(
                              onTap: () => setState(() => {selKind = _SelKind.clip, sel = i}),
                              child: Container(
                                width: w,
                                margin: const EdgeInsets.only(right: 1),
                                decoration: BoxDecoration(border: Border.all(color: selected ? WmsColors.accent : Colors.transparent, width: 2)),
                                child: Stack(fit: StackFit.expand, children: [
                                  cl.kind == ClipKind.color ? Container(color: Color(int.parse('FF${cl.color.substring(1)}', radix: 16))) : ClipThumb(path: resolver.pathOf(cl.assetId!), at: cl.isVideo ? cl.srcIn + 0.3 : 0, size: 86),
                                  Positioned(left: 2, bottom: 2, child: Container(color: Colors.black54, padding: const EdgeInsets.all(2), child: Text('${cl.duration.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 10)))),
                                  if (!cl.transition.isCut && i < p.clips.length - 1) Positioned(right: 0, top: 0, child: Tooltip(message: transitionNames[cl.transition.type] ?? cl.transition.type, child: Container(color: WmsColors.accent2, padding: const EdgeInsets.all(2), child: const Icon(Icons.compare_arrows, size: 12)))),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ]),
                ),
                lane('Nakładki', [for (var i = 0; i < p.overlays.length; i++) (p.overlays[i].start, p.overlays[i].end, p.overlays[i].name, () => setState(() => {selKind = _SelKind.overlay, sel = i}), selKind == _SelKind.overlay && sel == i)]),
                lane('Teksty', [for (var i = 0; i < p.texts.length; i++) (p.texts[i].start, p.texts[i].end, p.texts[i].text, () => setState(() => {selKind = _SelKind.text, sel = i}), selKind == _SelKind.text && sel == i)], color: WmsColors.warn),
                lane('Efekty', [
                  for (var i = 0; i < p.vfx.length; i++) (p.vfx[i].start, p.vfx[i].duration > 0 ? p.vfx[i].start + p.vfx[i].duration : total, allVfxNames[p.vfx[i].type] ?? p.vfx[i].type, () => setState(() => {selKind = _SelKind.vfx, sel = i}), selKind == _SelKind.vfx && sel == i),
                  for (var i = 0; i < p.visualizers.length; i++) (p.visualizers[i].start, p.visualizers[i].duration > 0 ? p.visualizers[i].start + p.visualizers[i].duration : total, visualizerNames[p.visualizers[i].style] ?? '', () => setState(() => {selKind = _SelKind.vis, sel = i}), selKind == _SelKind.vis && sel == i),
                ], color: const Color(0xFF8A5CFF)),
                lane('Audio', [
                  for (final t in p.audio.tracks)
                    for (final c in t.clips) (c.position, c.end, '${t.name}: ${doc!.assets[c.assetId]?.name ?? ''}', () => setState(() => {selKind = _SelKind.audio, sel = 0}), selKind == _SelKind.audio),
                ], color: WmsColors.accent),
                
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------ inspector
  Widget _inspector() {
    Widget body;
    if (sel < 0) {
      body = _projectProps();
    } else {
      switch (selKind) {
        case _SelKind.clip:
          body = sel < p.clips.length ? _clipProps(p.clips[sel]) : _projectProps();
        case _SelKind.overlay:
          body = sel < p.overlays.length ? _overlayProps(p.overlays[sel]) : _projectProps();
        case _SelKind.text:
          body = sel < p.texts.length ? _textProps(p.texts[sel]) : _projectProps();
        case _SelKind.vfx:
          body = sel < p.vfx.length ? _vfxProps(p.vfx[sel]) : _projectProps();
        case _SelKind.vis:
          body = sel < p.visualizers.length ? _visProps(p.visualizers[sel]) : _projectProps();
        case _SelKind.audio:
          body = _audioProps();
      }
    }
    return ListView(padding: const EdgeInsets.all(10), children: [
      Row(children: [
        Expanded(child: Text(sel < 0 ? 'Projekt' : 'Właściwości', style: Theme.of(context).textTheme.titleMedium)),
        if (sel >= 0) IconButton(tooltip: 'Duplikuj (Ctrl+D)', icon: const Icon(Icons.copy), onPressed: _duplicateSel),
        if (sel >= 0) IconButton(tooltip: 'Usuń (Del)', icon: const Icon(Icons.delete_outline), onPressed: _deleteSel),
        if (sel >= 0) IconButton(tooltip: 'Zamknij', icon: const Icon(Icons.close), onPressed: () => setState(() => sel = -1)),
      ]),
      body,
    ]);
  }

  Widget _projectProps() => Column(children: [
        Section(title: 'Ustawienia projektu', children: [
          TextField(controller: TextEditingController(text: doc!.name), decoration: const InputDecoration(labelText: 'Nazwa'), onSubmitted: (v) => setState(() => doc!.name = v)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [for (final f in [24.0, 25.0, 30.0, 50.0, 60.0]) ChoiceChip(label: Text('${f.round()} fps'), selected: p.fps == f, onSelected: (_) => _edit(() => p.fps = f))]),
          const Text('Kolor tła'),
          ColorDots(value: p.background, onChanged: (v) => _edit(() => p.background = v)),
        ]),
        Section(title: 'Wszystkie zdjęcia', children: [
          LabeledSlider(label: 'Czas wyświetlania', value: p.clips.where((c) => c.kind != ClipKind.video).firstOrNull?.imageDuration ?? 3, min: 0.5, max: 15, unit: 's', onChanged: (v) => setState(() => p.setAllImageDurations(v)), onChangeEnd: (_) => dirty = true),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in ['fade', 'dissolve', 'slideleft', 'zoomin', 'wipeleft', 'spin', 'hblur', 'glitch', 'fadewhite', 'cube', 'circleopen', 'filmburn'])
              ActionChip(label: Text(transitionNames[t]!), onPressed: () => _edit(() => p.applyTransitionToAll(t, 0.6))),
          ]),
          TextButton.icon(onPressed: () => _edit(() {
                for (var i = 0; i < p.clips.length; i++) {
                  if (p.clips[i].kind == ClipKind.image) p.clips[i].motion = Motion(preset: [MotionPreset.kenBurnsIn, MotionPreset.kenBurnsOut, MotionPreset.panRight, MotionPreset.panLeft][i % 4]);
                }
              }), icon: const Icon(Icons.animation), label: const Text('Ken Burns dla wszystkich zdjęć')),
        ]),
        Section(title: 'Korekcja kolorów całego filmu', children: [_gradeEditor(p.globalGrade)]),
        Section(title: 'Dźwięk', children: [
          SwitchListTile(contentPadding: EdgeInsets.zero, value: p.clipAudio, title: const Text('Dźwięk z klipów wideo'), onChanged: (v) => _edit(() => p.clipAudio = v)),
          LabeledSlider(label: 'Głośność klipów', value: p.clipAudioDb, min: -30, max: 12, unit: 'dB', onChanged: (v) => setState(() => p.clipAudioDb = v)),
        ]),
        if (p.lyrics != null)
          Section(title: 'Napisy / tekst piosenki (${p.lyrics!.lines.length} wersów)', trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _edit(() => p.lyrics = null)), children: [
            DropdownButton<LyricsMode>(value: p.lyrics!.mode, items: const [
              DropdownMenuItem(value: LyricsMode.subtitles, child: Text('Napisy')),
              DropdownMenuItem(value: LyricsMode.lyric, child: Text('Lyric video (animowane)')),
              DropdownMenuItem(value: LyricsMode.karaoke, child: Text('Karaoke')),
              DropdownMenuItem(value: LyricsMode.scroll, child: Text('Przewijany tekst')),
            ], onChanged: (m) => _edit(() => p.lyrics!.mode = m!)),
            TextStyleEditor(s: TextStyleSpec.fromJson(p.lyrics!.style), onChanged: () {}),
          ]),
      ]);

  Widget _clipProps(VisualClip c) {
    final asset = c.assetId == null ? null : doc!.assets[c.assetId];
    return Column(children: [
      Section(title: asset?.name ?? 'Kolor', children: [
        if (c.kind != ClipKind.video) LabeledSlider(label: 'Czas trwania', value: c.imageDuration, min: 0.3, max: 30, unit: 's', decimals: 2, onChanged: (v) => setState(() => c.imageDuration = v), onChangeEnd: (_) => dirty = true),
        if (c.kind == ClipKind.color) ColorDots(value: c.color, onChanged: (v) => _edit(() => c.color = v)),
        if (c.kind == ClipKind.video) ...[
          LabeledSlider(label: 'Początek', value: c.srcIn, min: 0, max: math.max(0.1, c.srcOut - 0.1), unit: 's', decimals: 2, onChanged: (v) => setState(() => c.srcIn = v)),
          LabeledSlider(label: 'Koniec', value: c.srcOut, min: c.srcIn + 0.1, max: asset?.duration ?? c.srcOut, unit: 's', decimals: 2, onChanged: (v) => setState(() => c.srcOut = v)),
          LabeledSlider(label: 'Prędkość', value: c.speed, min: 0.1, max: 8, unit: '×', decimals: 2, onChanged: (v) => setState(() => c.speed = v)),
          Wrap(spacing: 6, children: [
            ActionChip(label: const Text('Slow motion 0.5×'), onPressed: () => _edit(() => c.speed = 0.5)),
            ActionChip(label: const Text('Przyspieszenie 2×'), onPressed: () => _edit(() => c.speed = 2)),
            FilterChip(label: const Text('Odwróć'), selected: c.reverse, onSelected: (v) => _edit(() => c.reverse = v)),
            FilterChip(label: const Text('Zapętl'), selected: c.loopVideo, onSelected: (v) => _edit(() => c.loopVideo = v)),
            FilterChip(label: const Text('Wycisz'), selected: c.mute, onSelected: (v) => _edit(() => c.mute = v)),
          ]),
          if (c.loopVideo) LabeledSlider(label: 'Długość z pętlą', value: c.imageDuration, min: 0.5, max: 120, unit: 's', onChanged: (v) => setState(() => c.imageDuration = v)),
          Row(children: [
            Expanded(child: LabeledSlider(label: 'Stop-klatka (s)', value: c.freezeAt < 0 ? c.srcIn : c.freezeAt, min: c.srcIn, max: c.srcOut, decimals: 2, onChanged: (v) => setState(() => c.freezeAt = v))),
          ]),
          LabeledSlider(label: 'Czas stop-klatki', value: c.freezeDuration, min: 0, max: 10, unit: 's', onChanged: (v) => setState(() {
                c.freezeDuration = v;
                if (v > 0 && c.freezeAt < 0) c.freezeAt = c.srcIn;
                if (v == 0) c.freezeAt = -1;
              })),
          LabeledSlider(label: 'Głośność klipu', value: c.volumeDb, min: -30, max: 12, unit: 'dB', onChanged: (v) => setState(() => c.volumeDb = v)),
        ],
        DropdownButtonFormField<FitMode>(value: c.fit, decoration: const InputDecoration(labelText: 'Dopasowanie'), items: const [
          DropdownMenuItem(value: FitMode.cover, child: Text('Wypełnij (kadrowanie)')),
          DropdownMenuItem(value: FitMode.contain, child: Text('Zmieść (pasy)')),
          DropdownMenuItem(value: FitMode.blurBackground, child: Text('Rozmyte tło')),
          DropdownMenuItem(value: FitMode.stretch, child: Text('Rozciągnij')),
        ], onChanged: (v) => _edit(() => c.fit = v!)),
        Row(children: [
          IconButton(tooltip: 'Obróć 90°', icon: const Icon(Icons.rotate_90_degrees_cw), onPressed: () => _edit(() => c.rotate = (c.rotate + 90) % 360)),
          IconButton(tooltip: 'Odbicie poziome', icon: const Icon(Icons.flip), onPressed: () => _edit(() => c.flipH = !c.flipH)),
          IconButton(tooltip: 'Odbicie pionowe', icon: const RotatedBox(quarterTurns: 1, child: Icon(Icons.flip)), onPressed: () => _edit(() => c.flipV = !c.flipV)),
          IconButton(tooltip: 'Podziel w połowie', icon: const Icon(Icons.call_split), onPressed: () => _edit(() => p.splitClip(sel, p.clipStarts()[sel] + c.duration / 2))),
        ]),
        ExpansionTile(title: const Text('Kadrowanie'), children: [
          LabeledSlider(label: 'X', value: c.cropX, min: 0, max: 0.9, decimals: 2, onChanged: (v) => setState(() => c.cropX = v)),
          LabeledSlider(label: 'Y', value: c.cropY, min: 0, max: 0.9, decimals: 2, onChanged: (v) => setState(() => c.cropY = v)),
          LabeledSlider(label: 'Szerokość', value: c.cropW, min: 0.1, max: 1 - c.cropX, decimals: 2, onChanged: (v) => setState(() => c.cropW = v)),
          LabeledSlider(label: 'Wysokość', value: c.cropH, min: 0.1, max: 1 - c.cropY, decimals: 2, onChanged: (v) => setState(() => c.cropH = v)),
        ]),
      ]),
      Section(title: 'Ruch kamery i animacja', children: [
        DropdownButtonFormField<MotionPreset>(value: c.motion.preset, items: [for (final m in MotionPreset.values) DropdownMenuItem(value: m, child: Text(motionNames[m]!))], onChanged: (v) => _edit(() => c.motion = Motion(preset: v!, intensity: c.motion.intensity))),
        LabeledSlider(label: 'Intensywność', value: c.motion.intensity, min: 0, max: 1, decimals: 2, onChanged: (v) => setState(() => c.motion.intensity = v)),
        ExpansionTile(title: Text('Klatki kluczowe (${c.motion.zoom.length + c.motion.panX.length + c.motion.panY.length + c.motion.rotation.length})'), children: [
          _kfEditor('Zoom', c.motion.zoom, 1, 3, c.duration),
          _kfEditor('Pozycja X', c.motion.panX, 0, 1, c.duration),
          _kfEditor('Pozycja Y', c.motion.panY, 0, 1, c.duration),
          _kfEditor('Obrót °', c.motion.rotation, -180, 180, c.duration),
        ]),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(value: c.animIn, decoration: const InputDecoration(labelText: 'Wejście'), items: [for (final e in inOutAnimNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => _edit(() => c.animIn = v!))),
          const SizedBox(width: 8),
          Expanded(child: DropdownButtonFormField<String>(value: ['none', 'fade'].contains(c.animOut) ? c.animOut : 'none', decoration: const InputDecoration(labelText: 'Wyjście'), items: const [DropdownMenuItem(value: 'none', child: Text('Brak')), DropdownMenuItem(value: 'fade', child: Text('Zanikanie'))], onChanged: (v) => _edit(() => c.animOut = v!))),
        ]),
      ]),
      if (sel < p.clips.length - 1)
        Section(title: 'Przejście do następnego', children: [
          Wrap(spacing: 4, runSpacing: 4, children: [for (final e in transitionNames.entries) ChoiceChip(label: Text(e.value, style: const TextStyle(fontSize: 11)), selected: c.transition.type == e.key, onSelected: (_) => _edit(() => c.transition.type = e.key))]),
          LabeledSlider(label: 'Czas przejścia', value: c.transition.duration, min: 0.1, max: 3, unit: 's', decimals: 2, onChanged: (v) => setState(() => c.transition.duration = v)),
          if (music != null) TextButton(onPressed: () => _edit(() => c.transition.duration = 60 / music!.bpm), child: Text('Długość = 1 bit (${(60 / music!.bpm).toStringAsFixed(2)} s)')),
          TextButton(onPressed: () => _edit(() => p.applyTransitionToAll(c.transition.type, c.transition.duration)), child: const Text('Zastosuj do wszystkich')),
        ]),
      Section(title: 'Kolor i filtry', children: [_gradeEditor(c.grade)]),
    ]);
  }

  Widget _kfEditor(String label, List<Keyframe> k, double min, double max, double dur) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Text(label), const Spacer(), TextButton(onPressed: () => _edit(() => k.add(Keyframe(k.isEmpty ? 0 : dur, k.isEmpty ? (min + max) / 2 : k.last.v, Easing.easeInOut))), child: const Text('+ klatka'))]),
        for (var i = 0; i < k.length; i++)
          Row(children: [
            SizedBox(width: 70, child: Text('t ${k[i].t.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 11))),
            Expanded(child: Slider(value: k[i].t.clamp(0, dur), max: dur, onChanged: (v) => setState(() => k[i] = Keyframe(v, k[i].v, k[i].ease)))),
            Expanded(child: Slider(value: k[i].v.clamp(min, max), min: min, max: max, onChanged: (v) => setState(() => k[i] = Keyframe(k[i].t, v, k[i].ease)))),
            DropdownButton<Easing>(value: k[i].ease, items: const [DropdownMenuItem(value: Easing.linear, child: Text('lin.')), DropdownMenuItem(value: Easing.easeIn, child: Text('in')), DropdownMenuItem(value: Easing.easeOut, child: Text('out')), DropdownMenuItem(value: Easing.easeInOut, child: Text('in-out')), DropdownMenuItem(value: Easing.hold, child: Text('stop'))], onChanged: (e) => setState(() => k[i] = Keyframe(k[i].t, k[i].v, e!))),
            IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() => k.removeAt(i))),
          ]),
      ]);

  Widget _gradeEditor(ColorGrade g) => Column(children: [
        Wrap(spacing: 4, runSpacing: 4, children: [
          ChoiceChip(label: const Text('Brak'), selected: g.filter.isEmpty, onSelected: (_) => _edit(() => g.filter = '')),
          for (final e in lookNames.entries) ChoiceChip(label: Text(e.value, style: const TextStyle(fontSize: 11)), selected: g.filter == e.key, onSelected: (_) => _edit(() => g.filter = e.key)),
        ]),
        if (g.filter.isNotEmpty) LabeledSlider(label: 'Siła filtra', value: g.filterStrength, min: 0, max: 1, decimals: 2, onChanged: (v) => setState(() => g.filterStrength = v)),
        LabeledSlider(label: 'Jasność', value: g.brightness, min: -0.5, max: 0.5, decimals: 2, onChanged: (v) => setState(() => g.brightness = v)),
        LabeledSlider(label: 'Kontrast', value: g.contrast, min: 0.3, max: 2, decimals: 2, onChanged: (v) => setState(() => g.contrast = v)),
        LabeledSlider(label: 'Nasycenie', value: g.saturation, min: 0, max: 2.5, decimals: 2, onChanged: (v) => setState(() => g.saturation = v)),
        LabeledSlider(label: 'Ekspozycja', value: g.exposure, min: -2, max: 2, unit: 'EV', decimals: 2, onChanged: (v) => setState(() => g.exposure = v)),
        LabeledSlider(label: 'Gamma', value: g.gamma, min: 0.3, max: 2.5, decimals: 2, onChanged: (v) => setState(() => g.gamma = v)),
        LabeledSlider(label: 'Temperatura', value: g.temperature, min: 2000, max: 12000, unit: 'K', decimals: 0, onChanged: (v) => setState(() => g.temperature = v)),
        LabeledSlider(label: 'Odcień (zieleń/magenta)', value: g.tint, min: -1, max: 1, decimals: 2, onChanged: (v) => setState(() => g.tint = v)),
        LabeledSlider(label: 'Cienie', value: g.shadows, min: -1, max: 1, decimals: 2, onChanged: (v) => setState(() => g.shadows = v)),
        LabeledSlider(label: 'Światła', value: g.highlights, min: -1, max: 1, decimals: 2, onChanged: (v) => setState(() => g.highlights = v)),
        LabeledSlider(label: 'Ostrość', value: g.sharpness, min: -2, max: 3, decimals: 2, onChanged: (v) => setState(() => g.sharpness = v)),
        LabeledSlider(label: 'Winieta', value: g.vignette, min: 0, max: 1, decimals: 2, onChanged: (v) => setState(() => g.vignette = v)),
        LabeledSlider(label: 'Ziarno', value: g.grain, min: 0, max: 1, decimals: 2, onChanged: (v) => setState(() => g.grain = v)),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(onPressed: () async {
            final a = await importMedia(context, ['cube', '3dl'], multiple: false);
            if (a.isNotEmpty) _edit(() => {doc!.assets[a.first.id] = a.first, g.lutAssetId = a.first.id});
          }, icon: const Icon(Icons.palette), label: Text(g.lutAssetId == null ? 'Wczytaj LUT (.cube)' : 'LUT: ${doc!.assets[g.lutAssetId]?.name}')),
          if (g.lutAssetId != null) TextButton(onPressed: () => _edit(() => g.lutAssetId = null), child: const Text('Usuń LUT')),
          TextButton(onPressed: () async {
            final n = await promptText(context, 'Nazwa presetu kolorów');
            if (n != null && n.isNotEmpty) Services.i.kv.put('colorPresets', n, g.toJson()..remove('lut'));
          }, child: const Text('Zapisz preset')),
          PopupMenuButton<String>(
            child: const Padding(padding: EdgeInsets.all(8), child: Text('Moje presety ▾')),
            onSelected: (k) => _edit(() {
              final n = ColorGrade.fromJson(Services.i.kv.get('colorPresets', k)!);
              g
                ..brightness = n.brightness
                ..contrast = n.contrast
                ..saturation = n.saturation
                ..gamma = n.gamma
                ..exposure = n.exposure
                ..temperature = n.temperature
                ..tint = n.tint
                ..sharpness = n.sharpness
                ..shadows = n.shadows
                ..highlights = n.highlights
                ..vignette = n.vignette
                ..grain = n.grain
                ..filter = n.filter
                ..filterStrength = n.filterStrength;
            }),
            itemBuilder: (c) => [for (final k in Services.i.kv.keys('colorPresets')) PopupMenuItem(value: k, child: Text(k))],
          ),
          TextButton(onPressed: () => _edit(() {
                final n = ColorGrade();
                g
                  ..brightness = n.brightness
                  ..contrast = n.contrast
                  ..saturation = n.saturation
                  ..gamma = n.gamma
                  ..exposure = n.exposure
                  ..temperature = n.temperature
                  ..tint = 0
                  ..sharpness = 0
                  ..shadows = 0
                  ..highlights = 0
                  ..vignette = 0
                  ..grain = 0
                  ..filter = '';
              }), child: const Text('Resetuj')),
        ]),
      ]);

  Widget _timeFields(double start, double dur, void Function(double s, double d) on) => Column(children: [
        LabeledSlider(label: 'Start', value: start, min: 0, max: math.max(p.duration, start + 1), unit: 's', decimals: 2, onChanged: (v) => setState(() => on(_snap(v), dur))),
        LabeledSlider(label: 'Czas trwania', value: dur, min: 0.1, max: math.max(p.duration, dur + 1), unit: 's', decimals: 2, onChanged: (v) => setState(() => on(start, v))),
      ]);

  /// Snapping to beat markers (within 80 ms).
  double _snap(double t) {
    final b = music?.beats ?? p.beatMarkers;
    for (final x in b) {
      if ((x - t).abs() < 0.08) return x;
    }
    return t;
  }

  Widget _overlayProps(OverlayItem o) => Section(title: 'Nakładka: ${o.name}', children: [
        _timeFields(o.start, o.duration, (s, d) => {o.start = s, o.duration = d}),
        LabeledSlider(label: 'Pozycja X', value: o.x, min: 0, max: 1, decimals: 2, onChanged: (v) => setState(() => o.x = v)),
        LabeledSlider(label: 'Pozycja Y', value: o.y, min: 0, max: 1, decimals: 2, onChanged: (v) => setState(() => o.y = v)),
        LabeledSlider(label: 'Skala', value: o.scale, min: 0.05, max: 1.5, decimals: 2, onChanged: (v) => setState(() => o.scale = v)),
        LabeledSlider(label: 'Obrót', value: o.rotation, min: -180, max: 180, unit: '°', decimals: 0, onChanged: (v) => setState(() => o.rotation = v)),
        LabeledSlider(label: 'Przezroczystość', value: o.opacity, min: 0, max: 1, decimals: 2, onChanged: (v) => setState(() => o.opacity = v)),
        ExpansionTile(title: const Text('Ruch (klatki kluczowe)'), children: [
          _kfEditor('X', o.xKf, 0, 1, o.duration),
          _kfEditor('Y', o.yKf, 0, 1, o.duration),
          _kfEditor('Skala', o.scaleKf, 0.05, 1.5, o.duration),
          _kfEditor('Obrót', o.rotKf, -180, 180, o.duration),
        ]),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: o.chromaKey, title: const Text('Chroma key (zielone tło)'), onChanged: (v) => _edit(() => o.chromaKey = v)),
        if (o.chromaKey) ...[
          ColorDots(value: o.keyColor, onChanged: (v) => _edit(() => o.keyColor = v)),
          LabeledSlider(label: 'Podobieństwo', value: o.keySimilarity, min: 0.01, max: 0.6, decimals: 2, onChanged: (v) => setState(() => o.keySimilarity = v)),
          LabeledSlider(label: 'Zmiękczenie', value: o.keyBlend, min: 0, max: 0.5, decimals: 2, onChanged: (v) => setState(() => o.keyBlend = v)),
        ],
        DropdownButtonFormField<MaskShape>(value: o.mask, decoration: const InputDecoration(labelText: 'Maska'), items: const [
          DropdownMenuItem(value: MaskShape.none, child: Text('Brak')),
          DropdownMenuItem(value: MaskShape.circle, child: Text('Koło')),
          DropdownMenuItem(value: MaskShape.ellipse, child: Text('Elipsa')),
          DropdownMenuItem(value: MaskShape.rounded, child: Text('Zaokrąglony prostokąt')),
          DropdownMenuItem(value: MaskShape.heart, child: Text('Serce')),
          DropdownMenuItem(value: MaskShape.star, child: Text('Gwiazda')),
        ], onChanged: (v) => _edit(() => o.mask = v!)),
        LabeledSlider(label: 'Ramka', value: o.borderWidth, min: 0, max: 30, unit: 'px', decimals: 0, onChanged: (v) => setState(() => o.borderWidth = v)),
        if (o.borderWidth > 0) ColorDots(value: o.borderColor, onChanged: (v) => _edit(() => o.borderColor = v)),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(value: o.animIn, decoration: const InputDecoration(labelText: 'Wejście'), items: [for (final e in inOutAnimNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => _edit(() => o.animIn = v!))),
          const SizedBox(width: 6),
          Expanded(child: DropdownButtonFormField<String>(value: ['none', 'fade', 'zoom'].contains(o.animOut) ? o.animOut : 'none', decoration: const InputDecoration(labelText: 'Wyjście'), items: const [DropdownMenuItem(value: 'none', child: Text('Brak')), DropdownMenuItem(value: 'fade', child: Text('Zanikanie')), DropdownMenuItem(value: 'zoom', child: Text('Pomniejszenie'))], onChanged: (v) => _edit(() => o.animOut = v!))),
        ]),
        Row(children: [
          FilterChip(label: const Text('Pętla'), selected: o.loop, onSelected: (v) => _edit(() => o.loop = v)),
          const SizedBox(width: 6),
          FilterChip(label: const Text('Dźwięk'), selected: !o.mute, onSelected: (v) => _edit(() => o.mute = !v)),
          const SizedBox(width: 6),
          FilterChip(label: const Text('Ukryj'), selected: o.hidden, onSelected: (v) => _edit(() => o.hidden = v)),
          const SizedBox(width: 6),
          FilterChip(label: const Text('Zablokuj'), selected: o.locked, onSelected: (v) => _edit(() => o.locked = v)),
        ]),
        Row(children: [
          const Text('Warstwa '),
          IconButton(icon: const Icon(Icons.arrow_downward), onPressed: () => _edit(() => o.layer--)),
          Text('${o.layer}'),
          IconButton(icon: const Icon(Icons.arrow_upward), onPressed: () => _edit(() => o.layer++)),
          const Spacer(),
          SizedBox(width: 110, child: TextField(decoration: const InputDecoration(hintText: 'Grupa'), controller: TextEditingController(text: o.group), onSubmitted: (v) => _edit(() => o.group = v))),
          if (o.group.isNotEmpty)
            IconButton(tooltip: 'Przesuń całą grupę o 1 s', icon: const Icon(Icons.fast_forward), onPressed: () => _edit(() {
                  for (final x in p.overlays.where((x) => x.group == o.group)) {
                    x.start += 1;
                  }
                })),
        ]),
      ]);

  Widget _textProps(TextItem t) => Column(children: [
        Section(title: 'Tekst', children: [
          TextField(controller: TextEditingController(text: t.text), maxLines: 4, minLines: 1, onChanged: (v) => t.text = v, onEditingComplete: () => setState(() {})),
          _timeFields(t.start, t.duration, (s, d) => {t.start = s, t.duration = d}),
          DropdownButtonFormField<String>(value: t.anim, decoration: const InputDecoration(labelText: 'Animacja'), items: [for (final e in textAnimNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => _edit(() => t.anim = v!)),
          LabeledSlider(label: 'Czas animacji', value: t.animDur, min: 0.1, max: 3, unit: 's', onChanged: (v) => setState(() => t.animDur = v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: t.x >= 0, title: const Text('Własna pozycja'), onChanged: (v) => _edit(() => {t.x = v ? 0.5 : -1, t.y = v ? 0.5 : -1})),
          if (t.x >= 0) LabeledSlider(label: 'X', value: t.x, min: 0, max: 1, decimals: 2, onChanged: (v) => setState(() => t.x = v)),
          if (t.x >= 0) LabeledSlider(label: 'Y', value: t.y, min: 0, max: 1, decimals: 2, onChanged: (v) => setState(() => t.y = v)),
        ]),
        Section(title: 'Styl', trailing: TextButton(onPressed: _importFont, child: const Text('+ własna czcionka')), children: [TextStyleEditor(s: t.style, onChanged: () => setState(() => dirty = true))]),
      ]);

  Future<void> _importFont() async {
    final f = await pickFiles(extensions: ['ttf', 'otf'], multiple: false);
    if (f.isEmpty) return;
    final bytes = await File(f.first).readAsBytes();
    final fam = fontFamilyName(bytes);
    if (fam == null) {
      if (mounted) toast(context, 'Nie rozpoznano czcionki', error: true);
      return;
    }
    await File('${Services.i.fontsDir}/${f.first.split(RegExp(r'[\\/]')).last}').writeAsBytes(bytes);
    Services.i.kv.put('fonts', fam, {'family': fam, 'file': f.first.split(RegExp(r'[\\/]')).last});
    if (mounted) {
      toast(context, 'Dodano czcionkę „$fam”');
      setState(() {});
    }
  }

  Widget _vfxProps(VfxItem v) => Section(title: 'Efekt wizualny', children: [
        Wrap(spacing: 4, runSpacing: 4, children: [for (final e in allVfxNames.entries) ChoiceChip(label: Text(e.value, style: const TextStyle(fontSize: 11)), selected: v.type == e.key, onSelected: (_) => _edit(() => v.type = e.key))]),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: v.duration <= 0, title: const Text('Przez cały film'), onChanged: (b) => _edit(() => v.duration = b ? 0 : 3)),
        if (v.duration > 0) _timeFields(v.start, v.duration, (s, d) => {v.start = s, v.duration = d}),
        LabeledSlider(label: 'Intensywność', value: v.intensity, min: 0, max: 1, decimals: 2, onChanged: (x) => setState(() => v.intensity = x)),
        const Text('Kolor (cząsteczki/ramki)'),
        ColorDots(value: v.color, onChanged: (c) => _edit(() => v.color = c)),
        if (reactiveCapable.contains(v.type)) SwitchListTile(contentPadding: EdgeInsets.zero, value: v.reactive, title: const Text('Reaguje na muzykę (rzeczywista analiza sygnału)'), subtitle: music == null ? const Text('Dodaj muzykę, aby włączyć') : null, onChanged: (b) => _edit(() => v.reactive = b)),
      ]);

  Widget _visProps(VisualizerItem v) => Section(title: 'Wizualizator', children: [
        Wrap(spacing: 4, runSpacing: 4, children: [for (final e in visualizerNames.entries) ChoiceChip(label: Text(e.value, style: const TextStyle(fontSize: 11)), selected: v.style == e.key, onSelected: (_) => _edit(() => v.style = e.key))]),
        LabeledSlider(label: 'X', value: v.x, min: 0, max: 1, decimals: 2, onChanged: (x) => setState(() => v.x = x)),
        LabeledSlider(label: 'Y', value: v.y, min: 0, max: 1, decimals: 2, onChanged: (x) => setState(() => v.y = x)),
        LabeledSlider(label: 'Szerokość', value: v.width, min: 0.05, max: 1, decimals: 2, onChanged: (x) => setState(() => v.width = x)),
        LabeledSlider(label: 'Wysokość', value: v.height, min: 0.05, max: 1, decimals: 2, onChanged: (x) => setState(() => v.height = x)),
        LabeledSlider(label: 'Intensywność', value: v.intensity, min: 0.2, max: 4, decimals: 2, onChanged: (x) => setState(() => v.intensity = x)),
        LabeledSlider(label: 'Krycie', value: v.opacity, min: 0.1, max: 1, decimals: 2, onChanged: (x) => setState(() => v.opacity = x)),
        const Text('Kolor'),
        ColorDots(value: v.color, onChanged: (c) => _edit(() => v.color = c)),
        const Text('Kolor 2'),
        ColorDots(value: v.color2, onChanged: (c) => _edit(() => v.color2 = c)),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: v.bassPulse, title: const Text('Pulsowanie na basie'), onChanged: (b) => _edit(() => v.bassPulse = b)),
        OutlinedButton.icon(onPressed: () async {
          final a = await importMedia(context, imageExt, multiple: false);
          if (a.isNotEmpty) _edit(() => {doc!.assets[a.first.id] = a.first, v.logoAssetId = a.first.id});
        }, icon: const Icon(Icons.image), label: Text(v.logoAssetId == null ? 'Logo w centrum' : 'Logo: ${doc!.assets[v.logoAssetId]?.name}')),
        if (v.logoAssetId != null) LabeledSlider(label: 'Rozmiar logo', value: v.logoSize, min: 0.1, max: 0.9, decimals: 2, onChanged: (x) => setState(() => v.logoSize = x)),
      ]);

  Widget _audioProps() => Column(children: [
        for (final t in p.audio.tracks)
          Section(title: 'Ścieżka: ${t.name}', children: [
            LabeledSlider(label: 'Głośność', value: t.gainDb, min: -30, max: 12, unit: 'dB', onChanged: (v) => setState(() => t.gainDb = v)),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: t.muted, title: const Text('Wycisz'), onChanged: (v) => _edit(() => t.muted = v)),
            for (final c in t.clips)
              Column(children: [
                Text(doc!.assets[c.assetId]?.name ?? ''),
                LabeledSlider(label: 'Start na osi', value: c.position, min: 0, max: math.max(p.duration, c.position + 1), unit: 's', onChanged: (v) => setState(() => c.position = v)),
                LabeledSlider(label: 'Początek w utworze', value: c.srcIn, min: 0, max: c.srcOut - 0.1, unit: 's', onChanged: (v) => setState(() => c.srcIn = v)),
                LabeledSlider(label: 'Fade in', value: c.fadeIn, min: 0, max: 10, unit: 's', onChanged: (v) => setState(() => c.fadeIn = v)),
                LabeledSlider(label: 'Fade out', value: c.fadeOut, min: 0, max: 10, unit: 's', onChanged: (v) => setState(() => c.fadeOut = v)),
                LabeledSlider(label: 'Głośność', value: c.gainDb, min: -30, max: 12, unit: 'dB', onChanged: (v) => setState(() => c.gainDb = v)),
                TextButton.icon(onPressed: () => _edit(() => t.clips.remove(c)), icon: const Icon(Icons.delete_outline), label: const Text('Usuń')),
              ]),
          ]),
        TextButton.icon(onPressed: _fitToAudio, icon: const Icon(Icons.straighten), label: const Text('Dostosuj do długości audio (bez zniekształceń)')),
        if (p.fixedDuration != null) TextButton(onPressed: () => _edit(() => p.fixedDuration = null), child: const Text('Długość automatyczna')),
      ]);
}

class _RulerPainter extends CustomPainter {
  final double total, zoom;
  final List<double> beats;
  _RulerPainter(this.total, this.zoom, this.beats);
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = WmsColors.muted;
    final step = zoom > 80 ? 1 : zoom > 30 ? 5 : 10;
    for (var t = 0; t <= total; t += step) {
      c.drawLine(Offset(t * zoom, 6), Offset(t * zoom, s.height), p);
      final tp = TextPainter(text: TextSpan(text: '${t}s', style: const TextStyle(fontSize: 8, color: WmsColors.muted)), textDirection: TextDirection.ltr)..layout();
      tp.paint(c, Offset(t * zoom + 2, 0));
    }
    final bp = Paint()..color = WmsColors.accent2;
    for (final b in beats) {
      c.drawCircle(Offset(b * zoom, s.height - 2), 1.5, bp);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => true;
}
