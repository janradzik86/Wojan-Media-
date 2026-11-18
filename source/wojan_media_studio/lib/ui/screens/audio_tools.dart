import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:record/record.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../engine/audio/audio_compiler.dart';
import '../../engine/audio/audio_project.dart';
import '../../engine/audio/effects.dart';
import '../../engine/audio/tools.dart';
import '../../engine/dsp/analysis.dart';
import '../../engine/dsp/pcm.dart';
import '../../engine/export/audio_formats.dart';
import '../../engine/ffmpeg/probe.dart';
import '../../engine/ffmpeg/runner.dart';
import '../../engine/project/asset.dart';
import '../../engine/util/json_util.dart';
import '../../platform/native.dart';
import '../widgets/common.dart';
import '../widgets/player.dart';
import '../widgets/waveform.dart';
import 'render_result.dart';

class _Tool {
  final String id, name, desc;
  final IconData icon;
  const _Tool(this.id, this.name, this.desc, this.icon);
}

const _tools = [
  _Tool('cut', 'Przycinanie', 'Wybierz najlepszy fragment, fade in/out', Icons.content_cut),
  _Tool('omit', 'Usuń fragment', 'Wytnij część ze środka utworu', Icons.remove_circle_outline),
  _Tool('split', 'Podziel', 'Podziel plik na dwie części', Icons.call_split),
  _Tool('merge', 'Połącz', 'Połącz wiele utworów (z crossfade)', Icons.merge_type),
  _Tool('mix', 'Mikser', 'Nałóż kilka dźwięków (remiks, mashup)', Icons.layers),
  _Tool('convert', 'Konwerter', 'MP3, WAV, FLAC, AAC, M4A, OGG, OPUS, WMA…', Icons.swap_horiz),
  _Tool('batch', 'Konwersja wsadowa', 'Wiele plików naraz', Icons.dynamic_feed),
  _Tool('extract', 'Wideo → audio', 'Wyodrębnij ścieżkę dźwiękową z filmu', Icons.movie_filter),
  _Tool('speed', 'Tempo / ton / prędkość', 'Zmień tempo bez zmiany tonu i odwrotnie', Icons.speed),
  _Tool('volume', 'Głośność i normalizacja', 'Wzmocnienie, normalizacja szczytowa, LUFS', Icons.volume_up),
  _Tool('fx', 'Efekty i presety', 'Korektor, pogłos, echo, kompresor, odszumianie…', Icons.auto_fix_high),
  _Tool('vocal', 'Usuwanie wokalu', 'Karaoke – DSP (przybliżone)', Icons.mic_off),
  _Tool('silence', 'Usuń ciszę', 'Automatyczne wykrycie i usunięcie ciszy', Icons.space_bar),
  _Tool('reverse', 'Odwróć', 'Odtwarzanie wstecz', Icons.fast_rewind),
  _Tool('tags', 'Edytor tagów', 'Tytuł, wykonawca, album, okładka (ID3)', Icons.label),
  _Tool('ringtone', 'Dzwonek', 'Utwórz dzwonek / powiadomienie', Icons.ring_volume),
  _Tool('record', 'Dyktafon', 'Nagrywanie z mikrofonu', Icons.mic),
];

class AudioToolsPanel extends StatelessWidget {
  const AudioToolsPanel({super.key});
  @override
  Widget build(BuildContext context) => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 260, childAspectRatio: 1.6, crossAxisSpacing: 10, mainAxisSpacing: 10),
        itemCount: _tools.length,
        itemBuilder: (c, i) {
          final t = _tools[i];
          return Card(
            child: InkWell(
              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => AudioToolScreen(tool: t.id, title: t.name))),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(t.icon, color: WmsColors.accent, size: 30),
                  const Spacer(),
                  Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(t.desc, style: const TextStyle(fontSize: 12, color: WmsColors.muted), maxLines: 2),
                ]),
              ),
            ),
          );
        },
      );
}

