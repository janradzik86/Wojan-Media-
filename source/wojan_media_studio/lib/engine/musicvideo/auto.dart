import 'dart:math' as math;

import '../audio/audio_project.dart';
import '../dsp/analysis.dart';
import '../ffmpeg/probe.dart';
import '../lyrics/lyrics.dart';
import '../project/asset.dart';
import '../video/color.dart';
import '../video/model.dart';
import 'styles.dart';

enum MusicVideoMode { staticCover, animatedCover, dynamic, slideshow, lyricVideo, karaoke, visualizer, promo, album, trailer, beatSync }

const musicVideoModeNames = <MusicVideoMode, String>{
  MusicVideoMode.staticCover: 'Statyczna okładka z muzyką',
  MusicVideoMode.animatedCover: 'Animowana okładka',
  MusicVideoMode.dynamic: 'Dynamiczny teledysk',
  MusicVideoMode.slideshow: 'Pokaz slajdów',
  MusicVideoMode.lyricVideo: 'Lyric Video',
  MusicVideoMode.karaoke: 'Karaoke Video',
  MusicVideoMode.visualizer: 'Audio Visualizer',
  MusicVideoMode.promo: 'Klip promocyjny (najlepszy fragment)',
  MusicVideoMode.album: 'Album Video',
  MusicVideoMode.trailer: 'Trailer',
  MusicVideoMode.beatSync: 'Teledysk zsynchronizowany z rytmem',
};

class MusicVideoRequest {
  final MediaAsset music;
  final List<MediaAsset> visuals; // images and/or videos (≥1 for most modes)
  final List<MediaAsset> extraTracks; // album mode: further tracks
  final String? lyrics; // raw pasted text or LRC/SRT
  final String? lyricsFormat; // 'lrc','srt','vtt' or null for plain
  final String title, artist;
  final StyleTemplate style;
  final MusicVideoMode mode;
  final int width, height;
  final double fps;
  final MediaAsset? logo;
  final double? promoLength; // seconds (promo/trailer)
  final List<AudioAnalysis> extraAnalyses;
  MusicVideoRequest({
    required this.music,
    required this.visuals,
    this.extraTracks = const [],
    this.lyrics,
    this.lyricsFormat,
    this.title = '',
    this.artist = '',
    required this.style,
    required this.mode,
    this.width = 1080,
    this.height = 1920,
    this.fps = 30,
    this.logo,
    this.promoLength,
    this.extraAnalyses = const [],
  });
}

/// One-click music video generator: turns music + visuals into an editable
/// [VideoProject] whose cuts, transitions and effects follow the real beat
/// grid of the analysed track.
class MusicVideoGenerator {
  final math.Random _rnd;
  MusicVideoGenerator({int seed = 7}) : _rnd = math.Random(seed);

  T _pick<T>(List<T> l, int i) => l[i % l.length];

  /// Finds the loudest window of [len] seconds (chorus/drop heuristic),
  /// starting on a downbeat.
  static double bestSection(AudioAnalysis a, double len) {
    if (a.duration <= len) return 0;
    final fr = a.frameRate;
    final win = (len * fr).round();
    var best = 0.0, bestT = 0.0;
    var acc = 0.0;
    for (var i = 0; i < a.rms.length; i++) {
      acc += a.rms[i] + a.onsetEnv[i] * 0.5;
      if (i >= win) acc -= a.rms[i - win] + a.onsetEnv[i - win] * 0.5;
      if (i >= win && acc > best) {
        best = acc;
        bestT = (i - win) / fr;
      }
    }
    final db = a.downbeats.isNotEmpty ? a.downbeats : a.beats;
    if (db.isNotEmpty) {
      bestT = db.reduce((x, y) => (x - bestT).abs() < (y - bestT).abs() ? x : y);
    }
    return bestT.clamp(0, a.duration - len).toDouble();
  }

  /// Cut points following the beat grid, every [n] beats, within [s,e].
  static List<double> cutPoints(AudioAnalysis a, double s, double e, int n, {double minLen = 0.6}) {
    final beats = a.beats.where((b) => b > s + 0.05 && b < e - 0.3).toList();
    final cuts = <double>[s];
    if (beats.isEmpty) {
      for (var t = s + 3; t < e - 0.5; t += 3) {
        cuts.add(t);
      }
    } else {
      // align phase to downbeats when possible
      var start = 0;
      if (a.downbeats.isNotEmpty && n % 4 == 0) {
        final firstDb = a.downbeats.firstWhere((d) => d > s + 0.05, orElse: () => beats.first);
        start = beats.indexWhere((b) => (b - firstDb).abs() < 0.02).clamp(0, beats.length - 1);
        if (start > 0 && beats[start] - s >= minLen) cuts.add(beats[start]);
      }
      for (var i = start + n; i < beats.length; i += n) {
        if (beats[i] - cuts.last >= minLen) cuts.add(beats[i]);
      }
    }
    cuts.add(e);
    return cuts;
  }

