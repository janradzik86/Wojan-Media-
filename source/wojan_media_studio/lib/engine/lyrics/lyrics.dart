import '../util/json_util.dart';

class LyricWord {
  double start, end;
  String text;
  LyricWord(this.start, this.end, this.text);
  Map<String, dynamic> toJson() => {'s': start, 'e': end, 't': text};
  factory LyricWord.fromJson(Map<String, dynamic> j) => LyricWord(jd(j['s']), jd(j['e']), js(j['t']));
}

class LyricLine {
  double start, end; // end < 0 => until next line
  String text;
  List<LyricWord> words;
  LyricLine(this.start, this.end, this.text, [List<LyricWord>? words]) : words = words ?? [];
  bool get timed => start >= 0;
  Map<String, dynamic> toJson() => {'s': start, 'e': end, 't': text, 'w': words.map((e) => e.toJson()).toList()};
  factory LyricLine.fromJson(Map<String, dynamic> j) => LyricLine(jd(j['s'], -1), jd(j['e'], -1), js(j['t']), jl(j['w']).map(LyricWord.fromJson).toList());
}

enum LyricsMode { lyric, karaoke, scroll, subtitles }

/// Lyrics / subtitles track with timing and display options.
class LyricsTrack {
  List<LyricLine> lines;
  LyricsMode mode;
  String anim; // text animation id for lyric mode
  Map<String, dynamic> style; // TextStyleSpec json (kept generic to avoid cycle)
  int visibleLines; // karaoke: lines shown at once (1 or 2)
  LyricsTrack({List<LyricLine>? lines, this.mode = LyricsMode.lyric, this.anim = 'fade', Map<String, dynamic>? style, this.visibleLines = 2})
      : lines = lines ?? [],
        style = style ?? {};

  Map<String, dynamic> toJson() => {'lines': lines.map((e) => e.toJson()).toList(), 'mode': mode.name, 'anim': anim, 'style': style, 'visibleLines': visibleLines};
  factory LyricsTrack.fromJson(Map<String, dynamic> j) => LyricsTrack(
        lines: jl(j['lines']).map(LyricLine.fromJson).toList(),
        mode: LyricsMode.values.firstWhere((e) => e.name == j['mode'], orElse: () => LyricsMode.lyric),
        anim: js(j['anim'], 'fade'),
        style: jm(j['style']),
        visibleLines: ji(j['visibleLines'], 2),
      );

  // ------------------------------------------------------------ editing
  /// Splits pasted lyrics into lines (blank lines separate stanzas and are
  /// dropped; overly long lines are wrapped at ~[maxChars]).
  static List<LyricLine> splitText(String text, {int maxChars = 42}) {
    final out = <LyricLine>[];
    for (var raw in text.replaceAll('\r', '').split('\n')) {
      raw = raw.trim();
      if (raw.isEmpty) continue;
      // Remove section markers like [Chorus] / [Refren]
      if (RegExp(r'^\[[^\]]*\]$').hasMatch(raw)) continue;
      if (raw.length <= maxChars) {
        out.add(LyricLine(-1, -1, raw));
        continue;
      }
      final words = raw.split(RegExp(r'\s+'));
      var cur = StringBuffer();
      for (final w in words) {
        if (cur.isNotEmpty && cur.length + 1 + w.length > maxChars) {
          out.add(LyricLine(-1, -1, cur.toString()));
          cur = StringBuffer();
        }
        if (cur.isNotEmpty) cur.write(' ');
        cur.write(w);
      }
      if (cur.isNotEmpty) out.add(LyricLine(-1, -1, cur.toString()));
    }
    return out;
  }

