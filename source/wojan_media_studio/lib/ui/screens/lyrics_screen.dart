import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../engine/audio/audio_project.dart';
import '../../engine/audio/effects.dart';
import '../../engine/dsp/analysis.dart';
import '../../engine/ffmpeg/probe.dart';
import '../../engine/lyrics/lyrics.dart';
import '../../engine/musicvideo/auto.dart';
import '../../engine/project/asset.dart';
import '../../engine/project/format.dart';
import '../../engine/util/json_util.dart';
import '../../engine/video/color.dart';
import '../../engine/video/model.dart';
import '../shell.dart';
import '../widgets/common.dart';
import 'render_result.dart';
import 'video_widgets.dart';

class LyricsScreen extends StatefulWidget {
  final bool karaoke;
  const LyricsScreen({super.key, required this.karaoke});
  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  MediaAsset? music;
  AudioAnalysis? analysis;
  final visuals = <MediaAsset>[];
  LyricsTrack track = LyricsTrack();
  final player = Player();
  double pos = 0;
  StreamSubscription<Duration>? sub;
  bool tapMode = false;
  bool wordMode = false;
  int tapIndex = 0;
  int wordIndex = 0;
  late TextStyleSpec style = TextStyleSpec(size: widget.karaoke ? 60 : 72, align: widget.karaoke ? 'bottom' : 'center', highlightColor: '#FFD400');
  String anim = 'wordPop';
  LyricsMode mode = LyricsMode.lyric;
  bool removeVocals = false;
  int format = 0; // index into formatPresets
  final sel = <int>{};

  @override
  void initState() {
    super.initState();
    mode = widget.karaoke ? LyricsMode.karaoke : LyricsMode.lyric;
    removeVocals = widget.karaoke;
    sub = player.stream.position.listen((d) => setState(() => pos = d.inMilliseconds / 1000));
  }

  @override
  void dispose() {
    sub?.cancel();
    player.dispose();
    super.dispose();
  }

  Future<void> _pickMusic() async {
    final a = await importMedia(context, [...audioExt, ...videoExt], multiple: false);
    if (a.isEmpty) return;
    setState(() => music = a.first);
    await player.open(Media(Services.i.store.mediaPath(a.first.relPath)), play: false);
    final an = await runBusy(context, 'Analiza rytmu…', () => Services.i.analyze(Services.i.store.mediaPath(a.first.relPath), a.first.sha256));
    if (an != null) setState(() => analysis = an);
  }

  Future<void> _paste() async {
    final t = await promptText(context, 'Wklej pełny tekst piosenki', maxLines: 14, hint: 'Każdy wers w osobnej linii. Puste linie oddzielają zwrotki.');
    if (t == null) return;
    setState(() {
      track = LyricsTrack.parse(t)..mode = mode;
      tapIndex = 0;
    });
  }

  Future<void> _import() async {
    final f = await pickFiles(extensions: subExt, multiple: false);
    if (f.isEmpty) return;
    final t = LyricsTrack.parse(await File(f.first).readAsString(), ext: extOf(f.first));
    setState(() => track = t..mode = mode);
  }

  Future<void> _export(String fmt) async {
    final content = switch (fmt) { 'srt' => track.toSrt(), 'vtt' => track.toVtt(), 'lrc' => track.toLrc(enhanced: widget.karaoke), _ => track.toLrc() };
    final path = exportPath(music?.name ?? 'tekst', fmt);
    await File(path).writeAsString(content);
    if (!mounted) return;
    if (Platform.isAndroid) {
      await SharePlus.instance.share(ShareParams(files: [XFile(path, mimeType: 'text/plain')]));
    } else {
      toast(context, 'Zapisano: $path');
    }
  }

