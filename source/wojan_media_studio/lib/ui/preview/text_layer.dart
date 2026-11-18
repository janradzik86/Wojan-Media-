import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Easing;

import '../../engine/lyrics/lyrics.dart';
import '../../engine/video/model.dart';

/// Registers bundled (OFL) and user-imported fonts with the Flutter engine
/// under the same family names libass uses, so the live preview shows the
/// same typeface as the export.
class PreviewFonts {
  static const bundled = <String, String>{
    'Noto Sans': 'NotoSans.ttf',
    'Anton': 'Anton-Regular.ttf',
    'Bebas Neue': 'BebasNeue-Regular.ttf',
    'Oswald': 'Oswald.ttf',
    'Playfair Display': 'PlayfairDisplay.ttf',
    'Lobster': 'Lobster-Regular.ttf',
    'Pacifico': 'Pacifico-Regular.ttf',
    'Caveat': 'Caveat.ttf',
    'Monoton': 'Monoton-Regular.ttf',
    'Press Start 2P': 'PressStart2P-Regular.ttf',
    'Rubik Glitch': 'RubikGlitch-Regular.ttf',
    'Nosifer': 'Nosifer-Regular.ttf',
  };
  static final Set<String> _loaded = {};
  static final ValueNotifier<int> version = ValueNotifier(0);
  static Future<void>? _all;

  static Future<void> ensure({String? userFontsDir}) => _all ??= _loadAll(userFontsDir);

  static Future<void> _loadAll(String? dir) async {
    for (final e in bundled.entries) {
      try {
        final l = FontLoader(e.key)..addFont(rootBundle.load('assets/fonts/${e.value}'));
        await l.load();
        _loaded.add(e.key);
      } catch (_) {
        try {
          final bytes = await File('assets/fonts/${e.value}').readAsBytes();
          final l = FontLoader(e.key)..addFont(Future.value(ByteData.sublistView(bytes)));
          await l.load();
          _loaded.add(e.key);
        } catch (_) {}
      }
    }
    if (dir != null && Directory(dir).existsSync()) {
      for (final f in Directory(dir).listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        if (!RegExp(r'\.(ttf|otf)$', caseSensitive: false).hasMatch(name)) continue;
        if (bundled.values.contains(name)) continue;
        final fam = name.replaceAll(RegExp(r'\.(ttf|otf)$', caseSensitive: false), '').replaceAll(RegExp(r'[-_](Regular|Bold|Italic)$'), '').replaceAll(RegExp(r'[-_]'), ' ');
        try {
          final l = FontLoader(fam)..addFont(f.readAsBytes().then(ByteData.sublistView));
          await l.load();
          _loaded.add(fam);
        } catch (_) {}
      }
    }
    version.value++;
  }

  static bool has(String family) => _loaded.contains(family);
}

Color _c(String hex, [double a = 1]) {
  var x = hex.replaceFirst('#', '').replaceFirst('0x', '');
  if (x.length == 6) x = 'FF$x';
  final c = Color(int.tryParse(x, radix: 16) ?? 0xFFFFFFFF);
  return c.withValues(alpha: (c.a * a).clamp(0.0, 1.0));
}

/// Draws every text item and the lyrics track of a project at time [t].
/// Geometry mirrors `AssBuilder` (PlayRes = output size, font size scaled by
/// min(W,H)/1080, margins, \an alignment and the same animation timings).
class TextLayer extends StatelessWidget {
  final VideoProject project;
  final double t;
  final double scale; // display px per output px
  final Size size;
  const TextLayer({super.key, required this.project, required this.t, required this.scale, required this.size});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: PreviewFonts.version,
        builder: (_, _, _) => CustomPaint(size: size, painter: _TextPainterAll(project, t, scale)),
      );
}

/// Lyrics with finalised timing (cached per track content).
final Map<String, LyricsTrack> _lyricsCache = {};
LyricsTrack _finalLyrics(LyricsTrack l, double songDuration) {
  final key = '${l.toJson()}|$songDuration';
  return _lyricsCache.putIfAbsent(key, () {
    if (_lyricsCache.length > 8) _lyricsCache.clear();
    final copy = LyricsTrack.fromJson(l.toJson());
    copy.finalizeTiming(songDuration: songDuration);
    return copy;
  });
}

class _Unit {
  final String text;
  final Rect box; // in line layout coordinates
  final int index;
  _Unit(this.text, this.box, this.index);
}

