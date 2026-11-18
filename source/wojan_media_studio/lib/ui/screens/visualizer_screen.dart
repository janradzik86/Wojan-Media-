import 'package:material_ui/material_ui.dart';

import '../../app/services.dart';
import '../../engine/audio/audio_project.dart';
import '../../engine/project/asset.dart';
import '../../engine/project/format.dart';
import '../../engine/video/color.dart';
import '../../engine/video/model.dart';
import '../../engine/video/visualizer.dart';
import '../shell.dart';
import '../widgets/common.dart';
import 'render_result.dart';
import 'video_widgets.dart';

class VisualizerScreen extends StatefulWidget {
  const VisualizerScreen({super.key});
  @override
  State<VisualizerScreen> createState() => _VisualizerScreenState();
}

class _VisualizerScreenState extends State<VisualizerScreen> {
  MediaAsset? music, background, logo;
  final vis = VisualizerItem(style: 'circle', x: 0.1, y: 0.25, width: 0.8, height: 0.45, logoSize: 0.4);
  bool bars = true, particles = true, pulse = true, bassGlow = false;
  int format = 0;
  final title = TextEditingController();

  Future<ProjectDoc> _build() async {
    final (w, h) = formatPresets.values.elementAt(format);
    final d = await Services.i.store.create('Wizualizator – ${music!.name}', ProjectType.visualizer);
    final v = VideoProject(width: w, height: h);
    d.assets[music!.id] = music!;
    v.audio.tracks.first.clips.add(AudioClip(assetId: music!.id, srcIn: 0, srcOut: music!.duration));
    v.musicAssetId = music!.id;
    v.fixedDuration = music!.duration;
    if (background != null) {
      d.assets[background!.id] = background!;
      v.clips.add(VisualClip(kind: background!.kind.name == 'video' ? ClipKind.video : ClipKind.image, assetId: background!.id, imageDuration: music!.duration, srcOut: background!.duration, loopVideo: true, fit: FitMode.cover, motion: Motion(preset: pulse ? MotionPreset.beatPulse : MotionPreset.kenBurnsIn, intensity: 0.4), grade: ColorGrade(brightness: -0.15)));
    } else {
      v.clips.add(VisualClip(kind: ClipKind.color, color: '#0B0D12', imageDuration: music!.duration));
    }
    if (logo != null) {
      d.assets[logo!.id] = logo!;
      vis.logoAssetId = logo!.id;
    }
    final vertical = h > w;
    vis
      ..y = vertical ? 0.25 : 0.12
      ..height = vertical ? 0.45 : 0.75;
    v.visualizers.add(vis);
    if (bars && vis.style != 'bars') v.visualizers.add(VisualizerItem(style: 'bars', x: 0, y: vertical ? 0.84 : 0.82, width: 1, height: 0.14, color: vis.color, color2: vis.color2, opacity: 0.85));
    if (particles) v.vfx.add(VfxItem(type: 'particles', reactive: true, color: vis.color));
    if (bassGlow) v.vfx.add(VfxItem(type: 'bassglow', reactive: true));
    if (title.text.isNotEmpty) v.texts.add(TextItem(text: title.text, start: 0, duration: music!.duration, anim: 'fade', style: TextStyleSpec(align: vertical ? 'top' : 'bottom', marginV: vertical ? 180 : 60, size: 64)));
    d.video = v;
    await Services.i.store.save(d);
    return d;
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
        Section(title: 'Materiały', children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: () async {
              final a = await importMedia(context, [...audioExt, ...videoExt], multiple: false);
              if (a.isNotEmpty) setState(() => music = a.first);
            }, icon: const Icon(Icons.library_music), label: Text(music?.name ?? 'Muzyka')),
            OutlinedButton.icon(onPressed: () async {
              final a = await importMedia(context, [...imageExt, ...videoExt], multiple: false);
              if (a.isNotEmpty) setState(() => background = a.first);
            }, icon: const Icon(Icons.wallpaper), label: Text(background?.name ?? 'Tło: zdjęcie lub film')),
            OutlinedButton.icon(onPressed: () async {
              final a = await importMedia(context, imageExt, multiple: false);
              if (a.isNotEmpty) setState(() => logo = a.first);
            }, icon: const Icon(Icons.verified), label: Text(logo?.name ?? 'Logo w centrum')),
          ]),
          const SizedBox(height: 8),
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Tekst / tytuł (opcjonalnie)')),
        ]),
        Section(title: 'Styl wizualizatora', children: [
          Wrap(spacing: 6, runSpacing: 6, children: [for (final e in visualizerNames.entries) ChoiceChip(label: Text(e.value), selected: vis.style == e.key, onSelected: (_) => setState(() => vis.style = e.key))]),
          const SizedBox(height: 8),
          const Text('Kolor główny'),
          ColorDots(value: vis.color, onChanged: (c) => setState(() => vis.color = c)),
          const Text('Kolor dodatkowy'),
          ColorDots(value: vis.color2, onChanged: (c) => setState(() => vis.color2 = c)),
          LabeledSlider(label: 'Intensywność', value: vis.intensity, min: 0.2, max: 4, decimals: 2, onChanged: (v) => setState(() => vis.intensity = v)),
          LabeledSlider(label: 'Krycie', value: vis.opacity, min: 0.2, max: 1, decimals: 2, onChanged: (v) => setState(() => vis.opacity = v)),
          SwitchListTile(value: vis.bassPulse, onChanged: (v) => setState(() => vis.bassPulse = v), title: const Text('Pulsowanie na basie (logo/koło)')),
          SwitchListTile(value: pulse, onChanged: (v) => setState(() => pulse = v), title: const Text('Tło pulsuje do rytmu')),
          SwitchListTile(value: bars, onChanged: (v) => setState(() => bars = v), title: const Text('Dodatkowe słupki u dołu')),
          SwitchListTile(value: particles, onChanged: (v) => setState(() => particles = v), title: const Text('Cząsteczki reagujące na muzykę')),
          SwitchListTile(value: bassGlow, onChanged: (v) => setState(() => bassGlow = v), title: const Text('Jasność reagująca na bas')),
          DropdownButton<int>(value: format, items: [for (var i = 0; i < formatPresets.length; i++) DropdownMenuItem(value: i, child: Text(formatPresets.keys.elementAt(i)))], onChanged: (v) => setState(() => format = v!)),
          const Text('Wszystkie animacje są obliczane z rzeczywistego sygnału audio (FFT w FFmpeg + lokalna analiza basu i bitów).', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
        Wrap(spacing: 8, children: [
          FilledButton.icon(onPressed: music == null ? null : () async {
            final d = await _build();
            if (!context.mounted) return;
            final s = await showVideoExportDialog(context, d.video!);
            if (s != null && context.mounted) await queueVideoRender(context, d, s);
          }, icon: const Icon(Icons.movie_creation), label: const Text('Renderuj')),
          OutlinedButton.icon(onPressed: music == null ? null : () async => Nav.openProject(await _build()), icon: const Icon(Icons.edit), label: const Text('Edytuj w Studiu Wideo')),
        ]),
      ]);
}