  VideoProject generate(MusicVideoRequest r, AudioAnalysis a) {
    final st = r.style;
    final p = VideoProject(width: r.width, height: r.height, fps: r.fps, background: st.background);
    p.musicAssetId = r.music.id;
    p.beatMarkers = [...a.beats];
    var songStart = 0.0;
    var songEnd = a.duration;
    if (r.mode == MusicVideoMode.promo || r.mode == MusicVideoMode.trailer) {
      final len = (r.promoLength ?? (r.mode == MusicVideoMode.trailer ? 30 : 30)).clamp(5.0, a.duration);
      songStart = bestSection(a, len);
      songEnd = songStart + len;
    }
    final total = songEnd - songStart;
    // ---- audio
    final music = p.audio.tracks.first;
    final mclip = AudioClip(assetId: r.music.id, srcIn: songStart, srcOut: songEnd, position: 0);
    if (r.mode == MusicVideoMode.promo || r.mode == MusicVideoMode.trailer) {
      mclip.fadeIn = 0.5;
      mclip.fadeOut = 1.5;
    }
    music.clips.add(mclip);
    var timelineEnd = total;
    final albumStarts = <double>[0];
    if (r.mode == MusicVideoMode.album) {
      var pos = total;
      for (final t in r.extraTracks) {
        music.clips.add(AudioClip(assetId: t.id, srcIn: 0, srcOut: t.duration, position: pos, fadeIn: 0.3, fadeOut: 1));
        albumStarts.add(pos);
        pos += t.duration;
      }
      timelineEnd = pos;
    }
    // Analysis shifted to the selected section (beats relative to timeline)
    final beatsTl = [for (final b in a.beats) if (b >= songStart && b <= songEnd) b - songStart];
    final period = a.bpm > 0 ? 60 / a.bpm : 0.5;
    final visuals = r.visuals;
    final hasVisuals = visuals.isNotEmpty;
    final grade = ColorGrade()..filter = st.grade;
    MotionPreset motionAt(int i) => MotionPreset.values.firstWhere((m) => m.name == _pick(st.motions, i), orElse: () => MotionPreset.kenBurnsIn);

    VisualClip clipFor(MediaAsset v, double dur, int i, {MotionPreset? motion, String? transition, double td = 0}) {
      final isVideo = v.kind == MediaKind.video;
      final c = VisualClip(
        kind: isVideo ? ClipKind.video : ClipKind.image,
        assetId: v.id,
        imageDuration: dur,
        srcIn: 0,
        srcOut: isVideo ? math.min(v.duration, dur) : 0,
        loopVideo: isVideo && v.duration < dur,
        fit: (v.width != null && v.height != null && ((v.width! > v.height!) != (r.width > r.height))) ? FitMode.blurBackground : FitMode.cover,
        motion: Motion(preset: isVideo ? MotionPreset.none : (motion ?? motionAt(i)), intensity: st.motionIntensity),
        grade: grade.copy(),
        transition: Transition(type: transition ?? 'cut', duration: td),
      );
      if (isVideo) {
        // pick a varied segment of longer videos
        if (v.duration > dur + 1) {
          final maxStart = v.duration - dur;
          c.srcIn = (maxStart * _rnd.nextDouble() * 0.8);
          c.srcOut = c.srcIn + dur;
        } else if (!c.loopVideo) {
          c.srcOut = math.min(v.duration, dur);
        }
        c.imageDuration = dur;
        c.mute = true;
      }
      return c;
    }

    // A single still image: one continuous shot for the whole audio instead
    // of fake cuts between identical frames (picture is never distorted).
    final singleStill = visuals.length == 1 && visuals.first.kind != MediaKind.video &&
        !{MusicVideoMode.staticCover, MusicVideoMode.animatedCover, MusicVideoMode.visualizer}.contains(r.mode);
    if (singleStill) {
      // shown as-is for the whole song (optionally a light pulse on the beat)
      final c = clipFor(visuals.first, timelineEnd, 0, motion: st.beatPulse || r.mode == MusicVideoMode.beatSync ? MotionPreset.beatPulse : MotionPreset.none);
      c.fit = FitMode.blurBackground;
      c.motion.intensity = 0.35;
      c.animIn = 'fade';
      c.animOut = 'fade';
      c.animOutDur = 1.5;
      p.clips.add(c);
      for (final fx in st.vfx) {
        p.vfx.add(VfxItem(type: fx, intensity: 0.5, reactive: st.reactiveVfx));
      }
    }
    switch (singleStill ? null : r.mode) {
      case null:
        break;
      case MusicVideoMode.staticCover:
        p.clips.add(VisualClip(kind: ClipKind.image, assetId: hasVisuals ? visuals.first.id : null, imageDuration: timelineEnd, fit: FitMode.blurBackground));
        if (!hasVisuals) p.clips.first.kind = ClipKind.color;
        break;
      case MusicVideoMode.animatedCover:
      case MusicVideoMode.visualizer:
        // cover with slow motion + beat pulse; long segments
        final seg = math.min(20.0, timelineEnd);
        var t = 0.0;
        var i = 0;
        while (t < timelineEnd - 0.01) {
          final d = math.min(seg, timelineEnd - t);
          final v = hasVisuals ? visuals[i % visuals.length] : null;
          final c = v == null
              ? VisualClip(kind: ClipKind.color, color: st.background, imageDuration: d)
              : clipFor(v, d, i, motion: st.beatPulse || r.mode == MusicVideoMode.visualizer ? MotionPreset.beatPulse : (i.isEven ? MotionPreset.kenBurnsIn : MotionPreset.kenBurnsOut));
          c.fit = FitMode.blurBackground;
          c.motion.intensity = 0.35;
          c.transition = Transition(type: 'fade', duration: 1);
          p.clips.add(c);
          t += d - (t + d < timelineEnd - 0.01 ? 1 : 0);
          i++;
        }
        p.vfx.add(VfxItem(type: 'particles', intensity: 0.5, reactive: true));
        if (r.mode == MusicVideoMode.visualizer) {
          final vertical = r.height > r.width;
          p.visualizers.add(VisualizerItem(style: 'circle', x: 0.1, y: vertical ? 0.25 : 0.15, width: 0.8, height: vertical ? 0.45 : 0.7, color: st.visualizerColor, color2: st.visualizerColor2, logoAssetId: r.logo?.id ?? (hasVisuals && visuals.first.kind == MediaKind.image ? visuals.first.id : null), logoSize: 0.45));
          p.visualizers.add(VisualizerItem(style: 'bars', x: 0, y: vertical ? 0.82 : 0.8, width: 1, height: 0.15, color: st.visualizerColor, opacity: 0.8));
          p.clips.forEach((c) => c.grade.brightness = -0.12);
        }
        break;
      case MusicVideoMode.slideshow:
      case MusicVideoMode.lyricVideo:
      case MusicVideoMode.karaoke:
      case MusicVideoMode.dynamic:
      case MusicVideoMode.beatSync:
      case MusicVideoMode.promo:
      case MusicVideoMode.trailer:
      case MusicVideoMode.album:
        var every = st.cutEveryBeats;
        if (r.mode == MusicVideoMode.slideshow || r.mode == MusicVideoMode.lyricVideo || r.mode == MusicVideoMode.karaoke) every = math.max(8, every);
        if (r.mode == MusicVideoMode.beatSync) every = math.max(1, every ~/ 2);
        if (r.mode == MusicVideoMode.trailer) every = 2;
        // Ensure every visual is shown at least once when there are many.
        if (hasVisuals && beatsTl.isNotEmpty) {
          final maxEvery = (beatsTl.length / visuals.length).floor();
          if (maxEvery >= 1 && maxEvery < every && r.mode != MusicVideoMode.beatSync) every = math.max(1, maxEvery);
        }
        final shifted = a.withBeats(beatsTl);
        final cuts = cutPoints(shifted, 0, timelineEnd, every, minLen: math.max(0.4, period * 0.9));
        for (var i = 0; i < cuts.length - 1; i++) {
          final isLast = i == cuts.length - 2;
          final trType = isLast ? 'cut' : _pick(st.transitions, i);
          var td = trType == 'cut' ? 0.0 : math.min(period * st.transitionBeats, (cuts[i + 1] - cuts[i]) * 0.45);
          if (r.mode == MusicVideoMode.trailer && trType != 'cut') td = math.min(td, 0.25);
          final dur = cuts[i + 1] - cuts[i] + td;
          if (!hasVisuals) {
            p.clips.add(VisualClip(kind: ClipKind.color, color: st.background, imageDuration: dur, transition: Transition(type: trType, duration: td)));
          } else {
            p.clips.add(clipFor(visuals[i % visuals.length], dur, i, transition: trType, td: td));
          }
        }
        for (final fx in st.vfx) {
          p.vfx.add(VfxItem(type: fx, intensity: 0.55, reactive: st.reactiveVfx));
        }
        if (r.mode == MusicVideoMode.trailer) p.vfx.add(VfxItem(type: 'cinematic', intensity: 0.6));
        break;
    }

    // ---- titles
    final textStyle = TextStyleSpec(font: st.font, color: st.textColor, highlightColor: st.accentColor, outlineColor: st.outlineColor, size: 72, align: 'center');
    if (r.title.isNotEmpty || r.artist.isNotEmpty) {
      final double introLen = math.min(5.0, math.max(2.5, (a.downbeats.length > 2 ? a.downbeats[2] - a.downbeats[0] : 4.0)));
      p.texts.add(TextItem(text: [if (r.artist.isNotEmpty) r.artist, if (r.title.isNotEmpty) r.title].join('\n'), start: 0.3, duration: introLen, anim: st.textAnim, animDur: 0.6, style: textStyle));
      if (r.mode == MusicVideoMode.album) {
        for (var i = 0; i < r.extraTracks.length; i++) {
          p.texts.add(TextItem(text: r.extraTracks[i].name, start: albumStarts[i + 1] + 0.3, duration: 4, anim: st.textAnim, style: textStyle.copy()..size = 60));
        }
      }
    }
    // ---- lyrics
    if (r.lyrics != null && r.lyrics!.trim().isNotEmpty) {
      final track = LyricsTrack.parse(r.lyrics!, ext: r.lyricsFormat);
      if (track.lines.any((l) => !l.timed)) autoTimeLines(track, a, songStart: songStart, songEnd: songEnd);
      if (songStart > 0) track.shift(-songStart);
      track.lines.removeWhere((l) => l.start < 0 || l.start > total);
      track.mode = r.mode == MusicVideoMode.karaoke ? LyricsMode.karaoke : (r.mode == MusicVideoMode.lyricVideo ? LyricsMode.lyric : LyricsMode.subtitles);
      track.anim = st.textAnim == 'typewriter' ? 'typewriter' : 'wordPop';
      final ls = textStyle.copy()
        ..size = r.mode == MusicVideoMode.lyricVideo ? 70 : 58
        ..align = r.mode == MusicVideoMode.lyricVideo ? 'center' : 'bottom'
        ..marginV = r.height > r.width ? 360 : 90;
      track.style = ls.toJson();
      p.lyrics = track;
    }
    if (r.logo != null && r.mode != MusicVideoMode.visualizer) {
      p.overlays.add(OverlayItem(assetId: r.logo!.id, start: 0, duration: timelineEnd, x: 0.88, y: 0.07, scale: 0.14, opacity: 0.9, animIn: 'fade'));
    }
    p.fixedDuration = timelineEnd;
    return p;
  }

