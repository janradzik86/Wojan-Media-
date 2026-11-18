import 'package:material_ui/material_ui.dart';

import '../../app/services.dart';
import '../../engine/export/audio_formats.dart';
import '../../engine/export/video_export.dart';
import '../../engine/ffmpeg/escape.dart';
import '../../engine/ffmpeg/probe.dart';
import '../../engine/ffmpeg/runner.dart';
import '../../engine/util/json_util.dart';
import '../widgets/common.dart';
import 'audio_tools.dart';
import 'render_result.dart';

/// Media converter: video ↔ formats, compression, GIF, frame/thumbnail
/// export, images, audio (delegates to audio tools).
class ConverterScreen extends StatefulWidget {
  const ConverterScreen({super.key});
  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen> {
  String? input;
  MediaInfo? info;
  String target = 'mp4';
  int shortSide = 1080;
  double fps = 30;
  int crf = 23;
  int targetMB = 0;
  double frameAt = 0;
  double progress = 0;
  CancelToken? cancel;
  double? rs, re;

  Future<void> _pick() async {
    final f = await pickFiles(extensions: [...videoExt, ...imageExt, ...audioExt], multiple: false);
    if (f.isEmpty) return;
    final i = MediaInfo.fromProbe(f.first, await Services.i.runner.probeJson(f.first));
    setState(() {
      input = f.first;
      info = i;
      target = i.kind == MediaKind.image ? 'png' : i.kind == MediaKind.audio ? 'mp3' : 'mp4';
      shortSide = [i.displayWidth ?? 1080, i.displayHeight ?? 1080].reduce((a, b) => a < b ? a : b);
    });
  }

  Future<void> _run() async {
    final i = info!;
    final stem = input!.split(RegExp(r'[\\/]')).last.split('.').first;
    final out = exportPath('${stem}_conv', target);
    cancel = CancelToken();
    setState(() => progress = 0.001);
    try {
      final r = Services.i.runner;
      final w = i.displayWidth ?? 1920, h = i.displayHeight ?? 1080;
      final scaleExpr = w <= h ? 'scale=$shortSide:-2' : 'scale=-2:$shortSide';
      void prog(double t) => setState(() => progress = i.duration > 0 ? (t / i.duration).clamp(0.0, 1.0) : 0);
      final range = [if (rs != null) ...['-ss', fsec(rs!)], if (re != null) ...['-to', fsec(re!)]];
      if (['png', 'jpg', 'webp'].contains(target) && i.kind != MediaKind.image) {
        await r.run(['-ss', fsec(frameAt), '-i', input!, '-frames:v', '1', '-update', '1', if (target == 'jpg') ...['-q:v', '2'], out]);
      } else if (i.kind == MediaKind.image) {
        await r.run(['-i', input!, '-vf', scaleExpr, '-frames:v', '1', '-update', '1', if (target == 'jpg') ...['-q:v', '2'], if (target == 'webp') ...['-quality', '90'], out]);
      } else if (target == 'gif') {
        await r.run([...range, '-i', input!, '-filter_complex', 'fps=${FfEscape.num(fps.clamp(5, 30))},$scaleExpr:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer', '-loop', '0', out], onProgress: prog, cancel: cancel);
      } else if (AudioExportSettings.formatFromExtension(target) != null) {
        final s = AudioExportSettings(format: AudioExportSettings.formatFromExtension(target)!);
        await r.run([...range, '-i', input!, '-vn', ...s.codecArgs(), out], onProgress: prog, cancel: cancel);
      } else {
        final container = VideoContainer.values.firstWhere((c) => c.name == target);
        final s = VideoExportSettings(container: container, codec: container == VideoContainer.webm ? VideoCodec.vp9 : VideoCodec.h264, crf: crf, fps: fps, preset: 'medium');
        if (targetMB > 0 && i.duration > 0) {
          // compression to a target size: total kbps = MB*8192/s
          final total = (targetMB * 8192 / i.duration).floor();
          s.audioBitrateKbps = total > 600 ? 128 : 64;
          s.bitrateKbps = (total - s.audioBitrateKbps).clamp(150, 100000);
        }
        final enc = s.encoderCandidates(await Services.i.videoRenderer().availableEncoders()).last;
        await r.run([...range, '-i', input!, '-vf', '$scaleExpr,fps=${FfEscape.num(fps)},format=yuv420p', ...s.videoArgs(enc), ...s.audioArgs(), out], onProgress: prog, cancel: cancel, what: 'Konwersja nie powiodła się');
      }
      if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => RenderResultScreen(path: out)));
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => progress = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = info;
    final targets = i == null
        ? <String>[]
        : i.kind == MediaKind.image
            ? ['png', 'jpg', 'webp']
            : i.kind == MediaKind.audio
                ? AudioFormat.values.map((e) => AudioExportSettings(format: e).extension).toList()
                : ['mp4', 'webm', 'mov', 'mkv', 'gif', 'mp3', 'm4a', 'wav', 'flac', 'png', 'jpg', 'webp'];
    return ListView(padding: const EdgeInsets.all(12), children: [
      Section(title: 'Plik', trailing: FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.folder_open), label: Text(tr('import'))), children: [
        if (i == null) const Text('Wideo, audio lub obraz (w tym HEIC, jeśli obsługuje go silnik).'),
        if (i != null) MediaInfoView(i),
      ]),
      if (i != null)
        Section(title: 'Konwersja', children: [
          Wrap(spacing: 6, runSpacing: 6, children: [for (final t in targets) ChoiceChip(label: Text(t.toUpperCase()), selected: target == t, onSelected: (_) => setState(() => target = t))]),
          if (i.kind != MediaKind.audio && !['mp3', 'm4a', 'wav', 'flac', 'png', 'jpg', 'webp'].contains(target) || i.kind == MediaKind.image)
            Wrap(spacing: 6, children: [for (final e in resolutionPresets.entries) ChoiceChip(label: Text(e.key), selected: shortSide == e.value, onSelected: (_) => setState(() => shortSide = e.value))]),
          if (i.kind == MediaKind.video && ['mp4', 'webm', 'mov', 'mkv', 'gif'].contains(target)) ...[
            Wrap(spacing: 6, children: [for (final f in [15.0, 24.0, 25.0, 30.0, 50.0, 60.0]) ChoiceChip(label: Text('${f.round()} fps'), selected: fps == f, onSelected: (_) => setState(() => fps = f))]),
            if (target != 'gif') LabeledSlider(label: 'Jakość (CRF)', value: crf.toDouble(), min: 16, max: 36, decimals: 0, onChanged: (v) => setState(() => crf = v.round())),
            if (target != 'gif') LabeledSlider(label: 'Kompresja do rozmiaru (0 = wył.)', value: targetMB.toDouble(), min: 0, max: 500, unit: 'MB', decimals: 0, onChanged: (v) => setState(() => targetMB = v.round())),
            RangeSlider(values: RangeValues(rs ?? 0, re ?? i.duration), max: i.duration, onChanged: (v) => setState(() => {rs = v.start > 0 ? v.start : null, re = v.end < i.duration ? v.end : null}), labels: RangeLabels(fmtTime(rs ?? 0), fmtTime(re ?? i.duration))),
            const Text('Zakres eksportu (fragment)', style: TextStyle(fontSize: 12)),
          ],
          if (i.kind == MediaKind.video && ['png', 'jpg', 'webp'].contains(target)) LabeledSlider(label: 'Klatka w czasie', value: frameAt, min: 0, max: i.duration, unit: 's', decimals: 2, onChanged: (v) => setState(() => frameAt = v)),
          if (progress > 0) Row(children: [Expanded(child: LinearProgressIndicator(value: progress < 0.01 ? null : progress)), IconButton(onPressed: () => cancel?.cancel(), icon: const Icon(Icons.cancel))]),
          FilledButton.icon(onPressed: progress > 0 ? null : _run, icon: const Icon(Icons.swap_horiz), label: const Text('Konwertuj')),
        ]),
      Section(title: 'Narzędzia audio', children: [
        Wrap(spacing: 8, children: [
          OutlinedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AudioToolScreen(tool: 'batch', title: 'Konwersja wsadowa audio'))), child: const Text('Konwersja wsadowa audio')),
          OutlinedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AudioToolScreen(tool: 'extract', title: 'Wideo → audio'))), child: const Text('Ekstrakcja audio z wideo')),
        ]),
      ]),
    ]);
  }
}