  void _tap() {
    if (!tapMode) return;
    if (wordMode) {
      // word-level karaoke sync: tap each word start
      if (tapIndex >= track.lines.length) return;
      final line = track.lines[tapIndex];
      final words = line.text.split(RegExp(r'\s+'));
      if (wordIndex == 0) {
        line.start = pos;
        line.words = [];
      }
      if (line.words.isNotEmpty) line.words.last.end = pos;
      line.words.add(LyricWord(pos, pos + 0.4, words[wordIndex]));
      wordIndex++;
      if (wordIndex >= words.length) {
        wordIndex = 0;
        tapIndex++;
      }
    } else {
      track.tap(tapIndex, pos);
      tapIndex++;
    }
    setState(() {});
    if (tapIndex >= track.lines.length) {
      final last = track.lines.last;
      if (last.end < 0) last.end = pos + 3;
      track.finalizeTiming(songDuration: analysis?.duration ?? 0);
      setState(() => tapMode = false);
      toast(context, 'Synchronizacja zakończona');
    }
  }

  void _autoTime() {
    if (analysis == null) return;
    setState(() => MusicVideoGenerator.autoTimeLines(track, analysis!));
    toast(context, 'Wersy rozłożono automatycznie na takty – to przybliżenie, sprawdź i popraw (tap-sync).');
  }

  LyricLine? get current {
    for (final l in track.lines) {
      if (l.timed && pos >= l.start && pos < (l.end > 0 ? l.end : l.start + 4)) return l;
    }
    return null;
  }