  /// Approximate automatic timing for untimed lyric lines: lines are placed
  /// on downbeats across the vocal region (after the intro until the
  /// outro). This is NOT speech recognition – users refine it with tap-sync.
  static void autoTimeLines(LyricsTrack t, AudioAnalysis a, {double songStart = 0, double? songEnd}) {
    final lines = t.lines;
    if (lines.isEmpty) return;
    final end = (songEnd ?? a.duration);
    // intro: first point where energy rises above 40% of its 90th percentile
    final sorted = List<double>.from(a.rms)..sort();
    final ref = sorted.isEmpty ? 0.0 : sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)];
    var introEnd = songStart;
    for (var i = (songStart * a.frameRate).floor(); i < a.rms.length; i++) {
      if (a.rms[i] > ref * 0.4) {
        introEnd = i / a.frameRate;
        break;
      }
    }
    final grid = (a.downbeats.isNotEmpty ? a.downbeats : a.beats).where((d) => d >= introEnd && d < end - 2).toList();
    final usable = end - 2 - introEnd;
    if (grid.length >= lines.length) {
      final step = grid.length / lines.length;
      for (var i = 0; i < lines.length; i++) {
        lines[i].start = grid[(i * step).floor()];
        lines[i].end = -1;
        lines[i].words = [];
      }
    } else {
      for (var i = 0; i < lines.length; i++) {
        lines[i].start = introEnd + usable * i / lines.length;
        lines[i].end = -1;
        lines[i].words = [];
      }
    }
    t.finalizeTiming(songDuration: end);
  }
}