class AudioToolScreen extends StatefulWidget {
  final String tool, title;
  const AudioToolScreen({super.key, required this.tool, required this.title});
  @override
  State<AudioToolScreen> createState() => _AudioToolScreenState();
}

class _AudioToolScreenState extends State<AudioToolScreen> {
  final tools = AudioTools(Services.i.runner);
  List<String> inputs = [];
  MediaInfo? info;
  Float32List peaks = Float32List(0);
  double s = 0, e = 0, fadeIn = 0, fadeOut = 0, tempo = 1, pitch = 0, speed = 1, gain = 0, crossfade = 0, lufs = -14, peakDb = -1, silThr = -45, silDur = 0.6;
  String normMode = 'gain';
  final out = AudioExportSettings();
  final fx = <AudioEffect>[];
  final tags = <String, String>{'title': '', 'artist': '', 'album': '', 'genre': '', 'date': '', 'track': '', 'comment': ''};
  String? cover;
  final vols = <double>[];
  final offs = <double>[];
  double progress = 0;
  CancelToken? cancel;
  String? previewPath;
  final recorder = AudioRecorder();
  bool recording = false;
  DateTime? recStart;

  bool get multi => ['merge', 'mix', 'batch'].contains(widget.tool);
  bool get needsRange => ['cut', 'omit', 'split', 'ringtone'].contains(widget.tool);

  @override
  void dispose() {
    recorder.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final ext = widget.tool == 'extract' ? videoExt : [...audioExt, ...videoExt];
    final f = await pickFiles(extensions: ext, multiple: multi);
    if (f.isEmpty) return;
    setState(() {
      inputs = multi ? [...inputs, ...f] : f;
      vols.addAll(List.filled(f.length, 0));
      offs.addAll(List.filled(f.length, 0));
    });
    if (!multi) await _load(f.first);
  }

  Future<void> _load(String path) async {
    final i = MediaInfo.fromProbe(path, await Services.i.runner.probeJson(path));
    setState(() {
      info = i;
      s = 0;
      e = widget.tool == 'ringtone' ? math.min(30, i.duration) : i.duration;
      for (final k in tags.keys) {
        tags[k] = i.tags[k] ?? '';
      }
      if (AudioExportSettings.formatFromExtension(extOf(path)) != null && widget.tool != 'convert') out.format = AudioExportSettings.formatFromExtension(extOf(path))!;
      if (widget.tool == 'ringtone') out.format = AudioFormat.mp3;
    });
    if (i.hasAudio) {
      final pcm = await PcmDecoder(Services.i.runner, Directory('${Services.i.store.cacheDir.path}/pcm')).decode(path, sampleRate: 8000);
      if (mounted) setState(() => peaks = AudioAnalyzer.waveformPeaks(pcm.samples, 3000));
    }
  }

  List<AudioEffect> _chain() {
    switch (widget.tool) {
      case 'speed':
        return [if (tempo != 1) AudioEffect(AudioFx.tempo, {'factor': tempo}), if (pitch != 0) AudioEffect(AudioFx.pitch, {'semitones': pitch}), if (speed != 1) AudioEffect(AudioFx.speed, {'factor': speed})];
      case 'volume':
        return [if (normMode == 'gain') AudioEffect(AudioFx.volume, {'gain': gain}), AudioEffect(AudioFx.limiter, {'ceiling': -0.3})];
      case 'fx':
        return fx;
      case 'vocal':
        return [AudioEffect(AudioFx.vocalRemove)];
      case 'silence':
        return [AudioEffect(AudioFx.silenceRemove, {'threshold': silThr, 'minDur': silDur})];
      case 'reverse':
        return [AudioEffect(AudioFx.reverse)];
    }
    return [];
  }