  /// Fills missing end times (next line start or +4 s) and word timings
  /// (proportional to syllable-ish character count) for karaoke.
  void finalizeTiming({double songDuration = 0}) {
    final timed = lines.where((l) => l.timed).toList()..sort((a, b) => a.start.compareTo(b.start));
    for (var i = 0; i < timed.length; i++) {
      final l = timed[i];
      if (l.end <= l.start) {
        final next = i + 1 < timed.length ? timed[i + 1].start : (songDuration > 0 ? songDuration : l.start + 4);
        l.end = (next - l.start) > 8 ? l.start + 6 : next;
      }
      final ws = l.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      final hasWords = l.words.length == ws.length && l.words.every((w) => w.end > w.start);
      if (!hasWords) {
        final total = ws.fold<int>(0, (s, w) => s + w.length + 1);
        var t = l.start;
        final span = (l.end - l.start) * 0.95;
        l.words = [];
        for (final w in ws) {
          final d = span * (w.length + 1) / total;
          l.words.add(LyricWord(t, t + d, w));
          t += d;
        }
      }
    }
  }

  /// Group timing correction: shift and/or stretch selected (or all) lines.
  void shift(double offset, {Set<int>? only, double stretch = 1, double pivot = 0}) {
    for (var i = 0; i < lines.length; i++) {
      if (only != null && !only.contains(i)) continue;
      final l = lines[i];
      double f(double t) => t < 0 ? t : (pivot + (t - pivot) * stretch + offset).clamp(0, double.infinity).toDouble();
      l.start = f(l.start);
      l.end = f(l.end);
      for (final w in l.words) {
        w.start = f(w.start);
        w.end = f(w.end);
      }
    }
  }

  /// Tap-sync helper: sets start of line [index] (and end of previous).
  void tap(int index, double t) {
    if (index < 0 || index >= lines.length) return;
    lines[index].start = t;
    lines[index].words = [];
    if (index > 0 && (lines[index - 1].end < 0 || lines[index - 1].end > t)) lines[index - 1].end = t;
  }

  /// Snaps line starts to the nearest beat within [tolerance] seconds.
  void snapToBeats(List<double> beats, {double tolerance = 0.15}) {
    if (beats.isEmpty) return;
    for (final l in lines) {
      if (!l.timed) continue;
      var best = l.start, bd = tolerance;
      for (final b in beats) {
        final d = (b - l.start).abs();
        if (d < bd) {
          bd = d;
          best = b;
        }
      }
      l.start = best;
    }
  }

