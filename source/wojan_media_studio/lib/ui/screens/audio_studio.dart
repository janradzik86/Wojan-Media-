import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart' hide AudioTrack;
import 'package:record/record.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../engine/audio/audio_compiler.dart';
import '../../engine/audio/audio_project.dart';
import '../../engine/audio/effects.dart';
import '../../engine/dsp/analysis.dart';
import '../../engine/dsp/pcm.dart';
import '../../engine/export/audio_formats.dart';
import '../../engine/ffmpeg/runner.dart';
import '../../engine/project/asset.dart';
import '../../engine/project/format.dart';
import '../../engine/render/queue.dart';
import '../../engine/util/expr.dart';
import '../../engine/util/hash.dart';
import '../../engine/util/json_util.dart';
import '../../engine/util/undo.dart';
import '../shell.dart';
import '../widgets/common.dart';
import '../widgets/player.dart';
import '../widgets/waveform.dart';
import 'audio_tools.dart';
import 'render_result.dart';

class AudioStudioScreen extends StatefulWidget {
  const AudioStudioScreen({super.key});
  @override
  State<AudioStudioScreen> createState() => _AudioStudioScreenState();
}

class _AudioStudioScreenState extends State<AudioStudioScreen> with SingleTickerProviderStateMixin {
  late final TabController tabs = TabController(length: 3, vsync: this);
  ProjectDoc? doc;
  AudioProject get p => doc!.audio!;
  final undo = UndoStack();
  String? trackId;
  double selS = 0, selE = 0, playhead = 0, zoom = 1, scroll = 0;
  final peaks = <String, Float32List>{};
  final _peakKeys = <String, String>{};
  List<AudioClip> clipboard = [];
  String? previewPath;
  Player? player;
  StreamSubscription<Duration>? _posSub;
  double previewOffset = 0;
  Timer? _autosave;
  bool dirty = false;
  final recorder = AudioRecorder();
  bool recording = false;
  String? recordPath;
  AudioAnalysis? beatsAnalysis;

  @override
  void initState() {
    super.initState();
    _openFromNav();
    _autosave = Timer.periodic(Duration(seconds: (Services.i.settings.get<num>('autosaveSec')).toInt()), (_) {
      if (dirty && doc != null) Services.i.store.autosave(doc!);
    });
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _posSub?.cancel();
    recorder.dispose();
    super.dispose();
  }

  Future<void> _openFromNav() async {
    final id = Nav.openProjectId;
    if (id != null && Services.i.store.projectFile(id).existsSync()) {
      final d = await Services.i.store.load(id);
      if (d.type == ProjectType.audio || d.audio != null) {
        d.audio ??= AudioProject();
        setState(() {
          doc = d;
          trackId = p.tracks.first.id;
        });
        _refreshPeaks();
      }
    }
  }

  Future<void> _newProject() async {
    final d = await Services.i.store.create('Projekt audio ${DateTime.now().toString().substring(0, 16)}', ProjectType.audio);
    d.audio = AudioProject();
    await Services.i.store.save(d);
    Nav.openProjectId = d.id;
    setState(() {
      doc = d;
      trackId = p.tracks.first.id;
    });
  }

  void _edit(String label, void Function() f) {
    undo.push(p.toJson(), label);
    setState(f);
    dirty = true;
    _refreshPeaks();
  }

  Future<void> _save() async {
    if (doc == null) return;
    await Services.i.store.save(doc!);
    dirty = false;
    await Services.i.store.makeThumbnail(doc!).catchError((_) {});
    if (mounted) toast(context, 'Zapisano projekt');
  }

  AssetResolver get resolver => Services.i.store.resolver(doc!);
  AudioRenderer get renderer => AudioRenderer(Services.i.runner, Directory('${Services.i.store.cacheDir.path}/audio'));