  Future<String> _run({bool preview = false}) async {
    final first = inputs.first;
    final base = first.split(RegExp(r'[\\/]')).last;
    final stem = base.contains('.') ? base.substring(0, base.lastIndexOf('.')) : base;
    final settings = preview ? AudioExportSettings(format: AudioFormat.m4a, bitrateKbps: 160) : out;
    final o = preview ? '${Services.i.store.cacheDir.path}/tool_preview_${DateTime.now().millisecondsSinceEpoch}.m4a' : exportPath('${stem}_${widget.tool}', settings.extension);
    cancel = CancelToken();
    void prog(double t) => setState(() => progress = info == null || info!.duration <= 0 ? 0 : (t / info!.duration).clamp(0, 1));
    switch (widget.tool) {
      case 'cut':
        await tools.cut(first, o, settings, s, e, fadeIn: fadeIn, fadeOut: fadeOut, cancel: cancel);
      case 'ringtone':
        await tools.cut(first, o, settings, s, math.min(e, s + 40), fadeIn: 0.3, fadeOut: 1.0, cancel: cancel);
      case 'omit':
        await tools.omit(first, o, settings, s, e);
      case 'split':
        final o2 = o.replaceFirst('.${settings.extension}', '_cz2.${settings.extension}');
        await tools.split(first, o, o2, settings, s > 0 ? s : (e < (info?.duration ?? 0) ? e : (info?.duration ?? 0) / 2));
      case 'merge':
        await tools.merge(inputs, o, settings, crossfade: crossfade, onProgress: prog, cancel: cancel);
      case 'mix':
        await tools.mix(inputs, o, settings, volumesDb: vols.take(inputs.length).toList(), offsets: offs.take(inputs.length).toList());
      case 'extract':
        await tools.extractFromVideo(first, o, settings, onProgress: prog, cancel: cancel);
      case 'volume' when normMode == 'lufs':
        await tools.normalizeLufs(first, o, settings, targetLufs: lufs);
      case 'volume' when normMode == 'peak':
        await tools.normalizePeak(first, o, settings, targetDb: peakDb);
      case 'tags':
        final ext = extOf(first);
        final tagOut = preview ? o : exportPath(stem, ext);
        await tools.writeTags(first, tagOut, Map.fromEntries(tags.entries.where((e) => e.value.isNotEmpty)), coverImage: cover);
        return tagOut;
      case 'convert':
      case 'speed':
      case 'volume':
      case 'fx':
      case 'vocal':
      case 'silence':
      case 'reverse':
        final ch = _chain();
        if (ch.any((e) => e.type == AudioFx.reverb)) {
          // reverb needs an impulse response input → project renderer path
          await _renderChainViaProject(first, o, settings, ch, prog);
        } else {
          await tools.convert(first, o, settings, effects: ch, onProgress: prog, cancel: cancel, metadata: const {});
        }
    }
    return o;
  }

  Future<void> _renderChainViaProject(String input, String o, AudioExportSettings st, List<AudioEffect> ch, ProgressCb prog) async {
    final i = info ?? MediaInfo.fromProbe(input, await Services.i.runner.probeJson(input));
    final asset = MediaAsset(id: 'src', name: input, kind: i.kind, sha256: '', size: i.sizeBytes, relPath: '', duration: i.duration, localPath: input);
    final ap = AudioProject(sampleRate: st.sampleRate);
    final c = ap.appendAsset(ap.tracks.first.id, 'src', i.duration);
    c.effects.addAll(ch);
    await AudioRenderer(Services.i.runner, Directory('${Services.i.store.cacheDir.path}/audio')).render(ap, MapAssetResolver({'src': asset}, ''), o, st, onProgress: prog, cancel: cancel);
  }

