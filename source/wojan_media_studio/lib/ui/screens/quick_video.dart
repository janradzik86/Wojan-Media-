import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../engine/dsp/analysis.dart';
import '../../engine/export/video_export.dart';
import '../../engine/musicvideo/auto.dart';
import '../../engine/musicvideo/styles.dart';
import '../../engine/project/asset.dart';
import '../../engine/project/format.dart';
import '../../engine/publish/platforms.dart';
import '../../engine/util/json_util.dart';
import '../../engine/video/model.dart';
import '../shell.dart';
import '../widgets/common.dart';
import '../preview/live_preview.dart';
import '../preview/preview_controller.dart';
import 'render_result.dart';
import 'video_widgets.dart';

/// One-click music video wizard (requirement §7).
class QuickVideoScreen extends StatefulWidget {
  final MusicVideoMode? initialMode;
  const QuickVideoScreen({super.key, this.initialMode});
  @override
  State<QuickVideoScreen> createState() => _QuickVideoScreenState();
}

class _QuickVideoScreenState extends State<QuickVideoScreen> {
  int step = 0;
  MediaAsset? music;
  final visuals = <MediaAsset>[];
  final extraTracks = <MediaAsset>[];
  MediaAsset? logo;
  final lyrics = TextEditingController();
  final title = TextEditingController();
  final artist = TextEditingController();
  late StyleTemplate style = factoryStyles.first;
  late MusicVideoMode mode = widget.initialMode ?? MusicVideoMode.dynamic;
  String platform = 'tiktok';
  double promoLen = 30;
  AudioAnalysis? analysis;
  ProjectDoc? doc;
  String? preview;
  bool busy = false;
  PreviewController? pc;

  List<StyleTemplate> get styles => [...factoryStyles, ...Services.i.userStyles()];

  Future<void> _pickMusic() async {
    final a = await importMedia(context, [...audioExt, ...videoExt], multiple: false);
    if (a.isEmpty) return;
    setState(() {
      music = a.first;
      analysis = null;
      if (title.text.isEmpty) title.text = a.first.name.contains('.') ? a.first.name.substring(0, a.first.name.lastIndexOf('.')) : a.first.name;
    });
    final an = await runBusy(context, 'Analiza rytmu i struktury utworu…', () => Services.i.analyze(Services.i.store.mediaPath(a.first.relPath), a.first.sha256));
    if (an != null) setState(() => analysis = an);
  }

  Future<void> _generate() async {
    if (music == null || analysis == null) return;
    final prof = Services.i.profiles[platform]!;
    final req = MusicVideoRequest(
      music: music!,
      visuals: visuals,
      extraTracks: extraTracks,
      lyrics: lyrics.text.trim().isEmpty ? null : lyrics.text,
      title: title.text,
      artist: artist.text,
      style: style,
      mode: mode,
      width: prof.width,
      height: prof.height,
      fps: prof.fps,
      logo: logo,
      promoLength: promoLen,
    );
    final v = MusicVideoGenerator(seed: DateTime.now().millisecond).generate(req, analysis!);
    final d = doc ?? await Services.i.store.create(title.text.isEmpty ? 'Teledysk' : title.text, ProjectType.musicVideo);
    d.video = v;
    d.name = title.text.isEmpty ? d.name : title.text;
    d.assets
      ..clear()
      ..[music!.id] = music!;
    for (final a in [...visuals, ...extraTracks, ?logo]) {
      d.assets[a.id] = a;
    }
    d.extra['style'] = style.id;
    d.extra['mode'] = mode.name;
    d.publish.title = [artist.text, title.text].where((e) => e.isNotEmpty).join(' – ');
    d.publish.hashtags = ['#${style.name.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '').toLowerCase()}', '#muzyka', '#teledysk'];
    d.exportSettings['video'] = prof.exportSettings().toJson();
    await Services.i.store.save(d);
    await Services.i.store.makeThumbnail(d).catchError((_) {});
    setState(() => doc = d);
    await _preview();
  }

