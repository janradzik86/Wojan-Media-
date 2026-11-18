import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../engine/export/video_export.dart';
import '../../engine/util/json_util.dart';
import '../../engine/video/model.dart';
import '../widgets/common.dart';

/// Aspect / format presets for new and existing projects.
const formatPresets = <String, (int, int)>{
  '9:16 (TikTok, Shorts, Reels)': (1080, 1920),
  '16:9 (YouTube, Facebook)': (1920, 1080),
  '1:1 (Instagram)': (1080, 1080),
  '4:5 (feed)': (1080, 1350),
  '4:3': (1440, 1080),
  '21:9 (kinowy)': (2560, 1080),
};

const fontFamilies = ['Noto Sans', 'Anton', 'Bebas Neue', 'Oswald', 'Playfair Display', 'Lobster', 'Pacifico', 'Caveat', 'Monoton', 'Press Start 2P', 'Rubik Glitch', 'Nosifer'];

/// Thumbnail for a visual clip (cached JPG from FFmpeg).
class ClipThumb extends StatefulWidget {
  final String? path;
  final double at;
  final double size;
  const ClipThumb({super.key, this.path, this.at = 0, this.size = 72});
  @override
  State<ClipThumb> createState() => _ClipThumbState();
}

class _ClipThumbState extends State<ClipThumb> {
  static final _cache = <String, String>{};
  String? thumb;
  @override
  void initState() {
    super.initState();
    _make();
  }

  @override
  void didUpdateWidget(covariant ClipThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _make();
  }

  Future<void> _make() async {
    final p = widget.path;
    if (p == null) return;
    final key = '$p@${widget.at.toStringAsFixed(1)}';
    if (_cache[key] != null) {
      setState(() => thumb = _cache[key]);
      return;
    }
    final out = '${Services.i.store.cacheDir.path}/thumbs/${key.hashCode}.jpg';
    if (!File(out).existsSync()) {
      await Directory('${Services.i.store.cacheDir.path}/thumbs').create(recursive: true);
      await Services.i.runner.ffmpeg([if (widget.at > 0) ...['-ss', widget.at.toStringAsFixed(2)], '-i', p, '-vf', 'scale=160:-2', '-frames:v', '1', '-update', '1', out]);
    }
    if (File(out).existsSync() && mounted) setState(() => thumb = _cache[key] = out);
  }

  @override
  Widget build(BuildContext context) => thumb == null
      ? Container(color: WmsColors.panel2, width: widget.size, height: widget.size, child: const Icon(Icons.image, color: WmsColors.muted))
      : Image.file(File(thumb!), width: widget.size, height: widget.size, fit: BoxFit.cover);
}