  Future<void> _go({bool preview = false}) async {
    if (inputs.isEmpty) return;
    setState(() => progress = 0.001);
    try {
      final o = await _run(preview: preview);
      if (!mounted) return;
      if (preview) {
        setState(() => previewPath = o);
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (_) => RenderResultScreen(path: o)));
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => progress = 0);
    }
  }

  Future<void> _toggleRecord() async {
    if (recording) {
      final p = await recorder.stop();
      setState(() => recording = false);
      if (p != null && mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => RenderResultScreen(path: p)));
      return;
    }
    if (!await recorder.hasPermission()) {
      if (mounted) toast(context, 'Brak uprawnienia do mikrofonu', error: true);
      return;
    }
    final enc = switch (out.format) { AudioFormat.wav => AudioEncoder.wav, AudioFormat.flac => AudioEncoder.flac, AudioFormat.opus => AudioEncoder.opus, _ => AudioEncoder.aacLc };
    final ext = switch (enc) { AudioEncoder.wav => 'wav', AudioEncoder.flac => 'flac', AudioEncoder.opus => 'opus', _ => 'm4a' };
    await recorder.start(RecordConfig(encoder: enc, sampleRate: out.sampleRate, numChannels: out.channels, bitRate: out.bitrateKbps * 1000), path: exportPath('Nagranie', ext));
    setState(() {
      recording = true;
      recStart = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dur = info?.duration ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.tool == 'record')
          Section(title: 'Nagrywanie', children: [
            _formatPicker(),
            const SizedBox(height: 12),
            Center(child: FloatingActionButton.large(onPressed: _toggleRecord, backgroundColor: recording ? WmsColors.error : WmsColors.accent, child: Icon(recording ? Icons.stop : Icons.mic))),
            if (recording) StreamBuilder(stream: Stream<int>.periodic(const Duration(milliseconds: 200), (i) => i), builder: (c, _) => Center(child: Text(fmtTime(DateTime.now().difference(recStart!).inMilliseconds / 1000), style: const TextStyle(fontSize: 28)))),
          ])
        else ...[
          Section(title: multi ? 'Pliki (${inputs.length})' : 'Plik źródłowy', trailing: FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.folder_open), label: Text(tr('import'))), children: [
            if (inputs.isEmpty) const Text('Wybierz plik(i) – obsługiwane: MP3, WAV, FLAC, AAC, M4A, OGG, OPUS, WMA, wideo…', style: TextStyle(color: WmsColors.muted)),
            if (multi)
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorder: (a, b) => setState(() {
                  final x = inputs.removeAt(a);
                  inputs.insert(b > a ? b - 1 : b, x);
                }),
                children: [
                  for (var i = 0; i < inputs.length; i++)
                    ListTile(
                      key: ValueKey('$i${inputs[i]}'),
                      dense: true,
                      title: Text(inputs[i].split(RegExp(r'[\\/]')).last),
                      subtitle: widget.tool == 'mix'
                          ? Column(children: [
                              LabeledSlider(label: 'Głośność', value: vols[i], min: -30, max: 12, unit: 'dB', onChanged: (v) => setState(() => vols[i] = v)),
                              LabeledSlider(label: 'Przesunięcie', value: offs[i], min: 0, max: 60, unit: 's', onChanged: (v) => setState(() => offs[i] = v)),
                            ])
                          : null,
                      trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => inputs.removeAt(i))),
                    ),
                ],
              ),
            if (info != null) MediaInfoView(info!),
          ]),
          if (needsRange && info != null)
            Section(title: 'Zakres', children: [
              WaveformView(peaks: peaks, duration: dur, selStart: s, selEnd: e, onSelect: (a, b) => setState(() => {s = a, e = b}), height: 110),
              LabeledSlider(label: widget.tool == 'split' ? 'Punkt podziału' : 'Początek', value: s, min: 0, max: dur, unit: 's', decimals: 2, onChanged: (v) => setState(() => s = math.min(v, e))),
              if (widget.tool != 'split') LabeledSlider(label: 'Koniec', value: e, min: 0, max: dur, unit: 's', decimals: 2, onChanged: (v) => setState(() => e = math.max(v, s))),
              if (widget.tool == 'cut') LabeledSlider(label: 'Fade in', value: fadeIn, min: 0, max: 10, unit: 's', onChanged: (v) => setState(() => fadeIn = v)),
              if (widget.tool == 'cut') LabeledSlider(label: 'Fade out', value: fadeOut, min: 0, max: 10, unit: 's', onChanged: (v) => setState(() => fadeOut = v)),
              Text('Długość wyniku: ${fmtTime(widget.tool == 'omit' ? dur - (e - s) : e - s)}'),
            ]),
          ..._params(),
          if (widget.tool != 'tags') Section(title: 'Plik wynikowy', children: [_formatPicker()]),
          if (previewPath != null) PreviewPlayer(path: previewPath, audioOnly: true),
          if (progress > 0) Padding(padding: const EdgeInsets.all(8), child: Row(children: [Expanded(child: LinearProgressIndicator(value: progress < 0.01 ? null : progress)), IconButton(icon: const Icon(Icons.cancel), onPressed: () => cancel?.cancel())])),
          Wrap(spacing: 8, children: [
            if (!multi && widget.tool != 'split') OutlinedButton.icon(onPressed: inputs.isEmpty ? null : () => _go(preview: true), icon: const Icon(Icons.play_arrow), label: Text(tr('preview'))),
            FilledButton.icon(onPressed: inputs.isEmpty || progress > 0 ? null : _go, icon: const Icon(Icons.save), label: Text(tr('save'))),
            if (widget.tool == 'ringtone' && Platform.isAndroid)
              OutlinedButton.icon(onPressed: inputs.isEmpty ? null : () async {
                final o = await _run();
                final ok = await NativeBridge.setRingtone(o);
                if (context.mounted) toast(context, ok ? 'Ustawiono jako dzwonek' : 'Zapisano dzwonek. Ustawienie wymaga zgody „Modyfikowanie ustawień systemu”.');
              }, icon: const Icon(Icons.phone_in_talk), label: const Text('Zapisz i ustaw jako dzwonek')),
          ]),
        ],
      ]),
    );
  }

  Widget _formatPicker() => Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        DropdownButton<AudioFormat>(value: out.format, items: [for (final f in AudioFormat.values) DropdownMenuItem(value: f, child: Text(f.name.toUpperCase()))], onChanged: (v) => setState(() => out.format = v!)),
        if (!out.lossless) DropdownButton<int>(value: out.bitrateKbps, items: [for (final b in [64, 96, 128, 160, 192, 256, 320]) DropdownMenuItem(value: b, child: Text('$b kb/s'))], onChanged: (v) => setState(() => out.bitrateKbps = v!)),
        DropdownButton<int>(value: out.sampleRate, items: [for (final r in [8000, 16000, 22050, 32000, 44100, 48000, 96000]) DropdownMenuItem(value: r, child: Text('$r Hz'))], onChanged: (v) => setState(() => out.sampleRate = v!)),
        DropdownButton<int>(value: out.channels, items: const [DropdownMenuItem(value: 1, child: Text('Mono')), DropdownMenuItem(value: 2, child: Text('Stereo'))], onChanged: (v) => setState(() => out.channels = v!)),
        if (info != null) Text('≈ ${fmtBytes(out.estimateSize(info!.duration))}', style: const TextStyle(color: WmsColors.muted)),
      ]);

  List<Widget> _params() {
    switch (widget.tool) {
      case 'merge':
        return [Section(title: 'Łączenie', children: [LabeledSlider(label: 'Crossfade', value: crossfade, min: 0, max: 10, unit: 's', onChanged: (v) => setState(() => crossfade = v))])];
      case 'speed':
        return [
          Section(title: 'Tempo i ton', children: [
            LabeledSlider(label: 'Tempo (ton bez zmian)', value: tempo, min: 0.25, max: 4, unit: '×', decimals: 2, onChanged: (v) => setState(() => tempo = v)),
            LabeledSlider(label: 'Ton (tempo bez zmian)', value: pitch, min: -12, max: 12, unit: 'półt.', onChanged: (v) => setState(() => pitch = v)),
            LabeledSlider(label: 'Prędkość (ton+tempo)', value: speed, min: 0.25, max: 4, unit: '×', decimals: 2, onChanged: (v) => setState(() => speed = v)),
          ])
        ];
      case 'volume':
        return [
          Section(title: 'Głośność', children: [
            SegmentedButton<String>(segments: const [ButtonSegment(value: 'gain', label: Text('Wzmocnienie')), ButtonSegment(value: 'peak', label: Text('Normalizacja szczytu')), ButtonSegment(value: 'lufs', label: Text('Normalizacja LUFS'))], selected: {normMode}, onSelectionChanged: (s) => setState(() => normMode = s.first)),
            if (normMode == 'gain') LabeledSlider(label: 'Wzmocnienie', value: gain, min: -30, max: 30, unit: 'dB', onChanged: (v) => setState(() => gain = v)),
            if (normMode == 'peak') LabeledSlider(label: 'Szczyt docelowy', value: peakDb, min: -12, max: 0, unit: 'dBFS', onChanged: (v) => setState(() => peakDb = v)),
            if (normMode == 'lufs') LabeledSlider(label: 'Głośność docelowa', value: lufs, min: -30, max: -6, unit: 'LUFS', onChanged: (v) => setState(() => lufs = v)),
            if (normMode == 'lufs') const Text('YouTube/Spotify ≈ -14 LUFS, Apple Music ≈ -16 LUFS, podcasty ≈ -16…-19 LUFS. Dwuprzebiegowa normalizacja EBU R128.', style: TextStyle(color: WmsColors.muted, fontSize: 12)),
          ])
        ];
      case 'silence':
        return [
          Section(title: 'Cisza', children: [
            LabeledSlider(label: 'Próg', value: silThr, min: -80, max: -20, unit: 'dB', onChanged: (v) => setState(() => silThr = v)),
            LabeledSlider(label: 'Min. długość', value: silDur, min: 0.1, max: 5, unit: 's', onChanged: (v) => setState(() => silDur = v)),
            if (inputs.isNotEmpty)
              TextButton(onPressed: () async {
                final r = await tools.detectSilence(inputs.first, thresholdDb: silThr, minDur: silDur);
                if (mounted) toast(context, 'Wykryto ${r.length} fragmentów ciszy (łącznie ${fmtTime(r.fold(0.0, (a, b) => a + b.end - b.start))})');
              }, child: const Text('Wykryj ciszę')),
          ])
        ];
      case 'fx':
        return [
          Section(
            title: 'Łańcuch efektów',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              PopupMenuButton<String>(icon: const Icon(Icons.auto_awesome), onSelected: (id) => setState(() => {fx.clear(), fx.addAll(factoryFxPresets.firstWhere((p) => p.id == id).build())}), itemBuilder: (c) => [for (final p in factoryFxPresets) PopupMenuItem(value: p.id, child: Text(p.namePl))]),
              IconButton(icon: const Icon(Icons.add), onPressed: () async {
                final t = await showDialog<AudioFx>(context: context, builder: (c) => SimpleDialog(children: [for (final d in fxDefs.values) SimpleDialogOption(onPressed: () => Navigator.pop(c, d.type), child: Text(d.namePl))]));
                if (t != null) setState(() => fx.add(AudioEffect(t)));
              }),
            ]),
            children: [
              for (final f in fx)
                Card(
                  color: WmsColors.panel2,
                  child: Column(children: [
                    ListTile(dense: true, title: Text(fxDefs[f.type]!.namePl), trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => fx.remove(f)))),
                    for (final p in fxDefs[f.type]!.params) LabeledSlider(label: p.labelPl, value: f.p(p.key), min: p.min, max: p.max, unit: p.unit, decimals: 2, onChanged: (v) => setState(() => f.params[p.key] = v)),
                  ]),
                ),
            ],
          )
        ];
      case 'tags':
        return [
          Section(title: 'Tagi', children: [
            for (final k in tags.keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: TextField(controller: TextEditingController(text: tags[k]), decoration: InputDecoration(labelText: {'title': 'Tytuł', 'artist': 'Wykonawca', 'album': 'Album', 'genre': 'Gatunek', 'date': 'Rok', 'track': 'Nr utworu', 'comment': 'Komentarz'}[k]), onChanged: (v) => tags[k] = v),
              ),
            Row(children: [
              OutlinedButton.icon(onPressed: () async {
                final f = await pickFiles(extensions: ['jpg', 'jpeg', 'png'], multiple: false);
                if (f.isNotEmpty) setState(() => cover = f.first);
              }, icon: const Icon(Icons.image), label: const Text('Okładka')),
              const SizedBox(width: 8),
              if (cover != null) Image.file(File(cover!), height: 64),
            ]),
          ])
        ];
      case 'vocal':
        return [const Section(title: 'Uwaga', children: [Text('Usuwanie wokalu działa przez odejmowanie kanałów (DSP) – skuteczne dla wokalu nagranego centralnie w miksie stereo. To nie jest separacja AI; efekty mogą być niepełne.', style: TextStyle(color: WmsColors.muted))])];
    }
    return [];
  }
}

