import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../engine/ffmpeg/probe.dart';
import '../../engine/project/asset.dart';
import '../../engine/util/json_util.dart';

String tr(String k) => Services.i.t(k);

void toast(BuildContext ctx, String msg, {bool error = false}) {
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? WmsColors.error : null, duration: Duration(seconds: error ? 6 : 3)));
}

Future<bool> confirm(BuildContext ctx, String title, String body) async =>
    await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(title: Text(title), content: Text(body), actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('OK')),
      ]),
    ) ??
    false;

Future<String?> promptText(BuildContext ctx, String title, {String initial = '', int maxLines = 1, String hint = ''}) async {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: ctx,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: 480, child: TextField(controller: c, autofocus: true, maxLines: maxLines, decoration: InputDecoration(hintText: hint))),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('cancel'))), FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('OK'))],
    ),
  );
}

/// Picks files with the system picker (Android SAF / Windows dialog).
Future<List<String>> pickFiles({required List<String> extensions, bool multiple = true, String? dialogTitle}) async {
  final r = await FilePicker.platform.pickFiles(allowMultiple: multiple, type: FileType.custom, allowedExtensions: extensions, dialogTitle: dialogTitle);
  if (r == null) return [];
  return r.files.where((f) => f.path != null).map((f) => f.path!).toList();
}

const audioExt = ['mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg', 'opus', 'wma', 'aiff', 'amr', 'mka', 'ac3'];
const videoExt = ['mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v', '3gp', 'ts', 'mts', 'wmv', 'flv', 'mpg'];
const imageExt = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif', 'tif', 'tiff', 'avif'];
const subExt = ['srt', 'vtt', 'lrc', 'txt', 'ass'];

/// Imports picked files into the media store with a progress dialog.
Future<List<MediaAsset>> importMedia(BuildContext ctx, List<String> ext, {bool multiple = true}) async {
  final paths = await pickFiles(extensions: ext, multiple: multiple);
  if (paths.isEmpty || !ctx.mounted) return [];
  return importPaths(ctx, paths);
}

Future<List<MediaAsset>> importPaths(BuildContext ctx, List<String> paths) async {
  final out = <MediaAsset>[];
  final errors = <String>[];
  await runBusy(ctx, 'Importowanie ${paths.length} plików…', () async {
    for (final p in paths) {
      try {
        out.add(await Services.i.store.importMedia(p));
      } catch (e) {
        errors.add('${p.split(RegExp(r'[\\/]')).last}: $e');
      }
    }
  });
  if (errors.isNotEmpty && ctx.mounted) toast(ctx, 'Nie zaimportowano: ${errors.join('; ')}', error: true);
  return out;
}

/// Runs [f] while showing a modal progress indicator; reports errors.
Future<T?> runBusy<T>(BuildContext ctx, String label, Future<T> Function() f) async {
  showDialog<void>(
    context: ctx,
    barrierDismissible: false,
    builder: (_) => PopScope(canPop: false, child: AlertDialog(content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 20), Expanded(child: Text(label))]))),
  );
  try {
    return await f();
  } catch (e) {
    if (ctx.mounted) toast(ctx, '$e', error: true);
    return null;
  } finally {
    if (ctx.mounted) Navigator.of(ctx, rootNavigator: true).pop();
  }
}

class Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  const Section({super.key, required this.title, required this.children, this.trailing});
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)), ?trailing]),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );
}

class LabeledSlider extends StatelessWidget {
  final String label;
  final double value, min, max;
  final String unit;
  final int decimals;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  const LabeledSlider({super.key, required this.label, required this.value, required this.min, required this.max, required this.onChanged, this.unit = '', this.decimals = 1, this.onChangeEnd});
  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(width: 150, child: Text(label, overflow: TextOverflow.ellipsis)),
        Expanded(child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged, onChangeEnd: onChangeEnd)),
        SizedBox(width: 72, child: Text('${value.toStringAsFixed(decimals)} $unit', textAlign: TextAlign.right, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))),
      ]);
}

class ColorDots extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  static const palette = ['#FFFFFF', '#000000', '#35D0BA', '#FF4FA3', '#FFD400', '#FF7A1A', '#E10600', '#1DB954', '#2B7BFF', '#8A2BE2', '#C0C0C0', '#E8C170'];
  const ColorDots({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final c in palette)
          InkWell(
            onTap: () => onChanged(c),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: Color(int.parse('FF${c.substring(1)}', radix: 16)), shape: BoxShape.circle, border: Border.all(color: value.toUpperCase() == c ? WmsColors.accent : Colors.white24, width: value.toUpperCase() == c ? 3 : 1)),
            ),
          ),
      ]);
}

/// Small info table for media metadata.
class MediaInfoView extends StatelessWidget {
  final MediaInfo info;
  const MediaInfoView(this.info, {super.key});
  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Format', info.formatName ?? '-'),
      ('Czas', fmtTime(info.duration)),
      if (info.hasVideo) ('Obraz', '${info.displayWidth}×${info.displayHeight} @ ${info.fps?.toStringAsFixed(2)} fps (${info.videoCodec})'),
      if (info.hasAudio) ('Dźwięk', '${info.audioCodec}, ${info.sampleRate} Hz, ${info.channels} kan.'),
      if (info.bitrate != null) ('Bitrate', '${(info.bitrate! / 1000).round()} kb/s'),
      ('Rozmiar', fmtBytes(info.sizeBytes)),
      for (final t in info.tags.entries.take(8)) (t.key, t.value),
    ];
    return Table(columnWidths: const {0: IntrinsicColumnWidth()}, children: [
      for (final r in rows) TableRow(children: [Padding(padding: const EdgeInsets.only(right: 12, bottom: 4), child: Text(r.$1, style: const TextStyle(color: WmsColors.muted))), Text(r.$2)]),
    ]);
  }
}

bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Output path helper inside the exports folder.
String exportPath(String name, String ext) {
  final safe = name.replaceAll(RegExp(r'[^\p{L}\p{N}\-_ ]', unicode: true), '').trim().replaceAll(' ', '_');
  final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:\.]'), '-').substring(0, 19);
  return '${Services.i.exportsDir.path}/${safe.isEmpty ? 'wojan' : safe}_$stamp.$ext';
}