/// Safe-zone overlay (areas usually covered by platform UI).
class SafeZonePainter extends CustomPainter {
  final bool vertical;
  SafeZonePainter(this.vertical);
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = WmsColors.warn.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final b = Paint()
      ..color = WmsColors.warn
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    if (vertical) {
      c.drawRect(Rect.fromLTWH(0, 0, s.width, s.height * 0.12), p); // top bar
      c.drawRect(Rect.fromLTWH(0, s.height * 0.78, s.width, s.height * 0.22), p); // caption & buttons
      c.drawRect(Rect.fromLTWH(s.width * 0.84, s.height * 0.35, s.width * 0.16, s.height * 0.43), p); // right action rail
    } else {
      c.drawRect(Rect.fromLTWH(0, s.height * 0.85, s.width, s.height * 0.15), p);
    }
    c.drawRect(Rect.fromLTWH(s.width * 0.05, s.height * 0.05, s.width * 0.9, s.height * 0.9), b);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Export dialog with codec, bitrate, quality, resolution, FPS, range,
/// size estimate and saved presets.
Future<VideoExportSettings?> showVideoExportDialog(BuildContext context, VideoProject p, {VideoExportSettings? initial}) async {
  final s = initial?.copy() ?? VideoExportSettings(width: p.width, height: p.height, fps: p.fps);
  var useRange = false;
  double rs = 0, re = p.duration;
  return showDialog<VideoExportSettings>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final shortSide = s.width < s.height ? s.width : s.height;
      void res(int short) {
        final aspect = p.width / p.height;
        if (aspect < 1) {
          s.width = short;
          s.height = (short / aspect / 2).round() * 2;
        } else {
          s.height = short;
          s.width = (short * aspect / 2).round() * 2;
        }
      }

      final presets = Services.i.kv.keys('exportPresets');
      return AlertDialog(
        title: const Text('Eksport wideo'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (presets.isNotEmpty)
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Własne presety eksportu'),
                  items: [for (final k in presets) DropdownMenuItem(value: k, child: Text(k))],
                  onChanged: (k) => set(() {
                    final j = Services.i.kv.get('exportPresets', k!)!;
                    final n = VideoExportSettings.fromJson(j);
                    s
                      ..container = n.container
                      ..codec = n.codec
                      ..crf = n.crf
                      ..bitrateKbps = n.bitrateKbps
                      ..fps = n.fps
                      ..preset = n.preset;
                    res(jd(j['short'], shortSide.toDouble()).round());
                  }),
                ),
              DropdownButtonFormField<VideoContainer>(value: s.container, decoration: const InputDecoration(labelText: 'Format'), items: const [
                DropdownMenuItem(value: VideoContainer.mp4, child: Text('MP4')),
                DropdownMenuItem(value: VideoContainer.webm, child: Text('WEBM (VP9 + Opus)')),
                DropdownMenuItem(value: VideoContainer.mov, child: Text('MOV')),
                DropdownMenuItem(value: VideoContainer.mkv, child: Text('MKV')),
                DropdownMenuItem(value: VideoContainer.gif, child: Text('GIF (animacja)')),
              ], onChanged: (v) => set(() {
                s.container = v!;
                if (v == VideoContainer.webm) s.codec = VideoCodec.vp9;
                if (v != VideoContainer.webm && s.codec == VideoCodec.vp9) s.codec = VideoCodec.h264;
              })),
              if (s.container != VideoContainer.gif) ...[
                DropdownButtonFormField<VideoCodec>(value: s.codec, decoration: const InputDecoration(labelText: 'Kodek'), items: [
                  if (s.container != VideoContainer.webm) const DropdownMenuItem(value: VideoCodec.h264, child: Text('H.264 (najszersza zgodność)')),
                  if (s.container != VideoContainer.webm) const DropdownMenuItem(value: VideoCodec.h265, child: Text('H.265 / HEVC (mniejsze pliki)')),
                  if (s.container == VideoContainer.webm || s.container == VideoContainer.mkv) const DropdownMenuItem(value: VideoCodec.vp9, child: Text('VP9')),
                  if (s.container == VideoContainer.mov) const DropdownMenuItem(value: VideoCodec.prores, child: Text('ProRes 422 (montaż)')),
                ], onChanged: (v) => set(() => s.codec = v!)),
                DropdownButtonFormField<String>(value: Services.i.settings.get<String>('encoder'), decoration: const InputDecoration(labelText: 'Enkoder'), items: const [
                  DropdownMenuItem(value: 'auto', child: Text('Automatyczny (sprzętowy, z rezerwą programową)')),
                  DropdownMenuItem(value: 'hardware', child: Text('Tylko sprzętowy (GPU / MediaCodec)')),
                  DropdownMenuItem(value: 'software', child: Text('Programowy (najwyższa jakość)')),
                ], onChanged: (v) => Services.i.settings.set('encoder', v)),
              ],
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                for (final e in resolutionPresets.entries) ChoiceChip(label: Text(e.key), selected: shortSide == e.value, onSelected: (_) => set(() => res(e.value))),
              ]),
              Text('Rozdzielczość: ${s.width} × ${s.height}', style: const TextStyle(color: WmsColors.muted)),
              Wrap(spacing: 6, children: [for (final f in [24.0, 25.0, 30.0, 50.0, 60.0]) ChoiceChip(label: Text('${f.round()} FPS'), selected: s.fps == f, onSelected: (_) => set(() => s.fps = f))]),
              if (s.container == VideoContainer.gif) ...[
                LabeledSlider(label: 'Szerokość GIF', value: s.gifWidth.toDouble(), min: 160, max: 1080, unit: 'px', decimals: 0, onChanged: (v) => set(() => s.gifWidth = v.round())),
                LabeledSlider(label: 'FPS GIF', value: s.gifFps, min: 5, max: 30, decimals: 0, onChanged: (v) => set(() => s.gifFps = v)),
              ] else ...[
                SwitchListTile(contentPadding: EdgeInsets.zero, value: s.bitrateKbps > 0, title: const Text('Stały bitrate (zamiast stałej jakości)'), onChanged: (v) => set(() => s.bitrateKbps = v ? s.effectiveVideoKbps : 0)),
                if (s.bitrateKbps > 0) LabeledSlider(label: 'Bitrate wideo', value: s.bitrateKbps.toDouble(), min: 500, max: 60000, unit: 'kb/s', decimals: 0, onChanged: (v) => set(() => s.bitrateKbps = v.round())),
                if (s.bitrateKbps == 0) LabeledSlider(label: 'Jakość (CRF, mniej = lepiej)', value: s.crf.toDouble(), min: 14, max: 36, decimals: 0, onChanged: (v) => set(() => s.crf = v.round())),
                DropdownButtonFormField<String>(value: s.preset, decoration: const InputDecoration(labelText: 'Szybkość kompresji'), items: const [
                  DropdownMenuItem(value: 'ultrafast', child: Text('Najszybciej')),
                  DropdownMenuItem(value: 'veryfast', child: Text('Szybko')),
                  DropdownMenuItem(value: 'medium', child: Text('Zrównoważona')),
                  DropdownMenuItem(value: 'slow', child: Text('Najmniejszy plik')),
                ], onChanged: (v) => set(() => s.preset = v!)),
                DropdownButtonFormField<int>(value: s.audioBitrateKbps, decoration: const InputDecoration(labelText: 'Bitrate audio'), items: [for (final b in [96, 128, 160, 192, 256, 320]) DropdownMenuItem(value: b, child: Text('$b kb/s'))], onChanged: (v) => set(() => s.audioBitrateKbps = v!)),
                DropdownButtonFormField<int>(value: s.audioSampleRate, decoration: const InputDecoration(labelText: 'Próbkowanie audio'), items: const [DropdownMenuItem(value: 44100, child: Text('44,1 kHz')), DropdownMenuItem(value: 48000, child: Text('48 kHz'))], onChanged: (v) => set(() => s.audioSampleRate = v!)),
              ],
              CheckboxListTile(contentPadding: EdgeInsets.zero, value: useRange, title: const Text('Eksportuj tylko fragment'), onChanged: (v) => set(() => useRange = v!)),
              if (useRange) RangeSlider(values: RangeValues(rs, re), max: p.duration, onChanged: (v) => set(() => {rs = v.start, re = v.end}), labels: RangeLabels(fmtTime(rs), fmtTime(re))),
              const SizedBox(height: 8),
              Text('Szacowany rozmiar: ${fmtBytes(s.estimateBytes(useRange ? re - rs : p.duration))} • czas ${fmtTime(useRange ? re - rs : p.duration)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              if (shortSide >= 2160) const Text('4K wymaga wydajnego urządzenia; telefon może renderować wolno lub przekroczyć możliwości enkodera sprzętowego (automatyczny fallback).', style: TextStyle(color: WmsColors.warn, fontSize: 12)),
              const Text('Bez znaku wodnego. Bez limitu długości.', style: TextStyle(color: WmsColors.muted, fontSize: 12)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () async {
            final n = await promptText(c, 'Nazwa presetu eksportu');
            if (n != null && n.isNotEmpty) Services.i.kv.put('exportPresets', n, {...s.toJson(), 'short': shortSide});
            set(() {});
          }, child: const Text('Zapisz preset')),
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('cancel'))),
          FilledButton(onPressed: () {
            s.rangeStart = useRange ? rs : null;
            s.rangeEnd = useRange ? re : null;
            Navigator.pop(c, s);
          }, child: Text(tr('render'))),
        ],
      );
    }),
  );
}