/// Spectrum / frequency / level / BPM / clipping analysis panel.
class AudioAnalysisPanel extends StatefulWidget {
  final Future<String> Function()? projectRender;
  const AudioAnalysisPanel({super.key, this.projectRender});
  @override
  State<AudioAnalysisPanel> createState() => _AudioAnalysisPanelState();
}

class _AudioAnalysisPanelState extends State<AudioAnalysisPanel> {
  String? path;
  AudioAnalysis? a;
  PcmData? pcm;
  LoudnessReport? loud;
  double pos = 0;
  final taps = <DateTime>[];

  Future<void> _analyze(String p) async {
    await runBusy(context, 'Analiza sygnału…', () async {
      final dec = await PcmDecoder(Services.i.runner, Directory('${Services.i.store.cacheDir.path}/pcm')).decode(p);
      final an = AudioAnalyzer.analyze(dec);
      final l = await AudioTools(Services.i.runner).measureLoudness(p);
      setState(() {
        path = p;
        pcm = dec;
        a = an;
        loud = l;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final an = a;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Wrap(spacing: 8, children: [
        FilledButton.icon(onPressed: () async {
          final f = await pickFiles(extensions: [...audioExt, ...videoExt], multiple: false);
          if (f.isNotEmpty) await _analyze(f.first);
        }, icon: const Icon(Icons.folder_open), label: const Text('Analizuj plik')),
        if (widget.projectRender != null)
          OutlinedButton.icon(onPressed: () async {
            final p = await runBusy(context, 'Miksowanie projektu…', widget.projectRender!);
            if (p != null) await _analyze(p);
          }, icon: const Icon(Icons.graphic_eq), label: const Text('Analizuj miks projektu')),
      ]),
      if (an != null) ...[
        Section(title: 'Rytm i poziomy', children: [
          Wrap(spacing: 24, runSpacing: 8, children: [
            _stat('BPM', an.bpm.toStringAsFixed(1)),
            _stat('Pewność', '${(an.bpmConfidence * 100).round()}%'),
            _stat('Bity', '${an.beats.length}'),
            _stat('Transjenty', '${an.onsets.length}'),
            _stat('Głośność', '${loud?.integratedLufs.toStringAsFixed(1)} LUFS'),
            _stat('True peak', '${loud?.truePeakDb.toStringAsFixed(1)} dBTP'),
            _stat('LRA', '${loud?.lra.toStringAsFixed(1)} LU'),
            _stat('Szczyt', '${(20 * math.log(math.max(an.peak, 1e-9)) / math.ln10).toStringAsFixed(1)} dBFS'),
            _stat('RMS', '${an.rmsDb.toStringAsFixed(1)} dBFS'),
            _stat('Przesterowane próbki', '${an.clippedSamples}', warn: an.clippedSamples > 0),
            _stat('Zmiany dynamiki', an.sectionChanges.map((t) => fmtTime(t)).join(', ')),
          ]),
          Row(children: [
            const Text('Korekta BPM (wystukaj tempo):'),
            const SizedBox(width: 8),
            FilledButton.tonal(onPressed: () {
              final now = DateTime.now();
              if (taps.isNotEmpty && now.difference(taps.last).inSeconds > 2) taps.clear();
              taps.add(now);
              if (taps.length >= 4) {
                final d = (taps.last.difference(taps.first).inMilliseconds / (taps.length - 1)) / 1000;
                toast(context, 'Wystukane tempo: ${(60 / d).toStringAsFixed(1)} BPM');
              }
            }, child: const Text('TAP')),
          ]),
        ]),
        Section(title: 'Poziom audio w czasie (RMS) + bity', children: [SizedBox(height: 120, child: CustomPaint(painter: _EnvPainter(an), size: Size.infinite))]),
        Section(title: 'Analiza częstotliwości (średnie spektrum)', children: [SizedBox(height: 160, child: CustomPaint(painter: _SpecPainter(an.averageSpectrum), size: Size.infinite))]),
        Section(title: 'Spektrum w punkcie ${fmtTime(pos)}', children: [
          Slider(value: pos, max: an.duration, onChanged: (v) => setState(() => pos = v)),
          SizedBox(height: 160, child: CustomPaint(painter: _SpecPainter(AudioAnalyzer.spectrumAt(pcm!, pos)), size: Size.infinite)),
        ]),
      ],
    ]);
  }

  Widget _stat(String l, String v, {bool warn = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l, style: const TextStyle(color: WmsColors.muted, fontSize: 12)),
        Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: warn ? WmsColors.error : null)),
      ]);
}