class _TextPainterAll extends CustomPainter {
  final VideoProject p;
  final double t;
  final double k;
  _TextPainterAll(this.p, this.t, this.k);

  @override
  bool shouldRepaint(covariant _TextPainterAll o) => true;

  double get _assScale => math.min(p.width, p.height) / 1080.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(k);
    final items = [...p.texts.where((x) => !x.hidden)]..sort((a, b) => a.layer.compareTo(b.layer));
    for (final it in items) {
      if (t >= it.start && t < it.end) _item(canvas, it, t - it.start);
    }
    final ly = p.lyrics;
    if (ly != null && ly.lines.isNotEmpty) _lyrics(canvas, ly);
    canvas.restore();
  }

  // ---------------------------------------------------------------- styling
  TextStyle _style(TextStyleSpec s, {Color? color, Paint? foreground}) {
    final fs = s.size * _assScale;
    // libass font size is the line height (ascent+descent); Flutter's is
    // the em size. 0.675 was calibrated against libass renders
    // (integration_test/preview_parity_test.dart).
    return TextStyle(
      fontFamily: PreviewFonts.has(s.font) ? s.font : null,
      fontSize: fs * 0.675,
      fontWeight: s.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
      letterSpacing: s.letterSpacing * _assScale,
      color: foreground == null ? (color ?? _c(s.color, s.opacity)) : null,
      foreground: foreground,
      height: 1.18,
    );
  }

  TextPainter _layout(String text, TextStyle st, {double? maxW, TextAlign align = TextAlign.center}) {
    final tp = TextPainter(text: TextSpan(text: text, style: st), textDirection: TextDirection.ltr, textAlign: align);
    tp.layout(maxWidth: maxW ?? (p.width - 80 * 1.0));
    return tp;
  }

  /// Draws text with box / shadow / outline / fill like libass BorderStyle
  /// 1 (outline+shadow) or 3 (opaque box).
  void _draw(Canvas canvas, String text, TextStyleSpec s, Offset topLeft, {double alpha = 1, Color? fill, double outlineMul = 1, double blur = 0, double? maxW, Shader? gradient, TextAlign align = TextAlign.center}) {
    if (alpha <= 0.002 || text.isEmpty) return;
    final op = s.opacity * alpha;
    final bord = s.outline * _assScale * outlineMul;
    final shad = s.shadow * _assScale;
    final base = _layout(text, _style(s), maxW: maxW, align: align);
    if (s.box) {
      final r = Rect.fromLTWH(topLeft.dx - bord, topLeft.dy - bord, base.width + bord * 2, base.height + bord * 2);
      canvas.drawRect(r.shift(Offset(shad, shad)), Paint()..color = _c(s.shadowColor, 0.5 * op));
      canvas.drawRect(r, Paint()..color = _c(s.boxColor, 0.6 * op));
    } else {
      if (shad > 0) {
        final sp = Paint()..color = _c(s.shadowColor, 0.5 * op);
        if (bord > 0) {
          sp
            ..style = PaintingStyle.stroke
            ..strokeWidth = bord * 2
            ..strokeJoin = StrokeJoin.round;
        }
        if (blur > 0) sp.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
        _layout(text, _style(s, foreground: sp), maxW: maxW, align: align).paint(canvas, topLeft + Offset(shad, shad));
        if (bord > 0) _layout(text, _style(s, color: _c(s.shadowColor, 0.5 * op)), maxW: maxW, align: align).paint(canvas, topLeft + Offset(shad, shad));
      }
      if (bord > 0) {
        final op2 = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = bord * 2
          ..strokeJoin = StrokeJoin.round
          ..color = _c(s.outlineColor, op);
        if (blur > 0) op2.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
        _layout(text, _style(s, foreground: op2), maxW: maxW, align: align).paint(canvas, topLeft);
      }
    }
    final fp = Paint()..color = fill?.withValues(alpha: (fill.a * op).clamp(0.0, 1.0)) ?? _c(s.color, op);
    if (gradient != null) fp.shader = gradient;
    _layout(text, _style(s, foreground: fp), maxW: maxW, align: align).paint(canvas, topLeft);
  }

  /// Top-left of a block of [w]×[h] for anchor (ax, ay) with ASS alignment.
  Offset _place(double ax, double ay, int an, double w, double h) {
    final col = (an - 1) % 3; // 0 left, 1 centre, 2 right
    final row = (an - 1) ~/ 3; // 0 bottom, 1 middle, 2 top
    final x = col == 0 ? ax : col == 1 ? ax - w / 2 : ax - w;
    final y = row == 0 ? ay - h : row == 1 ? ay - h / 2 : ay;
    return Offset(x, y);
  }

  (double, double, int) _anchor(TextStyleSpec s, double x, double y) {
    final W = p.width.toDouble(), H = p.height.toDouble();
    if (x >= 0 && y >= 0) return ((x * W).roundToDouble(), (y * H).roundToDouble(), 5);
    final mv = (s.marginV * _assScale).roundToDouble();
    switch (s.align) {
      case 'top':
        return ((W / 2).floorToDouble(), mv, 8);
      case 'center':
        return ((W / 2).floorToDouble(), (H / 2).floorToDouble(), 5);
      default:
        return ((W / 2).floorToDouble(), H - mv, 2);
    }
  }

  double _fad(double lt, double dur, double inS, double outS) {
    var a = 1.0;
    if (inS > 0 && lt < inS) a = lt / inS;
    if (outS > 0 && lt > dur - outS) a = math.min(a, (dur - lt) / outS);
    return a.clamp(0.0, 1.0);
  }

  double _lerpT(double lt, double a, double b) => b <= a ? (lt >= b ? 1 : 0) : ((lt - a) / (b - a)).clamp(0.0, 1.0);

  List<_Unit> _units(TextPainter tp, String text, {required bool words}) {
    final out = <_Unit>[];
    if (words) {
      final re = RegExp(r'\S+');
      var idx = 0;
      for (final m in re.allMatches(text)) {
        final boxes = tp.getBoxesForSelection(TextSelection(baseOffset: m.start, extentOffset: m.end));
        if (boxes.isEmpty) continue;
        var r = boxes.first.toRect();
        for (final b in boxes.skip(1)) {
          r = r.expandToInclude(b.toRect());
        }
        out.add(_Unit(m.group(0)!, r, idx++));
      }
    } else {
      var off = 0, idx = 0;
      for (final r in text.runes) {
        final ch = String.fromCharCode(r);
        final len = ch.length;
        if (ch.trim().isNotEmpty) {
          final boxes = tp.getBoxesForSelection(TextSelection(baseOffset: off, extentOffset: off + len));
          if (boxes.isNotEmpty) out.add(_Unit(ch, boxes.first.toRect(), idx));
        }
        idx++;
        off += len;
      }
    }
    return out;
  }

  // ---------------------------------------------------------------- items
  void _item(Canvas canvas, TextItem it, double lt) {
    final s = it.style;
    final W = p.width.toDouble(), H = p.height.toDouble();
    final dur = it.duration;
    final ad = it.animDur;
    final (ax, ay, an) = _anchor(s, it.x, it.y);
    final tp = _layout(it.text, _style(s));
    final bw = tp.width, bh = tp.height;
    Shader? grad(Offset tl) => s.gradientTo == null ? null : ui.Gradient.linear(tl, tl + Offset(0, bh), [_c(s.color, s.opacity), _c(s.gradientTo!, s.opacity)]);

    void whole({double alpha = 1, double sc = 1, double rot = 0, Offset shift = Offset.zero, double outlineMul = 1, double blur = 0, double? x, double? y, int? anchor}) {
      final tl = _place(x ?? ax, y ?? ay, anchor ?? an, bw, bh) + shift;
      canvas.save();
      if (sc != 1 || rot != 0) {
        // ASS scales/rotates around the alignment point
        final org = Offset(x ?? ax, y ?? ay) + shift;
        canvas.translate(org.dx, org.dy);
        if (rot != 0) canvas.rotate(rot);
        canvas.scale(sc);
        canvas.translate(-org.dx, -org.dy);
      }
      _draw(canvas, it.text, s, tl, alpha: alpha, outlineMul: outlineMul, blur: blur, gradient: grad(tl));
      canvas.restore();
    }

    switch (it.anim) {
      case 'none':
        whole();
        break;
      case 'fade':
        whole(alpha: _fad(lt, dur, ad, ad));
        break;
      case 'zoomIn':
        whole(alpha: _fad(lt, dur, ad / 2, ad), sc: 0.1 + 0.9 * _lerpT(lt, 0, ad));
        break;
      case 'slideUp':
        final f = _lerpT(lt, 0, ad);
        whole(alpha: _fad(lt, dur, ad / 2, ad), shift: Offset(0, (H * 0.15).roundToDouble() * (1 - f)));
        break;
      case 'slideLeft':
        final f = _lerpT(lt, 0, ad);
        whole(alpha: _fad(lt, dur, ad / 2, ad), shift: Offset((W * 0.6).roundToDouble() * (1 - f), 0));
        break;
      case 'bounce':
        double sc;
        if (lt < ad * 0.6) {
          sc = 1.25 * _lerpT(lt, 0, ad * 0.6);
        } else if (lt < ad * 0.8) {
          sc = 1.25 + (0.9 - 1.25) * _lerpT(lt, ad * 0.6, ad * 0.8);
        } else {
          sc = 0.9 + 0.1 * _lerpT(lt, ad * 0.8, ad);
        }
        whole(alpha: _fad(lt, dur, 0, ad), sc: sc);
        break;
      case 'spin':
        final f = _lerpT(lt, 0, ad);
        // \frz is counter-clockwise in ASS; canvas.rotate is clockwise.
        whole(alpha: _fad(lt, dur, ad / 2, ad), sc: 0.2 + 0.8 * f, rot: 2 * math.pi * (1 - f));
        break;
      case 'glow':
        final ph = (lt % 1.0);
        final g = ph < 0.5 ? ph / 0.5 : 1 - (ph - 0.5) / 0.5;
        whole(alpha: _fad(lt, dur, ad, ad), outlineMul: 1 + g, blur: (2 + 6 * g) * _assScale);
        break;
      case 'scroll':
        final lines = it.text.split('\n').length;
        final textH = (s.size * _assScale * 1.3 * lines).roundToDouble();
        final y = H + (-textH - H) * (lt / dur).clamp(0.0, 1.0);
        whole(x: (W / 2).floorToDouble(), y: y, anchor: 8);
        break;
      case 'marquee':
        final textW = (s.size * _assScale * 0.55 * it.text.length).roundToDouble();
        final x = W + (-textW - W) * (lt / dur).clamp(0.0, 1.0);
        whole(x: x, anchor: 4);
        break;
      case 'typewriter':
      case 'wordPop':
      case 'letterWave':
        final words = it.anim == 'wordPop';
        final units = _units(tp, it.text, words: words);
        final tl = _place(ax, ay, an, bw, bh);
        final fadeOut = _fad(lt, dur, it.anim == 'letterWave' ? ad : 0, ad);
        final fadeIn = it.anim == 'letterWave' ? _fad(lt, dur, ad, 0) : 1.0;
        double per;
        if (it.anim == 'typewriter') {
          final n = it.text.runes.length;
          per = math.max(20, (math.min(ad * 3, dur * 0.6) * 1000 / math.max(1, n)).roundToDouble()) / 1000;
        } else if (words) {
          final n = it.text.split(RegExp(r'\s+')).length;
          per = math.max(80, (math.min(dur * 0.6, n * 0.35) * 1000 / math.max(1, n)).roundToDouble()) / 1000;
        } else {
          per = 0;
        }
        for (final u in units) {
          double a = fadeOut * fadeIn, sc = 1, sy = 1;
          if (it.anim == 'typewriter') {
            if (lt < u.index * per) continue;
          } else if (words) {
            final st = u.index * per;
            if (lt < st) continue;
            final f = _lerpT(lt, st, st + 0.15);
            a *= f;
            sc = 0.4 + 0.6 * f;
          } else {
            // \fscy wave: 100→135→100 every 1.2 s, char offset 60 ms
            final b0 = ((u.index * 60) % 1200) / 1000;
            if (lt >= b0) {
              final ph = (lt - b0) % 1.2;
              sy = ph < 0.3 ? 1 + 0.35 * ph / 0.3 : ph < 0.6 ? 1.35 - 0.35 * (ph - 0.3) / 0.3 : 1;
            }
          }
          final pos = tl + u.box.topLeft;
          canvas.save();
          final org = pos + Offset(u.box.width / 2, u.box.height);
          canvas.translate(org.dx, org.dy);
          canvas.scale(sc, sc * sy);
          canvas.translate(-org.dx, -org.dy);
          _draw(canvas, u.text, s, pos, alpha: a, maxW: double.infinity, gradient: grad(tl));
          canvas.restore();
        }
        break;
      default:
        whole(alpha: _fad(lt, dur, ad, ad));
    }
  }

  // ---------------------------------------------------------------- lyrics
  void _lyrics(Canvas canvas, LyricsTrack raw) {
    final total = p.duration;
    final track = _finalLyrics(raw, total);
    final s = TextStyleSpec.fromJson(raw.style);
    final lines = track.lines.where((l) => l.timed).toList()..sort((a, b) => a.start.compareTo(b.start));
    final W = p.width.toDouble(), H = p.height.toDouble();
    switch (track.mode) {
      case LyricsMode.subtitles:
      case LyricsMode.lyric:
        for (final l in lines) {
          if (t >= l.start && t < l.end) {
            _item(canvas, TextItem(text: l.text, start: l.start, duration: l.end - l.start, style: s, anim: track.mode == LyricsMode.subtitles ? 'none' : track.anim, animDur: 0.35), t - l.start);
          }
        }
        break;
      case LyricsMode.karaoke:
        final mv = (s.marginV * _assScale).roundToDouble();
        final lineH = (s.size * _assScale * 1.35).roundToDouble();
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          final show = math.max(i > 0 ? lines[i - 1].start : 0.0, l.start - 1.0);
          final end = l.end + 0.3;
          if (t < show || t >= end) continue;
          final slot = track.visibleLines >= 2 ? i % 2 : 0;
          final y = s.align == 'top' ? mv + slot * lineH : s.align == 'center' ? (H / 2).floorToDouble() + (slot == 0 ? -lineH / 2 : lineH / 2) : H - mv - (1 - slot) * lineH;
          final an = s.align == 'top' ? 8 : s.align == 'center' ? 5 : 2;
          final alpha = _fad(t - show, end - show, 0.2, 0.2);
          final text = l.words.isEmpty ? l.text : l.words.map((w) => w.text).join(' ');
          final tp = _layout(text, _style(s));
          final tl = _place((W / 2).floorToDouble(), y, an, tp.width, tp.height);
          // base (not yet sung) colour, then the sung part clipped (\kf sweep)
          _draw(canvas, text, s, tl, alpha: alpha);
          if (l.words.isEmpty) continue;
          final units = _units(tp, text, words: true);
          var sweepX = tl.dx;
          for (var w = 0; w < l.words.length && w < units.length; w++) {
            final word = l.words[w];
            final r = units[w].box.shift(tl);
            if (t >= word.end) {
              sweepX = r.right + 1;
            } else if (t > word.start) {
              sweepX = r.left + r.width * ((t - word.start) / math.max(0.01, word.end - word.start));
              break;
            } else {
              break;
            }
          }
          if (sweepX > tl.dx) {
            canvas.save();
            canvas.clipRect(Rect.fromLTRB(0, 0, sweepX, H));
            _draw(canvas, text, s, tl, alpha: alpha, fill: _c(s.highlightColor), outlineMul: 1);
            canvas.restore();
          }
        }
        break;
      case LyricsMode.scroll:
        final lineH = s.size * _assScale * 1.6;
        const window = 4.0;
        for (final l in lines) {
          final st0 = l.start - window, en = l.end + window;
          if (t < st0 || t >= en) continue;
          final y0 = H / 2 + lineH * 3, y1 = H / 2 - lineH * 3;
          final f = ((t - st0) / (en - st0)).clamp(0.0, 1.0);
          final y = y0 + (y1 - y0) * f;
          final lt = t - st0;
          final a = l.start - st0, bEnd = l.end - st0;
          var hl = 0.0;
          if (lt >= a) hl = _lerpT(lt, a, a + 0.15);
          if (lt >= bEnd) hl = 1 - _lerpT(lt, bEnd, bEnd + 0.2);
          final col = Color.lerp(_c(s.color, 0.6), _c(s.highlightColor), hl)!;
          final sc = 1 + 0.1 * hl;
          final tp = _layout(l.text, _style(s));
          final tl = _place((W / 2).floorToDouble(), y, 5, tp.width, tp.height);
          canvas.save();
          canvas.translate(W / 2, y);
          canvas.scale(sc);
          canvas.translate(-W / 2, -y);
          _draw(canvas, l.text, s, tl, alpha: _fad(lt, en - st0, 0.6, 0.6), fill: col);
          canvas.restore();
        }
        break;
    }
  }
}