/// Text style editor reused by titles, lyrics and karaoke.
class TextStyleEditor extends StatelessWidget {
  final TextStyleSpec s;
  final VoidCallback onChanged;
  const TextStyleEditor({super.key, required this.s, required this.onChanged});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownButtonFormField<String>(value: fontFamilies.contains(s.font) ? s.font : fontFamilies.first, decoration: const InputDecoration(labelText: 'Czcionka'), items: [for (final f in [...fontFamilies, ...userFonts()]) DropdownMenuItem(value: f, child: Text(f))], onChanged: (v) => {s.font = v!, onChanged()}),
        LabeledSlider(label: 'Rozmiar', value: s.size, min: 16, max: 200, decimals: 0, onChanged: (v) => {s.size = v, onChanged()}),
        const Text('Kolor'),
        ColorDots(value: s.color, onChanged: (v) => {s.color = v, onChanged()}),
        const SizedBox(height: 6),
        const Text('Kolor podświetlenia (karaoke)'),
        ColorDots(value: s.highlightColor, onChanged: (v) => {s.highlightColor = v, onChanged()}),
        const SizedBox(height: 6),
        const Text('Kontur'),
        ColorDots(value: s.outlineColor, onChanged: (v) => {s.outlineColor = v, onChanged()}),
        LabeledSlider(label: 'Grubość konturu', value: s.outline, min: 0, max: 12, onChanged: (v) => {s.outline = v, onChanged()}),
        LabeledSlider(label: 'Cień', value: s.shadow, min: 0, max: 12, onChanged: (v) => {s.shadow = v, onChanged()}),
        LabeledSlider(label: 'Przezroczystość', value: s.opacity, min: 0.1, max: 1, decimals: 2, onChanged: (v) => {s.opacity = v, onChanged()}),
        LabeledSlider(label: 'Odstęp liter', value: s.letterSpacing, min: -5, max: 30, onChanged: (v) => {s.letterSpacing = v, onChanged()}),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: s.gradientTo != null, title: const Text('Gradient (pionowy)'), onChanged: (v) => {s.gradientTo = v ? '#FF4FA3' : null, onChanged()}),
        if (s.gradientTo != null) ColorDots(value: s.gradientTo!, onChanged: (v) => {s.gradientTo = v, onChanged()}),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: s.box, title: const Text('Tło pod tekstem'), onChanged: (v) => {s.box = v, onChanged()}),
        Row(children: [
          const Text('Pozycja: '),
          SegmentedButton<String>(segments: const [ButtonSegment(value: 'top', label: Text('Góra')), ButtonSegment(value: 'center', label: Text('Środek')), ButtonSegment(value: 'bottom', label: Text('Dół'))], selected: {s.align}, onSelectionChanged: (v) => {s.align = v.first, onChanged()}),
        ]),
        LabeledSlider(label: 'Margines pionowy', value: s.marginV, min: 0, max: 800, decimals: 0, onChanged: (v) => {s.marginV = v, onChanged()}),
        Row(children: [SwitchListTile(value: s.bold, onChanged: (v) => {s.bold = v, onChanged()}, title: const Text('Pogrubienie')).expand(), SwitchListTile(value: s.italic, onChanged: (v) => {s.italic = v, onChanged()}, title: const Text('Kursywa')).expand()]),
      ]);
}

extension on Widget {
  Widget expand() => Expanded(child: this);
}

/// User fonts imported into the fonts directory (family names).
List<String> userFonts() => Services.i.kv.values('fonts').map((e) => '${e['family']}').toList();