class _EnvPainter extends CustomPainter {
  final AudioAnalysis a;
  _EnvPainter(this.a);
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF0C0E11));
    final n = a.rms.length;
    if (n == 0) return;
    final path = Path()..moveTo(0, s.height);
    for (var x = 0; x < s.width; x++) {
      final i = (x / s.width * n).floor().clamp(0, n - 1);
      path.lineTo(x.toDouble(), s.height - a.rms[i] * s.height * 0.95);
    }
    path.lineTo(s.width, s.height);
    c.drawPath(path, Paint()..color = WmsColors.accent.withValues(alpha: 0.6));
    final bp = Paint()..color = WmsColors.accent2.withValues(alpha: 0.4);
    for (final b in a.downbeats) {
      final x = b / a.duration * s.width;
      c.drawLine(Offset(x, 0), Offset(x, 8), bp);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => true;
}

class _SpecPainter extends CustomPainter {
  final Float32List db;
  _SpecPainter(this.db);
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF0C0E11));
    if (db.isEmpty) return;
    final w = s.width / db.length;
    for (var i = 0; i < db.length; i++) {
      final v = ((db[i] + 90) / 90).clamp(0.0, 1.0);
      c.drawRect(Rect.fromLTWH(i * w + 1, s.height * (1 - v), w - 2, s.height * v), Paint()..color = Color.lerp(WmsColors.accent, WmsColors.accent2, i / db.length)!);
    }
    final tp = TextPainter(text: const TextSpan(text: '30 Hz                                          ⟶                                   Nyquist', style: TextStyle(fontSize: 10, color: WmsColors.muted)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, const Offset(4, 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => true;
}