  /// Real waveform per track: track is rendered (cached by content hash)
  /// and decoded – what you see is what you get.
  Future<void> _refreshPeaks() async {
    if (doc == null) return;
    for (final t in p.tracks) {
      if (t.clips.isEmpty) {
        peaks.remove(t.id);
        continue;
      }
      final single = AudioProject(sampleRate: 22050, channels: 1, tracks: [AudioTrack.fromJson(t.toJson())..muted = false..solo = false]);
      final key = sha256String(jsonEncode(single.toJson()));
      if (_peakKeys[t.id] == key) continue;
      _peakKeys[t.id] = key;
      final f = File('${Services.i.store.cacheDir.path}/audio/peaks_$key.wav');
      try {
        if (!f.existsSync()) await renderer.render(single, resolver, f.path, AudioExportSettings(format: AudioFormat.wav, sampleRate: 22050, channels: 1));
        final pcm = await PcmDecoder(Services.i.runner, Directory('${Services.i.store.cacheDir.path}/pcm')).decode(f.path, sampleRate: 8000);
        peaks[t.id] = AudioAnalyzer.waveformPeaks(pcm.samples, 4000);
        if (mounted) setState(() {});
      } catch (e) {
        if (mounted) toast(context, 'Podgląd fali: $e', error: true);
      }
    }
  }

  Future<void> _addFiles({String? toTrack}) async {
    final a = await importMedia(context, [...audioExt, ...videoExt]);
    if (a.isEmpty) return;
    _edit('import', () {
      for (final asset in a) {
        doc!.assets[asset.id] = asset;
        final tid = toTrack ?? (p.tracks.firstWhere((t) => t.id == trackId, orElse: () => p.tracks.first)).id;
        p.appendAsset(tid, asset.id, asset.duration);
      }
    });
  }

  Future<void> _preview({bool selection = false}) async {
    if (doc == null || p.duration <= 0) return;
    final out = '${Services.i.store.cacheDir.path}/audio/preview_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final s = selection && selE > selS;
    await runBusy(context, 'Przygotowanie podglądu…', () => renderer.render(p, resolver, out, AudioExportSettings(format: AudioFormat.m4a, bitrateKbps: 160), rangeStart: s ? selS : null, rangeEnd: s ? selE : null));
    setState(() {
      previewPath = out;
      previewOffset = s ? selS : 0;
    });
  }

  void _attachPlayer(Player pl) {
    player = pl;
    _posSub?.cancel();
    _posSub = pl.stream.position.listen((d) {
      if (mounted) setState(() => playhead = previewOffset + d.inMilliseconds / 1000);
    });
  }