  /// Real-time preview (FotoPlay-style): no waiting for a render – the
  /// generated project plays immediately with its music.
  Future<void> _preview() async {
    final d = doc!;
    final v = d.video!;
    final mc = v.audio.tracks.first.clips.firstOrNull;
    final old = pc;
    pc = PreviewController(project: v, assets: Services.i.store.resolver(d), music: analysis, musicOffset: mc == null ? 0 : mc.position - mc.srcIn);
    setState(() => preview = d.id);
    old?.dispose();
    await pc!.seek(0);
    await pc!.play();
  }

  @override
  void dispose() {
    pc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = <Step>[
      Step(
        title: const Text('Muzyka'),
        isActive: step >= 0,
        state: music != null ? StepState.complete : StepState.indexed,
        content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FilledButton.icon(onPressed: _pickMusic, icon: const Icon(Icons.library_music), label: Text(music == null ? 'Wybierz plik muzyczny' : music!.name)),
          if (analysis != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Długość ${fmtTime(analysis!.duration)} • ${analysis!.bpm.toStringAsFixed(1)} BPM • ${analysis!.beats.length} bitów • ${analysis!.sectionChanges.length} zmian dynamiki', style: const TextStyle(color: WmsColors.accent))),
          const SizedBox(height: 8),
          TextField(controller: artist, decoration: const InputDecoration(labelText: 'Wykonawca (opcjonalnie)')),
          const SizedBox(height: 6),
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Tytuł utworu')),
        ]),
      ),
      Step(
        title: Text('Zdjęcia i klipy (${visuals.length})'),
        isActive: step >= 1,
        content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, children: [
            FilledButton.icon(onPressed: () async {
              final a = await importMedia(context, [...imageExt, ...videoExt]);
              setState(() => visuals.addAll(a));
            }, icon: const Icon(Icons.add_photo_alternate), label: const Text('Dodaj zdjęcia / klipy')),
            OutlinedButton.icon(onPressed: () async {
              final a = await importMedia(context, imageExt, multiple: false);
              if (a.isNotEmpty) setState(() => logo = a.first);
            }, icon: const Icon(Icons.verified), label: Text(logo == null ? 'Logo (opcjonalnie)' : 'Logo: ${logo!.name}')),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 90,
            child: ReorderableListView(
              scrollDirection: Axis.horizontal,
              onReorder: (a, b) => setState(() {
                final x = visuals.removeAt(a);
                visuals.insert(b > a ? b - 1 : b, x);
              }),
              children: [
                for (final v in visuals)
                  Padding(
                    key: ValueKey(v.id + visuals.indexOf(v).toString()),
                    padding: const EdgeInsets.only(right: 4),
                    child: Stack(children: [
                      ClipThumb(path: Services.i.store.mediaPath(v.relPath), size: 86),
                      Positioned(right: 0, top: 0, child: InkWell(onTap: () => setState(() => visuals.remove(v)), child: const Icon(Icons.cancel, size: 18))),
                    ]),
                  ),
              ],
            ),
          ),
          if (visuals.isEmpty) const Text('Bez zdjęć powstanie teledysk na kolorowym tle z wizualizatorem/tekstem.', style: TextStyle(color: WmsColors.muted)),
        ]),
      ),
      Step(
        title: const Text('Tekst piosenki (opcjonalnie)'),
        isActive: step >= 2,
        content: Column(children: [
          TextField(controller: lyrics, maxLines: 8, minLines: 3, decoration: const InputDecoration(hintText: 'Wklej tekst piosenki lub plik LRC/SRT. Bez znaczników czasu wersy zostaną rozłożone automatycznie na takty (przybliżenie – popraw w module Lyric Video).')),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () async {
            final f = await pickFiles(extensions: subExt, multiple: false);
            if (f.isNotEmpty) lyrics.text = await File(f.first).readAsString();
          }, icon: const Icon(Icons.file_open), label: const Text('Wczytaj LRC / SRT / VTT / TXT'))),
        ]),
      ),
      Step(
        title: Text('Styl: ${style.name}'),
        isActive: step >= 3,
        content: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in styles)
            ChoiceChip(
              avatar: CircleAvatar(backgroundColor: Color(int.parse('FF${s.accentColor.substring(1)}', radix: 16)), radius: 8),
              label: Text(s.name),
              selected: style.id == s.id,
              onSelected: (_) => setState(() => style = s),
            ),
        ]),
      ),
      Step(
        title: Text('Tryb: ${musicVideoModeNames[mode]}'),
        isActive: step >= 4,
        content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [for (final m in MusicVideoMode.values) ChoiceChip(label: Text(musicVideoModeNames[m]!), selected: mode == m, onSelected: (_) => setState(() => mode = m))]),
          if (mode == MusicVideoMode.promo || mode == MusicVideoMode.trailer) LabeledSlider(label: 'Długość klipu', value: promoLen, min: 5, max: 90, unit: 's', decimals: 0, onChanged: (v) => setState(() => promoLen = v)),
          if (mode == MusicVideoMode.album)
            OutlinedButton.icon(onPressed: () async {
              final a = await importMedia(context, audioExt);
              setState(() => extraTracks.addAll(a));
            }, icon: const Icon(Icons.queue_music), label: Text('Kolejne utwory albumu (${extraTracks.length})')),
        ]),
      ),
      Step(
        title: const Text('Format publikacji'),
        isActive: step >= 5,
        content: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in Services.i.profiles.all.where((p) => p.maxDescription > 0 || p.id.contains('youtube') || p.id.contains('4x5')))
            ChoiceChip(label: Text('${p.name} ${p.aspectW}:${p.aspectH}'), selected: platform == p.id, onSelected: (_) => setState(() => platform = p.id)),
        ]),
      ),
    ];
    return ListView(padding: const EdgeInsets.all(8), children: [
      Stepper(
        physics: const NeverScrollableScrollPhysics(),
        currentStep: step,
        onStepTapped: (i) => setState(() => step = i),
        onStepContinue: () => setState(() => step = (step + 1).clamp(0, steps.length - 1)),
        onStepCancel: () => setState(() => step = (step - 1).clamp(0, steps.length - 1)),
        steps: steps,
        controlsBuilder: (c, d) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            if (step < steps.length - 1) FilledButton.tonal(onPressed: d.onStepContinue, child: const Text('Dalej')),
            const SizedBox(width: 8),
            if (step > 0) TextButton(onPressed: d.onStepCancel, child: const Text('Wstecz')),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: music == null || analysis == null || busy ? null : _generate, icon: const Icon(Icons.auto_awesome), label: Text(doc == null ? 'Generuj teledysk' : 'Generuj ponownie')),
          if (doc != null) ...[
            OutlinedButton.icon(onPressed: () => Nav.openProject(doc!), icon: const Icon(Icons.edit), label: const Text('Popraw w Studiu Wideo')),
            OutlinedButton.icon(onPressed: busy ? null : () async {
              final v = doc!.video!;
              v.fitToAudio(fit: FitMode.blurBackground, target: v.audioDuration);
              await Services.i.store.save(doc!);
              if (context.mounted) toast(context, 'Dopasowano do długości audio: ${fmtTime(v.duration)}');
              await _preview();
            }, icon: const Icon(Icons.straighten), label: const Text('Dostosuj do długości audio')),
            FilledButton.icon(onPressed: busy ? null : () async {
              final s = await showVideoExportDialog(context, doc!.video!, initial: VideoExportSettings.fromJson(jm(doc!.exportSettings['video'])));
              if (s != null && context.mounted) await queueVideoRender(context, doc!, s);
            }, icon: const Icon(Icons.movie_creation), label: const Text('Zatwierdź i renderuj')),
          ],
        ]),
      ),
      if (preview != null && doc != null)
        if (pc != null) Center(child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 600, maxWidth: 900), child: LivePreview(key: ValueKey(pc), controller: pc!))),
      if (doc != null) Padding(padding: const EdgeInsets.all(12), child: Text('${doc!.video!.clips.length} ujęć zsynchronizowanych z bitem • ${doc!.video!.vfx.length} efektów • ${doc!.video!.lyrics?.lines.length ?? 0} wersów', style: const TextStyle(color: WmsColors.muted))),
    ]);
  }
}

/// Exposed for other modules (e.g. platform checks).
PlatformProfile? profileFor(String id) => Services.i.profiles[id];