  Future<ProjectDoc> _buildProject() async {
    final (w, h) = formatPresets.values.elementAt(format);
    final d = await Services.i.store.create('${widget.karaoke ? 'Karaoke' : 'Lyric video'} – ${music!.name}', widget.karaoke ? ProjectType.karaoke : ProjectType.lyric);
    final v = VideoProject(width: w, height: h);
    d.assets[music!.id] = music!;
    final mc = AudioClip(assetId: music!.id, srcIn: 0, srcOut: music!.duration);
    if (removeVocals) mc.effects.add(AudioEffect(AudioFx.vocalRemove));
    v.audio.tracks.first.clips.add(mc);
    v.musicAssetId = music!.id;
    v.fixedDuration = music!.duration;
    if (visuals.isEmpty) {
      v.clips.add(VisualClip(kind: ClipKind.color, color: '#101418', imageDuration: music!.duration));
      v.vfx.add(VfxItem(type: 'particles', reactive: true, intensity: 0.5));
    } else {
      final per = music!.duration / visuals.length;
      for (final a in visuals) {
        d.assets[a.id] = a;
        v.clips.add(VisualClip(kind: a.kind.name == 'video' ? ClipKind.video : ClipKind.image, assetId: a.id, imageDuration: per + 1, srcOut: a.duration, loopVideo: true, motion: Motion(preset: MotionPreset.kenBurnsIn, intensity: 0.3), fit: FitMode.blurBackground, transition: Transition(type: 'fade', duration: 1), grade: ColorGrade(brightness: -0.12, saturation: 0.9)));
      }
    }
    track
      ..mode = mode
      ..anim = anim
      ..style = style.toJson();
    track.finalizeTiming(songDuration: music!.duration);
    v.lyrics = LyricsTrack.fromJson(track.toJson());
    d.video = v;
    d.publish.title = music!.name;
    await Services.i.store.save(d);
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 1000;
    final left = ListView(padding: const EdgeInsets.all(12), children: [
      Section(title: '1. Muzyka i tło', children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: _pickMusic, icon: const Icon(Icons.library_music), label: Text(music?.name ?? 'Wybierz utwór')),
          OutlinedButton.icon(onPressed: () async {
            final a = await importMedia(context, [...imageExt, ...videoExt]);
            setState(() => visuals.addAll(a));
          }, icon: const Icon(Icons.wallpaper), label: Text('Tło (${visuals.length})')),
        ]),
        if (widget.karaoke) SwitchListTile(contentPadding: EdgeInsets.zero, value: removeVocals, title: const Text('Usuń wokal z podkładu (DSP)'), subtitle: const Text('Odejmowanie kanałów – działa dla wokalu w centrum miksu'), onChanged: (v) => setState(() => removeVocals = v)),
        if (analysis != null) Text('${analysis!.bpm.toStringAsFixed(1)} BPM • ${fmtTime(analysis!.duration)}', style: const TextStyle(color: WmsColors.accent)),
      ]),
      Section(title: '2. Tekst (${track.lines.length} wersów)', children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(onPressed: _paste, icon: const Icon(Icons.content_paste), label: const Text('Wklej tekst')),
          OutlinedButton.icon(onPressed: _import, icon: const Icon(Icons.file_open), label: const Text('Import SRT/VTT/LRC')),
          PopupMenuButton<String>(onSelected: _export, itemBuilder: (c) => const [PopupMenuItem(value: 'srt', child: Text('Eksport SRT')), PopupMenuItem(value: 'vtt', child: Text('Eksport VTT')), PopupMenuItem(value: 'lrc', child: Text('Eksport LRC'))], child: const Padding(padding: EdgeInsets.all(10), child: Text('Eksport ▾'))),
        ]),
      ]),
      Section(title: '3. Synchronizacja', children: [
        const Text('Tryb ręczny: odtwórz utwór i naciskaj przycisk (lub SPACJĘ) w momencie rozpoczęcia kolejnego wersu. W trybie słów – na początku każdego słowa.', style: TextStyle(color: WmsColors.muted, fontSize: 12)),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          StreamBuilder<bool>(stream: player.stream.playing, builder: (c, s) => IconButton.filled(icon: Icon((s.data ?? false) ? Icons.pause : Icons.play_arrow), onPressed: music == null ? null : player.playOrPause)),
          Text(fmtTime(pos)),
          FilterChip(label: const Text('Tryb tap-sync'), selected: tapMode, onSelected: (v) => setState(() => {tapMode = v, tapIndex = 0, wordIndex = 0})),
          FilterChip(label: const Text('Synchronizacja słów'), selected: wordMode, onSelected: (v) => setState(() => wordMode = v)),
          OutlinedButton(onPressed: analysis == null ? null : _autoTime, child: const Text('Auto (wg taktów)')),
          OutlinedButton(onPressed: analysis == null ? null : () => setState(() => track.snapToBeats(analysis!.beats)), child: const Text('Przyciągnij do bitów')),
        ]),
        if (tapMode)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 80,
              child: FilledButton(
                onPressed: _tap,
                child: Text(tapIndex < track.lines.length ? (wordMode ? 'SŁOWO: ${track.lines[tapIndex].text.split(RegExp(r'\s+'))[wordIndex.clamp(0, track.lines[tapIndex].text.split(RegExp(r'\s+')).length - 1)]}' : 'TERAZ: ${track.lines[tapIndex].text}') : 'Koniec', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
              ),
            ),
          ),
        const Divider(),
        Row(children: [
          const Text('Korekta grupowa:'),
          TextButton(onPressed: () => setState(() => track.shift(-0.1, only: sel.isEmpty ? null : sel)), child: const Text('-0,1 s')),
          TextButton(onPressed: () => setState(() => track.shift(0.1, only: sel.isEmpty ? null : sel)), child: const Text('+0,1 s')),
          TextButton(onPressed: () => setState(() => track.shift(-0.5, only: sel.isEmpty ? null : sel)), child: const Text('-0,5 s')),
          TextButton(onPressed: () => setState(() => track.shift(0.5, only: sel.isEmpty ? null : sel)), child: const Text('+0,5 s')),
          Text(sel.isEmpty ? '(wszystkie)' : '(${sel.length} zazn.)', style: const TextStyle(color: WmsColors.muted)),
        ]),
      ]),
      for (var i = 0; i < track.lines.length; i++)
        ListTile(
          dense: true,
          selected: current == track.lines[i],
          leading: Checkbox(value: sel.contains(i), onChanged: (v) => setState(() => v! ? sel.add(i) : sel.remove(i))),
          title: TextFormField(initialValue: track.lines[i].text, onChanged: (v) => track.lines[i].text = v, style: TextStyle(fontWeight: tapMode && i == tapIndex ? FontWeight.bold : null)),
          subtitle: Text(track.lines[i].timed ? '${fmtTime(track.lines[i].start)} → ${track.lines[i].end > 0 ? fmtTime(track.lines[i].end) : '…'}${track.lines[i].words.isNotEmpty ? ' • ${track.lines[i].words.length} słów' : ''}' : 'bez czasu'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'Ustaw start = kursor', icon: const Icon(Icons.my_location, size: 18), onPressed: () => setState(() => track.tap(i, pos))),
            IconButton(tooltip: 'Odtwórz od wersu', icon: const Icon(Icons.play_circle_outline, size: 18), onPressed: track.lines[i].timed ? () => {player.seek(Duration(milliseconds: (track.lines[i].start * 1000).round())), player.play()} : null),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => track.lines.removeAt(i))),
          ]),
        ),
    ]);
    final right = ListView(padding: const EdgeInsets.all(12), children: [
      Section(title: 'Podgląd na żywo', children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: Colors.black,
            alignment: style.align == 'top' ? Alignment.topCenter : style.align == 'center' ? Alignment.center : Alignment.bottomCenter,
            padding: const EdgeInsets.all(16),
            child: _LiveLine(line: current, pos: pos, style: style, karaoke: mode == LyricsMode.karaoke),
          ),
        ),
      ]),
      Section(title: 'Wygląd', children: [
        DropdownButton<LyricsMode>(value: mode, items: const [
          DropdownMenuItem(value: LyricsMode.lyric, child: Text('Lyric video (animowane wersy)')),
          DropdownMenuItem(value: LyricsMode.karaoke, child: Text('Karaoke (podświetlanie słów)')),
          DropdownMenuItem(value: LyricsMode.scroll, child: Text('Automatyczne przewijanie')),
          DropdownMenuItem(value: LyricsMode.subtitles, child: Text('Zwykłe napisy')),
        ], onChanged: (v) => setState(() => mode = v!)),
        if (mode == LyricsMode.lyric) DropdownButton<String>(value: anim, items: [for (final e in textAnimNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => setState(() => anim = v!)),
        DropdownButton<int>(value: format, items: [for (var i = 0; i < formatPresets.length; i++) DropdownMenuItem(value: i, child: Text(formatPresets.keys.elementAt(i)))], onChanged: (v) => setState(() => format = v!)),
        TextStyleEditor(s: style, onChanged: () => setState(() {})),
      ]),
      Wrap(spacing: 8, children: [
        FilledButton.icon(onPressed: music == null || track.lines.where((l) => l.timed).isEmpty ? null : () async {
          final d = await _buildProject();
          if (!context.mounted) return;
          final s = await showVideoExportDialog(context, d.video!);
          if (s != null && context.mounted) await queueVideoRender(context, d, s);
        }, icon: const Icon(Icons.movie_creation), label: const Text('Renderuj')),
        OutlinedButton.icon(onPressed: music == null ? null : () async {
          final d = await _buildProject();
          Nav.openProject(d);
        }, icon: const Icon(Icons.edit), label: const Text('Otwórz w Studiu Wideo')),
      ]),
      const SizedBox(height: 8),
      const Text('Automatyczna transkrypcja śpiewu: niedostępna w tej wersji (brak dołączonego lokalnego modelu rozpoznawania mowy). Synchronizacja odbywa się ręcznie (tap-sync) lub automatycznie według taktów – zawsze z możliwością korekty.', style: TextStyle(color: WmsColors.muted, fontSize: 12)),
    ]);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.space): _tap},
      child: Focus(autofocus: true, child: wide ? Row(children: [Expanded(flex: 3, child: left), SizedBox(width: 460, child: right)]) : ListView(children: [SizedBox(height: 900, child: left), SizedBox(height: 1000, child: right)])),
    );
  }
}

class _LiveLine extends StatelessWidget {
  final LyricLine? line;
  final double pos;
  final TextStyleSpec style;
  final bool karaoke;
  const _LiveLine({this.line, required this.pos, required this.style, required this.karaoke});
  Color _c(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));
  @override
  Widget build(BuildContext context) {
    if (line == null) return const SizedBox();
    final base = TextStyle(fontSize: style.size / 3, fontWeight: style.bold ? FontWeight.bold : FontWeight.normal, color: _c(style.color), shadows: [Shadow(color: _c(style.outlineColor), blurRadius: style.outline + 1)]);
    if (!karaoke || line!.words.isEmpty) return Text(line!.text, style: base, textAlign: TextAlign.center);
    return Text.rich(TextSpan(children: [
      for (final w in line!.words) TextSpan(text: '${w.text} ', style: base.copyWith(color: pos >= w.start ? _c(style.highlightColor) : _c(style.color))),
    ]), textAlign: TextAlign.center);
  }
}