  Future<void> _export() async {
    if (doc == null) return;
    final s = AudioExportSettings.fromJson(doc!.exportSettings['audio'] as Map<String, dynamic>? ?? {});
    final meta = <String, String>{'title': doc!.name, 'artist': '', 'album': ''};
    var onlySel = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        return AlertDialog(
          title: const Text('Eksport audio'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<AudioFormat>(value: s.format, decoration: const InputDecoration(labelText: 'Format'), items: [for (final f in AudioFormat.values) DropdownMenuItem(value: f, child: Text(f.name.toUpperCase()))], onChanged: (v) => set(() => s.format = v!)),
                if (!s.lossless) DropdownButtonFormField<int>(value: s.bitrateKbps, decoration: const InputDecoration(labelText: 'Bitrate'), items: [for (final b in [64, 96, 128, 160, 192, 256, 320]) DropdownMenuItem(value: b, child: Text('$b kb/s'))], onChanged: (v) => set(() => s.bitrateKbps = v!)),
                DropdownButtonFormField<int>(value: s.sampleRate, decoration: const InputDecoration(labelText: 'Częstotliwość próbkowania'), items: [for (final r in [22050, 32000, 44100, 48000, 96000]) DropdownMenuItem(value: r, child: Text('$r Hz'))], onChanged: (v) => set(() => s.sampleRate = v!)),
                DropdownButtonFormField<int>(value: s.channels, decoration: const InputDecoration(labelText: 'Kanały'), items: const [DropdownMenuItem(value: 1, child: Text('Mono')), DropdownMenuItem(value: 2, child: Text('Stereo'))], onChanged: (v) => set(() => s.channels = v!)),
                if (s.format == AudioFormat.wav) DropdownButtonFormField<int>(value: s.wavBits, decoration: const InputDecoration(labelText: 'Głębia bitowa'), items: const [DropdownMenuItem(value: 16, child: Text('16 bit')), DropdownMenuItem(value: 24, child: Text('24 bit')), DropdownMenuItem(value: 32, child: Text('32 bit float'))], onChanged: (v) => set(() => s.wavBits = v!)),
                TextField(decoration: const InputDecoration(labelText: 'Tytuł'), controller: TextEditingController(text: meta['title']), onChanged: (v) => meta['title'] = v),
                TextField(decoration: const InputDecoration(labelText: 'Wykonawca'), onChanged: (v) => meta['artist'] = v),
                TextField(decoration: const InputDecoration(labelText: 'Album'), onChanged: (v) => meta['album'] = v),
                if (selE > selS) CheckboxListTile(value: onlySel, title: Text('Tylko zaznaczenie (${fmtTime(selS)} – ${fmtTime(selE)})'), onChanged: (v) => set(() => onlySel = v!)),
                const SizedBox(height: 8),
                Text('Szacowany rozmiar: ${fmtBytes(s.estimateSize(onlySel ? selE - selS : p.duration))}'),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'))), FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('export')))],
        );
      }),
    );
    if (ok != true || !mounted) return;
    doc!.exportSettings['audio'] = s.toJson();
    final out = exportPath(meta['title']!.isEmpty ? doc!.name : meta['title']!, s.extension);
    final job = RenderJob(
      title: '${doc!.name} (${s.format.name})',
      outputPath: out,
      expectedDuration: onlySel ? selE - selS : p.duration,
      estimatedBytes: s.estimateSize(p.duration),
      run: (prog, c) => renderer.render(p, resolver, out, s, rangeStart: onlySel ? selS : null, rangeEnd: onlySel ? selE : null, onProgress: prog, cancel: c, metadata: Map.fromEntries(meta.entries.where((e) => e.value.isNotEmpty))),
    );
    Services.i.queue.add(job);
    final done = await Services.i.queue.changes.firstWhere((j) => j == job && j.state != JobState.running && j.state != JobState.queued);
    if (!mounted) return;
    if (done.state == JobState.done) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => RenderResultScreen(path: out, project: doc)));
    } else {
      toast(context, 'Eksport nie powiódł się: ${done.error}', error: true);
    }
  }

  Future<void> _toggleRecord() async {
    if (recording) {
      final path = await recorder.stop();
      setState(() => recording = false);
      if (path == null) return;
      final a = await Services.i.store.importMedia(path, displayName: 'Nagranie ${DateTime.now().toString().substring(0, 19)}.wav');
      _edit('record', () {
        doc!.assets[a.id] = a;
        final t = p.addTrack('Nagranie');
        t.clips.add(AudioClip(assetId: a.id, srcIn: 0, srcOut: a.duration, position: playhead));
        trackId = t.id;
      });
      return;
    }
    if (!await recorder.hasPermission()) {
      if (mounted) toast(context, 'Brak uprawnienia do mikrofonu', error: true);
      return;
    }
    recordPath = '${Services.i.store.cacheDir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';
    await recorder.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 48000, numChannels: 2), path: recordPath!);
    if (player != null && previewPath != null) await player!.play(); // overdub over the mix
    setState(() => recording = true);
  }

  Future<void> _detectBeats() async {
    final music = doc!.assets.values.where((a) => p.tracks.expand((t) => t.clips).any((c) => c.assetId == a.id)).firstOrNull;
    if (music == null) return;
    final a = await runBusy(context, 'Analiza rytmu…', () => Services.i.analyze(resolver.pathOf(music.id), music.sha256));
    if (a != null) setState(() => beatsAnalysis = a);
  }

  // --------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Material(
        color: Theme.of(context).cardTheme.color,
        child: TabBar(controller: tabs, tabs: const [Tab(text: 'Edytor wielościeżkowy'), Tab(text: 'Szybkie narzędzia'), Tab(text: 'Analiza')]),
      ),
      Expanded(
        child: TabBarView(controller: tabs, physics: const NeverScrollableScrollPhysics(), children: [
          doc == null ? _empty() : _editor(),
          const AudioToolsPanel(),
          AudioAnalysisPanel(projectRender: doc == null ? null : () async {
            final out = '${Services.i.store.cacheDir.path}/audio/analysis_mix.wav';
            await renderer.render(p, resolver, out, AudioExportSettings(format: AudioFormat.wav));
            return out;
          }),
        ]),
      ),
    ]);
  }

  Widget _empty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.graphic_eq, size: 64, color: WmsColors.accent),
          const SizedBox(height: 12),
          const Text('Otwórz projekt z Centrum projektów lub utwórz nowy.'),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _newProject, icon: const Icon(Icons.add), label: const Text('Nowy projekt audio')),
          TextButton(onPressed: () => tabs.animateTo(1), child: const Text('…lub użyj szybkich narzędzi (przytnij, konwertuj, połącz)')),
        ]),
      );

  AudioTrack? get selTrack => p.tracks.where((t) => t.id == trackId).firstOrNull;

  Widget _toolbar() {
    final hasSel = selE > selS + 0.01;
    final tid = trackId ?? p.tracks.first.id;
    Widget b(IconData i, String tip, VoidCallback? f) => IconButton(icon: Icon(i), tooltip: tip, onPressed: f);
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
      b(Icons.undo, tr('undo'), undo.canUndo ? () => setState(() => {doc!.audio = AudioProject.fromJson(undo.undo(p.toJson())!), _refreshPeaks()}) : null),
      b(Icons.redo, tr('redo'), undo.canRedo ? () => setState(() => {doc!.audio = AudioProject.fromJson(undo.redo(p.toJson())!), _refreshPeaks()}) : null),
      b(Icons.save, tr('save'), _save),
      const SizedBox(width: 8),
      b(Icons.library_add, 'Dodaj pliki do ścieżki', () => _addFiles()),
      b(Icons.playlist_add, 'Nowa ścieżka', () => _edit('track', () => trackId = p.addTrack().id)),
      b(recording ? Icons.stop_circle : Icons.mic, recording ? 'Zatrzymaj nagrywanie' : 'Nagraj mikrofon (nowa ścieżka)', _toggleRecord),
      const SizedBox(width: 8),
      b(Icons.content_cut, 'Przytnij do zaznaczenia', hasSel ? () => _edit('trim', () => p.trimTo(tid, selS, selE)) : null),
      b(Icons.backspace_outlined, 'Wytnij zaznaczenie', hasSel ? () => _edit('cut', () {
            clipboard = p.copyRange(tid, selS, selE);
            p.deleteRange(tid, selS, selE);
            selE = selS;
          }) : null),
      b(Icons.copy, 'Kopiuj', hasSel ? () => setState(() => clipboard = p.copyRange(tid, selS, selE)) : null),
      b(Icons.paste, 'Wklej w miejscu odtwarzania', clipboard.isNotEmpty ? () => _edit('paste', () => p.paste(tid, playhead, clipboard)) : null),
      b(Icons.call_split, 'Podziel w miejscu odtwarzania', () => _edit('split', () => p.splitAt(tid, playhead))),
      b(Icons.volume_off, 'Wycisz zaznaczenie', hasSel ? () => _edit('mute', () => p.muteRange(tid, selS, selE)) : null),
      b(Icons.space_bar, 'Wstaw ciszę', () async {
        final v = await promptText(context, 'Długość ciszy (s)', initial: '1.0');
        final d = double.tryParse(v ?? '');
        if (d != null && d > 0) _edit('silence', () => p.insertSilence(tid, playhead, d));
      }),
      b(Icons.repeat, 'Zapętl / powiel zaznaczenie', hasSel ? () async {
        final v = await promptText(context, 'Liczba powtórzeń', initial: '2');
        final n = int.tryParse(v ?? '');
        if (n != null && n > 0) _edit('dup', () => p.duplicateRange(tid, selS, selE, times: n));
      } : null),
      b(Icons.trending_up, 'Fade in zaznaczenia', hasSel ? () => _edit('fadein', () => _fadeSel(true)) : null),
      b(Icons.trending_down, 'Fade out zaznaczenia', hasSel ? () => _edit('fadeout', () => _fadeSel(false)) : null),
      b(Icons.auto_fix_high, 'Efekt na zaznaczeniu', hasSel ? () => _effectOnSelection(tid) : null),
      b(Icons.bookmark_add_outlined, 'Dodaj znacznik', () => _edit('marker', () => p.markers.add(Marker(playhead, 'Znacznik ${p.markers.length + 1}')))),
      b(Icons.av_timer, 'Wykryj BPM / bity', _detectBeats),
      const SizedBox(width: 8),
      FilledButton.tonalIcon(onPressed: () => _preview(selection: hasSel), icon: const Icon(Icons.play_circle), label: Text(hasSel ? 'Podgląd zaznaczenia' : tr('preview'))),
      const SizedBox(width: 8),
      FilledButton.icon(onPressed: _export, icon: const Icon(Icons.ios_share), label: Text(tr('export'))),
    ]);
  }

  void _fadeSel(bool fadeIn) {
    final tid = trackId ?? p.tracks.first.id;
    p.splitAt(tid, selS);
    p.splitAt(tid, selE);
    for (final c in p.track(tid).clips) {
      if (c.position >= selS - 1e-6 && c.end <= selE + 1e-6) {
        if (fadeIn) {
          c.fadeIn = c.length;
        } else {
          c.fadeOut = c.length;
        }
      }
    }
  }

  Future<void> _effectOnSelection(String tid) async {
    final fx = await _pickEffect();
    if (fx == null) return;
    _edit('fxsel', () {
      p.splitAt(tid, selS);
      p.splitAt(tid, selE);
      for (final c in p.track(tid).clips) {
        if (c.position >= selS - 1e-6 && c.end <= selE + 1e-6) c.effects.add(fx.copy());
      }
    });
  }

  Future<AudioEffect?> _pickEffect() => showDialog<AudioEffect>(
        context: context,
        builder: (c) => SimpleDialog(title: const Text('Dodaj efekt'), children: [
          for (final d in fxDefs.values) SimpleDialogOption(onPressed: () => Navigator.pop(c, AudioEffect(d.type)), child: Text(d.namePl)),
        ]),
      );

  Widget _editor() {
    final dur = p.duration;
    final wide = MediaQuery.sizeOf(context).width > 1000;
    final tracks = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(doc!.name, style: Theme.of(context).textTheme.titleLarge, overflow: TextOverflow.ellipsis)),
        Text('Długość ${fmtTime(dur)}  •  kursor ${fmtTime(playhead)}  •  zaznaczenie ${selE > selS ? '${fmtTime(selS)}–${fmtTime(selE)}' : '–'}'),
      ]),
      _toolbar(),
      Row(children: [
        const Text('Powiększenie'),
        Expanded(child: Slider(value: zoom, min: 1, max: 200, onChanged: (v) => setState(() => zoom = v))),
        const Text('Przewijanie'),
        Expanded(child: Slider(value: scroll, onChanged: zoom > 1 ? (v) => setState(() => scroll = v) : null)),
      ]),
      for (final t in p.tracks) _trackRow(t, dur),
      if (previewPath != null) PreviewPlayer(path: previewPath, audioOnly: true, onCreated: _attachPlayer),
    ]);
    final side = _inspector();
    if (wide) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: tracks)),
        SizedBox(width: 380, child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: side)),
      ]);
    }
    return ListView(padding: const EdgeInsets.all(8), children: [tracks, side]);
  }

  Widget _trackRow(AudioTrack t, double dur) {
    final sel = t.id == trackId;
    return Card(
      color: sel ? WmsColors.panel2 : null,
      child: InkWell(
        onTap: () => setState(() => trackId = t.id),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(t.name, style: TextStyle(fontWeight: sel ? FontWeight.bold : FontWeight.normal))),
              IconButton(tooltip: 'Wycisz ścieżkę', icon: Icon(t.muted ? Icons.volume_off : Icons.volume_up, size: 18), onPressed: () => _edit('m', () => t.muted = !t.muted)),
              IconButton(tooltip: 'Solo', icon: Icon(Icons.headphones, size: 18, color: t.solo ? WmsColors.warn : null), onPressed: () => _edit('s', () => t.solo = !t.solo)),
              IconButton(tooltip: 'Zablokuj', icon: Icon(t.locked ? Icons.lock : Icons.lock_open, size: 18), onPressed: () => setState(() => t.locked = !t.locked)),
              SizedBox(width: 120, child: Slider(value: t.gainDb, min: -30, max: 12, onChanged: (v) => setState(() => t.gainDb = v), onChangeEnd: (_) => _edit('g', () {}))),
              Text('${t.gainDb.toStringAsFixed(1)} dB', style: const TextStyle(fontSize: 11)),
              if (p.tracks.length > 1) IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => _edit('rmtrack', () => {p.tracks.remove(t), trackId = p.tracks.first.id})),
            ]),
            if (t.clips.isEmpty)
              OutlinedButton.icon(onPressed: () => _addFiles(toTrack: t.id), icon: const Icon(Icons.add), label: const Text('Dodaj plik audio lub wideo'))
            else
              WaveformView(
                peaks: peaks[t.id] ?? Float32List(0),
                duration: t.end,
                selStart: sel ? selS : 0,
                selEnd: sel ? selE : 0,
                playhead: playhead,
                zoom: zoom,
                scroll: scroll,
                markers: p.markers.map((m) => m.t).toList(),
                beats: beatsAnalysis?.beats ?? const [],
                height: 90,
                onSelect: t.locked ? (_, _) {} : (s, e) => setState(() => {trackId = t.id, selS = s, selE = e}),
                onSeek: (x) {
                  setState(() => {playhead = x, trackId = t.id, selE = selS});
                  if (player != null && x >= previewOffset) player!.seek(Duration(milliseconds: ((x - previewOffset) * 1000).round()));
                },
              ),
          ]),
        ),
      ),
    );
  }

  Widget _inspector() {
    final t = selTrack;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (t != null)
        Section(title: 'Fragmenty ścieżki „${t.name}”', children: [
          if (t.clips.isEmpty) const Text('Brak fragmentów'),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: true,
            onReorder: (a, b) => _edit('reorder', () => p.reorder(t.id, a, b > a ? b - 1 : b)),
            children: [
              for (final c in (t..sortClips()).clips)
                ListTile(
                  key: ValueKey(c.id),
                  dense: true,
                  title: Text('${doc!.assets[c.assetId]?.name ?? c.assetId}${c.muted ? ' (wyciszony)' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${fmtTime(c.position)} → ${fmtTime(c.end)}  ${c.tempo != 1 ? '• tempo ${c.tempo.toStringAsFixed(2)}×' : ''}${c.pitch != 0 ? ' • ton ${c.pitch.toStringAsFixed(1)}' : ''}${c.effects.isNotEmpty ? ' • ${c.effects.length} efekt(ów)' : ''}'),
                  onTap: () => _clipDialog(c),
                ),
            ],
          ),
          TextButton.icon(onPressed: () => _edit('pack', () => p.packSequential(t.id, crossfade: 0)), icon: const Icon(Icons.view_stream), label: const Text('Połącz kolejno (bez przerw)')),
          TextButton.icon(onPressed: () => _edit('xfade', () => p.packSequential(t.id, crossfade: 2)), icon: const Icon(Icons.compare_arrows), label: const Text('Połącz z crossfade 2 s')),
        ]),
      if (t != null) _fxChain('Efekty ścieżki', t.effects),
      _fxChain('Efekty master (mastering)', p.masterEffects, presets: true),
      Section(title: 'Master', children: [
        LabeledSlider(label: 'Głośność master', value: p.masterGainDb, min: -24, max: 12, unit: 'dB', onChanged: (v) => setState(() => p.masterGainDb = v)),
      ]),
      if (p.markers.isNotEmpty)
        Section(title: 'Znaczniki', children: [
          for (final m in p.markers)
            ListTile(dense: true, title: Text(m.label), subtitle: Text(fmtTime(m.t)), onTap: () => setState(() => playhead = m.t), trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => _edit('rmm', () => p.markers.remove(m)))),
        ]),
    ]);
  }

  Widget _fxChain(String title, List<AudioEffect> list, {bool presets = false}) => Section(
        title: title,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (presets)
            PopupMenuButton<String>(
              tooltip: 'Presety',
              icon: const Icon(Icons.auto_awesome),
              onSelected: (id) {
                if (id == '__save') {
                  promptText(context, 'Nazwa presetu').then((n) {
                    if (n != null && n.isNotEmpty) Services.i.kv.put('fxPresets', n, {'name': n, 'effects': list.map((e) => e.toJson()).toList()});
                  });
                  return;
                }
                final f = factoryFxPresets.where((p) => p.id == id).firstOrNull;
                final u = Services.i.kv.get('fxPresets', id);
                _edit('preset', () {
                  list.clear();
                  if (f != null) list.addAll(f.build());
                  if (u != null) list.addAll(jl(u['effects']).map(AudioEffect.fromJson));
                });
              },
              itemBuilder: (c) => [
                for (final f in factoryFxPresets) PopupMenuItem(value: f.id, child: Text(f.namePl)),
                for (final k in Services.i.kv.keys('fxPresets')) PopupMenuItem(value: k, child: Text('★ $k')),
                const PopupMenuItem(value: '__save', child: Text('Zapisz bieżący jako preset…')),
              ],
            ),
          IconButton(icon: const Icon(Icons.add), onPressed: () async {
            final fx = await _pickEffect();
            if (fx != null) _edit('fx', () => list.add(fx));
          }),
        ]),
        children: [
          if (list.isEmpty) const Text('Brak efektów', style: TextStyle(color: WmsColors.muted)),
          for (final e in list) _FxEditor(fx: e, onChanged: () => setState(() => dirty = true), onRemove: () => _edit('rmfx', () => list.remove(e))),
        ],
      );

  Future<void> _clipDialog(AudioClip c) async {
    undo.push(p.toJson(), 'clip');
    await showDialog<void>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(doc!.assets[c.assetId]?.name ?? 'Fragment'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                LabeledSlider(label: 'Początek w źródle', value: c.srcIn, min: 0, max: c.srcOut - 0.05, unit: 's', decimals: 2, onChanged: (v) => set(() => c.srcIn = v)),
                LabeledSlider(label: 'Koniec w źródle', value: c.srcOut, min: c.srcIn + 0.05, max: doc!.assets[c.assetId]?.duration ?? c.srcOut, unit: 's', decimals: 2, onChanged: (v) => set(() => c.srcOut = v)),
                LabeledSlider(label: 'Pozycja na osi', value: c.position, min: 0, max: p.duration + 30, unit: 's', decimals: 2, onChanged: (v) => set(() => c.position = v)),
                LabeledSlider(label: 'Głośność', value: c.gainDb, min: -40, max: 24, unit: 'dB', onChanged: (v) => set(() => c.gainDb = v)),
                LabeledSlider(label: 'Fade in', value: c.fadeIn, min: 0, max: c.length, unit: 's', onChanged: (v) => set(() => c.fadeIn = v)),
                LabeledSlider(label: 'Fade out', value: c.fadeOut, min: 0, max: c.length, unit: 's', onChanged: (v) => set(() => c.fadeOut = v)),
                LabeledSlider(label: 'Tempo (bez zmiany tonu)', value: c.tempo, min: 0.25, max: 4, unit: '×', decimals: 2, onChanged: (v) => set(() => c.tempo = v)),
                LabeledSlider(label: 'Ton (bez zmiany tempa)', value: c.pitch, min: -12, max: 12, unit: 'st', onChanged: (v) => set(() => c.pitch = v)),
                Row(children: [
                  const Text('Powtórzenia (pętla)'),
                  const Spacer(),
                  IconButton(onPressed: () => set(() => c.loops = (c.loops - 1).clamp(1, 1000)), icon: const Icon(Icons.remove)),
                  Text('${c.loops}'),
                  IconButton(onPressed: () => set(() => c.loops++), icon: const Icon(Icons.add)),
                ]),
                SwitchListTile(value: c.reverse, onChanged: (v) => set(() => c.reverse = v), title: const Text('Odwróć dźwięk')),
                SwitchListTile(value: c.muted, onChanged: (v) => set(() => c.muted = v), title: const Text('Wyciszony')),
                Row(children: [
                  const Expanded(child: Text('Automatyzacja głośności')),
                  TextButton(
                    onPressed: () => set(() => c.volumeAuto.add(Keyframe((playhead - c.position).clamp(0, c.length).toDouble(), c.volumeAuto.isEmpty ? 1 : 0.5))),
                    child: const Text('+ punkt w kursorze'),
                  ),
                  if (c.volumeAuto.isNotEmpty) TextButton(onPressed: () => set(() => c.volumeAuto.clear()), child: const Text('Wyczyść')),
                ]),
                for (final k in c.volumeAuto) LabeledSlider(label: 't=${k.t.toStringAsFixed(2)}s', value: k.v, min: 0, max: 2, onChanged: (v) => set(() => c.volumeAuto[c.volumeAuto.indexOf(k)] = Keyframe(k.t, v))),
                const Divider(),
                for (final e in c.effects) _FxEditor(fx: e, onChanged: () => set(() {}), onRemove: () => set(() => c.effects.remove(e))),
                TextButton.icon(onPressed: () async {
                  final fx = await _pickEffect();
                  if (fx != null) set(() => c.effects.add(fx));
                }, icon: const Icon(Icons.add), label: const Text('Dodaj efekt do fragmentu')),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () {
              set(() => selTrack!.clips.remove(c));
              Navigator.pop(d);
            }, child: Text(tr('delete'))),
            TextButton(onPressed: () {
              selTrack!.clips.add(c.copy()..position = c.end);
              Navigator.pop(d);
            }, child: const Text('Duplikuj')),
            FilledButton(onPressed: () => Navigator.pop(d), child: const Text('OK')),
          ],
        ),
      ),
    );
    setState(() => dirty = true);
    _refreshPeaks();
  }
}

class _FxEditor extends StatelessWidget {
  final AudioEffect fx;
  final VoidCallback onChanged, onRemove;
  const _FxEditor({required this.fx, required this.onChanged, required this.onRemove});
  @override
  Widget build(BuildContext context) {
    final d = fxDefs[fx.type]!;
    return Card(
      color: WmsColors.panel2,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(children: [
          Row(children: [
            Checkbox(value: fx.enabled, onChanged: (v) => {fx.enabled = v!, onChanged()}),
            Expanded(child: Text(d.namePl, style: const TextStyle(fontWeight: FontWeight.w600))),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onRemove),
          ]),
          for (final prm in d.params)
            LabeledSlider(label: prm.labelPl, value: fx.p(prm.key), min: prm.min, max: prm.max, unit: prm.unit, decimals: prm.max - prm.min > 50 ? 0 : 2, onChanged: (v) => {fx.params[prm.key] = v, onChanged()}),
        ]),
      ),
    );
  }
}
