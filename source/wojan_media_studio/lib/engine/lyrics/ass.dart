import 'dart:math' as math;

import '../video/model.dart';
import 'lyrics.dart';

/// Generates Advanced SubStation Alpha scripts rendered by libass inside
/// FFmpeg (`subtitles` filter). Used for titles, animated text, lyric videos,
/// karaoke and burned-in subtitles. Full Unicode (Polish characters) support.
class AssBuilder {
  final int w, h;
  final _styles = <String, TextStyleSpec>{};
  final _events = <String>[];
  AssBuilder(this.w, this.h);

  double get _scale => math.min(w, h) / 1080.0;

  static String color(String hex, [double opacity = 1]) {
    var hx = hex.replaceFirst('#', '').replaceFirst('0x', '');
    if (hx.length < 6) hx = hx.padLeft(6, '0');
    final r = hx.substring(0, 2), g = hx.substring(2, 4), b = hx.substring(4, 6);
    final a = ((1 - opacity.clamp(0.0, 1.0)) * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase();
    return '&H$a${b.toUpperCase()}${g.toUpperCase()}${r.toUpperCase()}';
  }

  static String _t(double s) {
    if (s < 0) s = 0;
    final cs = (s * 100).round();
    final hh = cs ~/ 360000, mm = (cs ~/ 6000) % 60, ss = (cs ~/ 100) % 60, c = cs % 100;
    return '$hh:${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}.${c.toString().padLeft(2, '0')}';
  }

  /// Escapes user text for ASS (braces start override blocks).
  static String esc(String s) => s.replaceAll('\\', '⧵').replaceAll('{', '(').replaceAll('}', ')').replaceAll('\n', r'\N');

  String style(TextStyleSpec s, {bool karaoke = false}) {
    final name = 'S${_styles.length}';
    _styles[name] = s;
    return name;
  }

  String _styleLine(String name, TextStyleSpec s) {
    final fs = (s.size * _scale).round();
    final align = s.align == 'top' ? 8 : s.align == 'center' ? 5 : 2;
    final primary = color(s.highlightColor, s.opacity); // karaoke "sung" colour
    final secondary = color(s.color, s.opacity);
    // For non-karaoke events we override \1c with the main colour.
    final outline = color(s.box ? s.boxColor : s.outlineColor, s.box ? 0.6 * s.opacity : s.opacity);
    final back = color(s.shadowColor, 0.5 * s.opacity);
    return 'Style: $name,${s.font},$fs,$primary,$secondary,$outline,$back,${s.bold ? -1 : 0},${s.italic ? -1 : 0},0,0,100,100,${s.letterSpacing.toStringAsFixed(1)},0,${s.box ? 3 : 1},${(s.outline * _scale).toStringAsFixed(1)},${(s.shadow * _scale).toStringAsFixed(1)},$align,40,40,${(s.marginV * _scale).round()},1';
  }

  void _event(double start, double end, String style, String text, {int layer = 0}) {
    _events.add('Dialogue: $layer,${_t(start)},${_t(end)},$style,,0,0,0,,$text');
  }

  /// Anchor point (pixel) of an item for animations that need coordinates.
  (int, int, int) _anchor(TextStyleSpec s, double x, double y) {
    if (x >= 0 && y >= 0) return ((x * w).round(), (y * h).round(), 5);
    final mv = (s.marginV * _scale).round();
    switch (s.align) {
      case 'top':
        return (w ~/ 2, mv, 8);
      case 'center':
        return (w ~/ 2, h ~/ 2, 5);
      default:
        return (w ~/ 2, h - mv, 2);
    }
  }

  String _base(TextStyleSpec s) => '\\1c${color(s.color, s.opacity)}';

  /// Adds an animated text item.
  void addText(TextItem item) {
    final s = item.style;
    final st = style(s);
    final dur = item.duration;
    final ms = (item.animDur * 1000).round();
    final totalMs = (dur * 1000).round();
    final (ax, ay, an) = _anchor(s, item.x, item.y);
    final pos = '\\an$an\\pos($ax,$ay)';
    final text = esc(item.text);
    String body;
    switch (item.anim) {
      case 'none':
        body = '{$pos${_base(s)}}$text';
        break;
      case 'fade':
        body = '{$pos${_base(s)}\\fad($ms,$ms)}$text';
        break;
      case 'typewriter':
        final chars = item.text.runes.map(String.fromCharCode).toList();
        final per = math.max(20, (math.min(item.animDur * 3, dur * 0.6) * 1000 / math.max(1, chars.length)).round());
        final b = StringBuffer('{$pos${_base(s)}\\fad(0,$ms)}');
        for (var i = 0; i < chars.length; i++) {
          b.write('{\\alpha&HFF&\\t(${i * per},${i * per + 1},\\alpha&H00&)}${esc(chars[i])}');
        }
        body = b.toString();
        break;
      case 'wordPop':
        final words = item.text.split(RegExp(r'\s+'));
        final per = math.max(80, (math.min(dur * 0.6, words.length * 0.35) * 1000 / math.max(1, words.length)).round());
        final b = StringBuffer('{$pos${_base(s)}\\fad(0,$ms)}');
        for (var i = 0; i < words.length; i++) {
          b.write('{\\alpha&HFF&\\fscx40\\fscy40\\t(${i * per},${i * per + 150},\\alpha&H00&\\fscx100\\fscy100)}${esc(words[i])} ');
        }
        body = b.toString();
        break;
      case 'zoomIn':
        body = '{$pos${_base(s)}\\fscx10\\fscy10\\t(0,$ms,\\fscx100\\fscy100)\\fad(${ms ~/ 2},$ms)}$text';
        break;
      case 'slideUp':
        body = '{\\an$an\\move($ax,${ay + (h * 0.15).round()},$ax,$ay,0,$ms)${_base(s)}\\fad(${ms ~/ 2},$ms)}$text';
        break;
      case 'slideLeft':
        body = '{\\an$an\\move(${ax + (w * 0.6).round()},$ay,$ax,$ay,0,$ms)${_base(s)}\\fad(${ms ~/ 2},$ms)}$text';
        break;
      case 'bounce':
        body = '{$pos${_base(s)}\\fscx0\\fscy0\\t(0,${(ms * 0.6).round()},\\fscx125\\fscy125)\\t(${(ms * 0.6).round()},${(ms * 0.8).round()},\\fscx90\\fscy90)\\t(${(ms * 0.8).round()},$ms,\\fscx100\\fscy100)\\fad(0,$ms)}$text';
        break;
      case 'spin':
        body = '{$pos${_base(s)}\\frz-360\\fscx20\\fscy20\\t(0,$ms,\\frz0\\fscx100\\fscy100)\\fad(${ms ~/ 2},$ms)}$text';
        break;
      case 'glow':
        final b = StringBuffer('{$pos${_base(s)}\\fad($ms,$ms)\\blur2');
        for (var t = 0; t < totalMs; t += 1000) {
          b.write('\\t($t,${t + 500},\\blur8\\bord${(s.outline * _scale * 2).toStringAsFixed(1)})\\t(${t + 500},${t + 1000},\\blur2\\bord${(s.outline * _scale).toStringAsFixed(1)})');
        }
        b.write('}$text');
        body = b.toString();
        break;
      case 'scroll':
        final lines = item.text.split('\n').length;
        final textH = (s.size * _scale * 1.3 * lines).round();
        body = '{\\an8\\move(${w ~/ 2},$h,${w ~/ 2},${-textH},0,$totalMs)${_base(s)}}$text';
        break;
      case 'marquee':
        final textW = (s.size * _scale * 0.55 * item.text.length).round();
        body = '{\\an4\\move($w,$ay,${-textW},$ay,0,$totalMs)${_base(s)}}$text';
        break;
      case 'letterWave':
        final chars = item.text.runes.map(String.fromCharCode).toList();
        final b = StringBuffer('{$pos${_base(s)}\\fad($ms,$ms)}');
        for (var i = 0; i < chars.length; i++) {
          final b0 = (i * 60) % 1200;
          final seg = StringBuffer();
          for (var t = b0; t < totalMs; t += 1200) {
            seg.write('\\t($t,${t + 300},\\fscy135)\\t(${t + 300},${t + 600},\\fscy100)');
          }
          b.write('{$seg}${esc(chars[i])}');
        }
        body = b.toString();
        break;
      default:
        body = '{$pos${_base(s)}\\fad($ms,$ms)}$text';
    }
    if (s.gradientTo != null && !item.text.contains('\n')) {
      _gradient(item, st, body, ay, an);
    } else {
      _event(item.start, item.end, st, body, layer: item.layer);
    }
  }

  /// Vertical gradient fill approximated with 8 clipped colour bands.
  void _gradient(TextItem item, String st, String body, int ay, int an) {
    final s = item.style;
    final fs = s.size * _scale;
    final top = an == 2 ? ay - fs * 1.15 : an == 8 ? ay.toDouble() : ay - fs * 0.6;
    final bottom = top + fs * 1.2;
    const bands = 8;
    final c1 = s.color, c2 = s.gradientTo!;
    int ch(String c, int i) => int.parse(c.replaceFirst('#', '').substring(i * 2, i * 2 + 2), radix: 16);
    for (var i = 0; i < bands; i++) {
      final f = i / (bands - 1);
      String mix(int k) => (ch(c1, k) + (ch(c2, k) - ch(c1, k)) * f).round().toRadixString(16).padLeft(2, '0');
      final col = '#${mix(0)}${mix(1)}${mix(2)}';
      final y0 = i == 0 ? 0 : (top + (bottom - top) * i / bands).round();
      final y1 = i == bands - 1 ? h : (top + (bottom - top) * (i + 1) / bands).round();
      final b = body.replaceFirst(_base(s), '\\1c${color(col, s.opacity)}\\clip(0,$y0,$w,$y1)${i > 0 ? '\\bord0\\shad0' : ''}');
      _event(item.start, item.end, st, b, layer: item.layer + (i > 0 ? 1 : 0));
    }
  }

  /// Adds lyrics as lyric video / karaoke / scrolling text / subtitles.
  void addLyrics(LyricsTrack track, TextStyleSpec s, {double songDuration = 0}) {
    track.finalizeTiming(songDuration: songDuration);
    final lines = track.lines.where((l) => l.timed).toList()..sort((a, b) => a.start.compareTo(b.start));
    switch (track.mode) {
      case LyricsMode.subtitles:
      case LyricsMode.lyric:
        for (final l in lines) {
          addText(TextItem(text: l.text, start: l.start, duration: l.end - l.start, style: s, anim: track.mode == LyricsMode.subtitles ? 'none' : track.anim, animDur: 0.35));
        }
        break;
      case LyricsMode.karaoke:
        final st = style(s);
        final mv = (s.marginV * _scale).round();
        final lineH = (s.size * _scale * 1.35).round();
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          final lead = 1.0;
          final show = math.max(i > 0 ? lines[i - 1].start : 0.0, l.start - lead);
          final slot = track.visibleLines >= 2 ? i % 2 : 0;
          final y = s.align == 'top' ? mv + slot * lineH : s.align == 'center' ? h ~/ 2 + (slot == 0 ? -lineH ~/ 2 : lineH ~/ 2) : h - mv - (1 - slot) * lineH;
          final an = s.align == 'top' ? 8 : s.align == 'center' ? 5 : 2;
          final b = StringBuffer('{\\an$an\\pos(${w ~/ 2},$y)\\fad(200,200)}');
          var t = l.start;
          final delayCs = ((l.start - show) * 100).round();
          if (delayCs > 0) b.write('{\\k$delayCs}');
          for (final word in l.words) {
            if (word.start > t + 0.01) b.write('{\\k${((word.start - t) * 100).round()}}');
            final d = ((word.end - word.start) * 100).round().clamp(1, 100000);
            b.write('{\\kf$d}${esc(word.text)} ');
            t = word.end;
          }
          _event(show, l.end + 0.3, st, b.toString());
        }
        break;
      case LyricsMode.scroll:
        final st = style(s);
        final lineH = s.size * _scale * 1.6;
        const window = 4.0; // seconds visible before/after
        for (final l in lines) {
          final st0 = l.start - window, en = l.end + window;
          final y0 = h / 2 + lineH * 3, y1 = h / 2 - lineH * 3;
          final hl = color(s.highlightColor, s.opacity);
          final base = color(s.color, s.opacity * 0.6);
          final a = ((l.start - st0) * 1000).round(), bEnd = ((l.end - st0) * 1000).round();
          _event(st0, en, st,
              '{\\an5\\move(${w ~/ 2},${y0.round()},${w ~/ 2},${y1.round()})\\1c$base\\fad(600,600)\\t($a,${a + 150},\\1c$hl\\fscx110\\fscy110)\\t($bEnd,${bEnd + 200},\\1c$base\\fscx100\\fscy100)}${esc(l.text)}');
        }
        break;
    }
  }

  String build() {
    final b = StringBuffer()
      ..writeln('[Script Info]')
      ..writeln('ScriptType: v4.00+')
      ..writeln('PlayResX: $w')
      ..writeln('PlayResY: $h')
      ..writeln('WrapStyle: 0')
      ..writeln('ScaledBorderAndShadow: yes')
      ..writeln('YCbCr Matrix: TV.709')
      ..writeln()
      ..writeln('[V4+ Styles]')
      ..writeln('Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding');
    _styles.forEach((k, v) => b.writeln(_styleLine(k, v)));
    b
      ..writeln()
      ..writeln('[Events]')
      ..writeln('Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text');
    for (final e in _events) {
      b.writeln(e);
    }
    return b.toString();
  }

  bool get isEmpty => _events.isEmpty;
}