  // ------------------------------------------------------------ formats
  static String _ts(double t, {String sep = ',', bool hours = true}) {
    if (t < 0) t = 0;
    final ms = (t * 1000).round();
    final h = ms ~/ 3600000, m = (ms ~/ 60000) % 60, s = (ms ~/ 1000) % 60, r = ms % 1000;
    final core = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}$sep${r.toString().padLeft(3, '0')}';
    return hours ? '${h.toString().padLeft(2, '0')}:$core' : core;
  }

  static String _lrcTs(double t) {
    final cs = (t * 100).round();
    final m = cs ~/ 6000, s = (cs ~/ 100) % 60, r = cs % 100;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${r.toString().padLeft(2, '0')}';
  }

  String toSrt() {
    finalizeTiming();
    final b = StringBuffer();
    var n = 1;
    for (final l in lines.where((l) => l.timed)) {
      b.writeln(n++);
      b.writeln('${_ts(l.start)} --> ${_ts(l.end)}');
      b.writeln(l.text);
      b.writeln();
    }
    return b.toString();
  }

  String toVtt() {
    finalizeTiming();
    final b = StringBuffer('WEBVTT\n\n');
    for (final l in lines.where((l) => l.timed)) {
      b.writeln('${_ts(l.start, sep: '.')} --> ${_ts(l.end, sep: '.')}');
      b.writeln(l.text);
      b.writeln();
    }
    return b.toString();
  }

  /// LRC; with [enhanced] word-level `<mm:ss.xx>` tags (A2 extension).
  String toLrc({bool enhanced = false, Map<String, String> tags = const {}}) {
    finalizeTiming();
    final b = StringBuffer();
    tags.forEach((k, v) => b.writeln('[$k:$v]'));
    for (final l in lines.where((l) => l.timed)) {
      if (enhanced && l.words.isNotEmpty) {
        b.write('[${_lrcTs(l.start)}]');
        for (final w in l.words) {
          b.write('<${_lrcTs(w.start)}>${w.text} ');
        }
        b.writeln('<${_lrcTs(l.end)}>');
      } else {
        b.writeln('[${_lrcTs(l.start)}]${l.text}');
      }
    }
    return b.toString();
  }

  static double _parseTs(String s) {
    s = s.trim().replaceAll(',', '.');
    final p = s.split(':');
    var t = 0.0;
    for (final x in p) {
      t = t * 60 + (double.tryParse(x) ?? 0);
    }
    return t;
  }

  static LyricsTrack parse(String content, {String? ext}) {
    final c = content.replaceAll('\r', '').replaceFirst('﻿', '');
    final e = ext?.toLowerCase();
    if (e == 'lrc' || (e == null && RegExp(r'^\[\d+:\d+', multiLine: true).hasMatch(c))) return parseLrc(c);
    if (e == 'vtt' || c.startsWith('WEBVTT')) return parseSrtVtt(c);
    if (e == 'srt' || c.contains('-->')) return parseSrtVtt(c);
    return LyricsTrack(lines: splitText(c));
  }

  static LyricsTrack parseSrtVtt(String c) {
    final lines = <LyricLine>[];
    final blocks = c.split(RegExp(r'\n\s*\n'));
    final re = RegExp(r'((?:\d+:)?\d+:\d+[\.,]\d+)\s*-->\s*((?:\d+:)?\d+:\d+[\.,]\d+)');
    for (final blk in blocks) {
      final ls = blk.split('\n').where((x) => x.trim().isNotEmpty).toList();
      final idx = ls.indexWhere((x) => re.hasMatch(x));
      if (idx < 0) continue;
      final m = re.firstMatch(ls[idx])!;
      final text = ls.sublist(idx + 1).join(' ').replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (text.isEmpty) continue;
      lines.add(LyricLine(_parseTs(m.group(1)!), _parseTs(m.group(2)!), text));
    }
    return LyricsTrack(lines: lines, mode: LyricsMode.subtitles);
  }

  static LyricsTrack parseLrc(String c) {
    final lines = <LyricLine>[];
    var offset = 0.0;
    final tagRe = RegExp(r'\[(\d+:\d+(?:[\.:]\d+)?)\]');
    final wordRe = RegExp(r'<(\d+:\d+(?:[\.:]\d+)?)>([^<]*)');
    for (final raw in c.split('\n')) {
      final off = RegExp(r'^\[offset:\s*([+-]?\d+)\]').firstMatch(raw.trim());
      if (off != null) offset = int.parse(off.group(1)!) / 1000;
      final times = tagRe.allMatches(raw).map((m) => _parseTs(m.group(1)!.replaceFirst(RegExp(r':(\d+)$'), r'.$1'))).toList();
      if (times.isEmpty) continue;
      var text = raw.replaceAll(tagRe, '');
      final words = <LyricWord>[];
      final wm = wordRe.allMatches(text).toList();
      if (wm.isNotEmpty) {
        for (var i = 0; i < wm.length; i++) {
          final w = wm[i].group(2)!.trim();
          final st = _parseTs(wm[i].group(1)!);
          final en = i + 1 < wm.length ? _parseTs(wm[i + 1].group(1)!) : st + 0.5;
          if (w.isNotEmpty) words.add(LyricWord(st - offset, en - offset, w));
        }
        text = words.map((w) => w.text).join(' ');
      }
      text = text.trim();
      for (final t in times) {
        lines.add(LyricLine(t - offset, -1, text, words.map((w) => LyricWord(w.start, w.end, w.text)).toList()));
      }
    }
    lines.sort((a, b) => a.start.compareTo(b.start));
    // end of enhanced lines = last word end
    for (final l in lines) {
      if (l.words.isNotEmpty) l.end = l.words.last.end;
    }
    final t = LyricsTrack(lines: lines.where((l) => l.text.isNotEmpty).toList(), mode: LyricsMode.karaoke);
    t.finalizeTiming();
    return t;
  }
}
