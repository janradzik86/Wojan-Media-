import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart' hide Easing;

import '../../engine/video/model.dart';
import '../../engine/video/vfx_library.dart';
import '../../engine/dsp/analysis.dart';
import 'preview_controller.dart';

// ---------------------------------------------------------------------------
// Shared resources (generated once, reused every frame)
// ---------------------------------------------------------------------------

/// Cache of decoded effect textures (`assets/fx/*.png`) and procedural
/// sprites used by the live preview.
class FxImages {
  static final Map<String, ui.Image> _img = {};
  static final Map<String, Future<ui.Image?>> _loading = {};
  static final ValueNotifier<int> version = ValueNotifier(0);

  static ui.Image? get(String file) {
    final i = _img[file];
    if (i != null) return i;
    _loading.putIfAbsent(file, () => _load(file));
    return null;
  }

  static Future<ui.Image?> _load(String file) async {
    try {
      final data = await rootBundle.load('assets/fx/$file');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      final f = await codec.getNextFrame();
      _img[file] = f.image;
      version.value++;
      return f.image;
    } catch (_) {
      // Fallback for tools/tests running from the source tree.
      try {
        final bytes = await File('${FxAssets.dir}/$file').readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final f = await codec.getNextFrame();
        _img[file] = f.image;
        version.value++;
        return f.image;
      } catch (_) {
        return null;
      }
    }
  }

  static ui.Image? _dot, _streak, _noise;

  /// Soft round sprite (white, radial falloff) for particles / bokeh.
  static ui.Image get dot => _dot ??= _make(64, 64, (c) {
        c.drawCircle(const Offset(32, 32), 32, Paint()..shader = ui.Gradient.radial(const Offset(32, 32), 32, [Colors.white, Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0)], [0, 0.35, 1]));
      });

  /// Thin vertical streak (rain).
  static ui.Image get streak => _streak ??= _make(8, 64, (c) {
        c.drawRect(const Rect.fromLTWH(2, 0, 4, 64), Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(0, 64), [Colors.white.withValues(alpha: 0), Colors.white, Colors.white.withValues(alpha: 0)], [0, 0.6, 1]));
      });

  /// Grey film-grain noise tile.
  static ui.Image get noise => _noise ??= () {
        final r = math.Random(7);
        final rec = ui.PictureRecorder();
        final c = Canvas(rec);
        final p = Paint();
        for (var y = 0; y < 128; y += 2) {
          for (var x = 0; x < 128; x += 2) {
            final v = r.nextInt(256);
            p.color = Color.fromARGB(255, v, v, v);
            c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 2, 2), p);
          }
        }
        return rec.endRecording().toImageSync(128, 128);
      }();

  static ui.Image _make(int w, int h, void Function(Canvas c) draw) {
    final rec = ui.PictureRecorder();
    draw(Canvas(rec));
    return rec.endRecording().toImageSync(w, h);
  }
}

/// What effect painters need from the timeline (implemented by
/// [PreviewController]; effect thumbnails use [FxThumbSource]).
abstract class FxSource {
  VideoProject get project;
  double get duration;
  AudioAnalysis? get music;
  double get musicOffset;
  double bassAt(double t);
  double energyAt(double t);
}

/// Stand-alone source for animated effect thumbnails (synthetic 120 BPM
/// pulse instead of music).
class FxThumbSource implements FxSource {
  @override
  final VideoProject project;
  FxThumbSource(this.project);
  @override
  double get duration => 4;
  @override
  AudioAnalysis? get music => null;
  @override
  double get musicOffset => 0;
  @override
  double bassAt(double t) => math.exp(-((t % 0.5)) * 6);
  @override
  double energyAt(double t) => 0.5 + 0.5 * math.exp(-((t % 0.5)) * 4);
}

Color _hex(String h, [double alpha = 1]) {
  var x = h.replaceFirst('#', '').replaceFirst('0x', '');
  if (x.length == 6) x = 'FF$x';
  final c = Color(int.tryParse(x, radix: 16) ?? 0xFFFFFFFF);
  return c.withValues(alpha: (c.a * alpha).clamp(0.0, 1.0));
}

double _frac(double v) => v - v.floorToDouble();

/// Beat times on the timeline (music analysis or a 120 BPM fallback grid,
/// exactly like the renderer).
List<double> previewBeats(FxSource c) {
  final m = c.music;
  if (m != null && m.beats.isNotEmpty) return [for (final b in m.beats) b + c.musicOffset];
  return fallbackBeats(c.duration + 1);
}

double previewBeatEnv(List<double> beats, double t, double decay) {
  var lo = 0, hi = beats.length - 1, idx = -1;
  while (lo <= hi) {
    final m = (lo + hi) >> 1;
    if (beats[m] <= t) {
      idx = m;
      lo = m + 1;
    } else {
      hi = m - 1;
    }
  }
  return idx < 0 ? 0 : math.exp(-(t - beats[idx]) * decay);
}

/// Beat envelope using only real music beats (0 without analysis) – used by
/// effects whose FFmpeg version is driven by `VfxContext.beatEnv`.
double _musicBeatEnv(FxSource c, double t, double decay) {
  final m = c.music;
  if (m == null || m.beats.isEmpty) return 0;
  return previewBeatEnv([for (final b in m.beats) b + c.musicOffset], t, decay);
}

/// Lightning flash times (same formula as `applyVfx` 'lightning').
List<double> _lightningTimes(FxSource c, bool react, double dur) {
  final m = c.music;
  if (react && m != null) {
    return [for (final t in m.onsets) if (m.valueAt(m.onsetEnv, t) > 0.8) t + c.musicOffset];
  }
  return [for (var t = 1.3; t < dur; t += 3.7 + (t * 7) % 2.1) t];
}

bool _within(List<double> ts, double t, double len, {double offset = 0}) {
  for (final x in ts) {
    if (t >= x + offset && t < x + offset + len) return true;
    if (x + offset > t) break;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Base-picture effects (wrap the composited track; mirrors FFmpeg filters)
// ---------------------------------------------------------------------------

List<double> _satMatrix(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  return [
    lr * (1 - s) + s, lg * (1 - s), lb * (1 - s), 0, 0,
    lr * (1 - s), lg * (1 - s) + s, lb * (1 - s), 0, 0,
    lr * (1 - s), lg * (1 - s), lb * (1 - s) + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

List<double> _mul(List<double> a, List<double> b) {
  // 5x4 colour matrices composed as a∘b (apply b first).
  final out = List<double>.filled(20, 0);
  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 5; c++) {
      var v = c == 4 ? a[r * 5 + 4] : 0.0;
      for (var k = 0; k < 4; k++) {
        v += a[r * 5 + k] * b[k * 5 + c];
      }
      out[r * 5 + c] = v;
    }
  }
  return out;
}

List<double> _brightContrast(double brightness, double contrast) {
  final o = 255 * (brightness + 0.5 * (1 - contrast));
  return [contrast, 0, 0, 0, o, 0, contrast, 0, 0, o, 0, 0, contrast, 0, o, 0, 0, 0, 1, 0];
}

List<double> _hueRotate(double deg) {
  final a = deg * math.pi / 180, c = math.cos(a), s = math.sin(a);
  return [
    0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928, 0, 0,
    0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283, 0, 0,
    0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

const _sepia = <double>[.393, .769, .189, 0, 0, .349, .686, .168, 0, 0, .272, .534, .131, 0, 0, 0, 0, 0, 1, 0];

bool _active(VfxItem fx, double t) => t >= fx.start && (fx.duration <= 0 || t < fx.start + fx.duration);

/// Effects of [p] that modify the picture itself (camera, colour, geometry)
/// are applied here around the base track, in the order of the project.
Widget wrapBaseVfx(Widget base, VideoProject p, double t, FxSource c, Size size) {
  final scale = size.width / p.width;
  final beats = previewBeats(c);
  for (final fx in p.vfx) {
    if (!_active(fx, t)) continue;
    final i = fx.intensity.clamp(0.0, 1.0);
    switch (fx.type) {
      case 'zoompunch':
      case 'heartbeat':
        final hb = fx.type == 'heartbeat';
        final amp = (hb ? 0.05 : 0.08) + (hb ? 0.05 : 0.12) * i;
        final v = hb ? heartbeatEnvelope(t) : previewBeatEnv(beats, t, 7);
        // the renderer overlays a scaled copy centred over the picture
        base = Transform.scale(scale: 1 + amp * v, child: base);
        break;
      case 'shake':
        final pad = (math.min(p.width, p.height) * (0.02 + 0.05 * i)).round() ~/ 2 * 2;
        final v = previewBeatEnv(beats, t, 6) * (0.75 + 0.25 * math.sin(t * 53)).abs();
        final dx = pad * v * 0.9 * math.sin(v * 91), dy = pad * v * 0.9 * math.cos(v * 57);
        final k = (p.width + pad * 2) / p.width;
        base = Transform.translate(offset: Offset(-dx * scale, -dy * scale), child: Transform.scale(scale: k, child: base));
        break;
      case 'bassglow':
        final v = c.bassAt(t).clamp(0.0, 1.0);
        base = ColorFiltered(colorFilter: ColorFilter.matrix(_mul(_brightContrast(v * 0.18 * (0.3 + i), 1), _satMatrix(1 + v * 0.5 * i))), child: base);
        break;
      case 'retro':
        base = ColorFiltered(colorFilter: ColorFilter.matrix(_mul(_satMatrix(0.85), const [0.9, 0.1, 0, 0, 18, 0.05, 0.85, 0.05, 0, 10, 0, 0.15, 0.7, 0, 0, 0, 0, 0, 1, 0])), child: base);
        break;
      case 'oldfilm':
        base = ColorFiltered(colorFilter: ColorFilter.matrix(_mul(_brightContrast(0.04 * math.sin(t * 47) * i, 1), _sepia)), child: base);
        break;
      case 'vhs':
        base = ColorFiltered(colorFilter: ColorFilter.matrix(_mul(_brightContrast(0, 1.05), _satMatrix(1.25))), child: ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 0.7 * scale, sigmaY: 0.7 * scale), child: base));
        break;
      case 'cinematic':
        base = ColorFiltered(colorFilter: ColorFilter.matrix(_mul(_brightContrast(0, 1.08), const [0.92, 0, 0, 0, 10, 0, 1, 0, 0, 0, 0, 0, 1.1, 0, 8, 0, 0, 0, 1, 0])), child: base);
        break;
      case 'blur':
        final s = (2 + 18 * i) * scale;
        base = ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: s, sigmaY: s, tileMode: TileMode.clamp), child: base);
        break;
      case 'neon':
        final dark = ColorFiltered(colorFilter: ColorFilter.matrix(_mul(_brightContrast(-0.25, 1), _satMatrix(0.6))), child: base);
        final glow = Opacity(
          opacity: 0.6 + 0.4 * i * 0.5,
          child: ColorFiltered(colorFilter: ColorFilter.matrix(_mul(_hueRotate(t * 40), _mul(_brightContrast(0.05, 1.9), _satMatrix(2.2)))), child: base),
        );
        base = Stack(fit: StackFit.expand, children: [dark, glow]);
        break;
      case 'rgbsplit':
      case 'glitch':
        final react = fx.reactive && c.music != null;
        double sh;
        if (fx.type == 'rgbsplit') {
          sh = (3 + 10 * i).roundToDouble();
        } else {
          final times = react ? [for (final b in beats) b] : [for (var x = 0.4; x < c.duration; x += 1.6 + (x * 13) % 1.3) x];
          if (!_within(times, t, 0.12)) continue;
          sh = (8 + 20 * i).roundToDouble();
        }
        final d = sh * scale;
        // Shifted channel fringes: pure red / blue whose opacity follows the
        // channel value (no darkening of the picture).
        const rOnly = <double>[0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.55, 0, 0, 0, 0];
        const bOnly = <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0.55, 0, 0];
        final strips = <Widget>[];
        if (fx.type == 'glitch') {
          // horizontal displaced bands like the noise/hue burst
          final r = math.Random((t * 25).floor());
          for (var k = 0; k < 5; k++) {
            final y = r.nextDouble() * size.height, h = (0.02 + r.nextDouble() * 0.08) * size.height;
            strips.add(Positioned(left: 0, right: 0, top: y, height: h, child: ClipRect(child: OverflowBox(alignment: Alignment.topLeft, minHeight: size.height, maxHeight: size.height, child: Transform.translate(offset: Offset((r.nextDouble() - 0.5) * 60 * scale, -y), child: SizedBox(width: size.width, height: size.height, child: base))))));
          }
        }
        base = Stack(fit: StackFit.expand, children: [
          base,
          Transform.translate(offset: Offset(d, 0), child: ColorFiltered(colorFilter: const ColorFilter.matrix(rOnly), child: base)),
          Transform.translate(offset: Offset(-d, 0), child: ColorFiltered(colorFilter: const ColorFilter.matrix(bOnly), child: base)),
          ...strips,
        ]);
        break;
      case 'tilt3d':
        final d = 0.04 + 0.08 * i;
        final ang = math.atan(d * 4 * math.sin(t * 1.3)) * 0.6;
        base = Transform(alignment: Alignment.center, transform: Matrix4.identity()..setEntry(3, 2, 0.0012 / scale.clamp(0.2, 4))..rotateX(ang), child: base);
        break;
      case 'mirror':
        final b0 = base;
        base = Stack(fit: StackFit.expand, children: [
          b0,
          Positioned(
            left: size.width / 2,
            top: 0,
            width: size.width / 2,
            height: size.height,
            child: ClipRect(child: OverflowBox(alignment: Alignment.topRight, minWidth: size.width, maxWidth: size.width, child: Transform.flip(flipX: true, child: SizedBox(width: size.width, height: size.height, child: b0)))),
          ),
        ]);
        break;
      case 'kaleido':
        final b0 = base;
        Widget q() => ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: size.width,
                maxWidth: size.width,
                minHeight: size.height,
                maxHeight: size.height,
                child: SizedBox(width: size.width, height: size.height, child: b0),
              ),
            );
        Widget quad(bool fx0, bool fy0) => Transform.flip(flipX: fx0, flipY: fy0, child: q());
        final w2 = size.width / 2, h2 = size.height / 2;
        base = Stack(children: [
          Positioned(left: 0, top: 0, width: w2, height: h2, child: quad(false, false)),
          Positioned(left: w2, top: 0, width: w2, height: h2, child: quad(true, false)),
          Positioned(left: 0, top: h2, width: w2, height: h2, child: quad(false, true)),
          Positioned(left: w2, top: h2, width: w2, height: h2, child: quad(true, true)),
        ]);
        break;
      case 'pixelate':
        final px = (8 + 40 * i) * scale;
        final k = 1 / px.clamp(1.0, 200.0);
        base = Transform.scale(
          scale: 1 / k,
          alignment: Alignment.topLeft,
          filterQuality: FilterQuality.none,
          child: Transform.scale(scale: k, alignment: Alignment.topLeft, filterQuality: FilterQuality.none, child: base),
        );
        break;
    }
  }
  return base;
}

// ---------------------------------------------------------------------------
// Overlay effects
// ---------------------------------------------------------------------------

/// Overlay part of one effect (particles, light, flashes, frames, grain).
class VfxLayer extends StatelessWidget {
  final VfxItem fx;
  final double t;
  final FxSource c;
  final Size size;
  const VfxLayer({super.key, required this.fx, required this.t, required this.c, required this.size});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: FxImages.version,
        builder: (_, _, _) => CustomPaint(size: size, painter: _VfxPainter(fx, t, c)),
      );
}

class _Particle {
  final double x, y, s, a, ph;
  const _Particle(this.x, this.y, this.s, this.a, this.ph);
}

final Map<String, List<_Particle>> _particleCache = {};

List<_Particle> _particles(String key, int n, int seed, {double minS = 0.5, double maxS = 1}) => _particleCache.putIfAbsent('$key/$n/$seed', () {
      final r = math.Random(seed);
      return [for (var k = 0; k < n; k++) _Particle(r.nextDouble(), r.nextDouble(), minS + (maxS - minS) * r.nextDouble(), 0.5 + 0.5 * r.nextDouble(), r.nextDouble() * 6.283)];
    });

class _VfxPainter extends CustomPainter {
  final VfxItem fx;
  final double t;
  final FxSource c;
  _VfxPainter(this.fx, this.t, this.c);

  VideoProject get p => c.project;

  @override
  bool shouldRepaint(covariant _VfxPainter o) => true;

  /// Opacity multiplier for music reactive particle effects (mirrors aaCmd).
  double _react(double base, {bool beats = false}) {
    if (!fx.reactive || c.music == null) return base;
    final v = beats ? math.max(_musicBeatEnv(c, t, 5), c.energyAt(t) * 0.5) : c.energyAt(t);
    return base * (0.25 + 0.75 * v.clamp(0.0, 1.0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final W = p.width.toDouble(), H = p.height.toDouble();
    final k = size.width / W;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(k);
    _paint(canvas, W, H);
    canvas.restore();
  }

  /// Soft dot particles scrolling with per-frame velocities identical to
  /// the FFmpeg `scroll` filter (content moves by -h/-v per frame).
  void _dots(Canvas canvas, double W, double H, {required double density, required int cell, required double blur, required double vx, required double vy, required Color color, required double opacity, int seed = 1, double stretch = 0, double gain = 4}) {
    final cells = (W / cell).ceil() * (H / cell).ceil();
    final n = (density * cells).clamp(8, 900).round();
    final ps = _particles('dots', n, seed);
    final fps = p.fps;
    final ox = -vx * fps * t, oy = -vy * fps * t;
    final r = math.max(1.0, cell * 0.5 + blur * 1.2);
    final xf = <RSTransform>[], rects = <Rect>[], cols = <Color>[];
    final img = stretch > 0 ? FxImages.streak : FxImages.dot;
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final brightness = (gain / 4).clamp(0.5, 1.5);
    for (final q in ps) {
      final x = _frac(q.x + ox) * W, y = _frac(q.y + oy) * H;
      final sz = r * 2 * (0.7 + 0.6 * q.s);
      final sc = stretch > 0 ? (stretch * 6) / img.height : sz / img.width;
      xf.add(RSTransform.fromComponents(rotation: 0, scale: sc, anchorX: img.width / 2, anchorY: img.height / 2, translateX: x, translateY: y));
      rects.add(src);
      cols.add(color.withValues(alpha: (opacity * q.a * brightness).clamp(0.0, 1.0)));
    }
    canvas.drawAtlas(img, xf, rects, cols, BlendMode.modulate, null, Paint()..filterQuality = FilterQuality.low);
  }

  void _clouds(Canvas canvas, double W, double H, {required double vx, required double vy, required Color color, required double opacity, int seed = 3, int grid = 24}) {
    final ps = _particles('cloud', 26, seed, minS: 0.6, maxS: 1.4);
    final fps = p.fps;
    final ox = -vx * fps * t, oy = -vy * fps * t;
    final r = math.max(W, H) * 0.22 * (grid / 24);
    final paint = Paint()..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.45);
    for (final q in ps) {
      final x = _frac(q.x + ox) * W, y = _frac(q.y + oy) * H;
      paint.color = color.withValues(alpha: (opacity * q.a * 0.3).clamp(0.0, 1.0));
      for (final dx in const [-1.0, 0.0, 1.0]) {
        for (final dy in const [-1.0, 0.0, 1.0]) {
          final cx = x + dx * W, cy = y + dy * H;
          if (cx < -r * 2 || cx > W + r * 2 || cy < -r * 2 || cy > H + r * 2) continue;
          canvas.drawCircle(Offset(cx, cy), r * q.s, paint);
        }
      }
    }
  }

  void _flash(Canvas canvas, double W, double H, double amount, {Color color = Colors.white}) {
    if (amount <= 0) return;
    canvas.drawRect(Rect.fromLTWH(0, 0, W, H), Paint()
      ..color = color.withValues(alpha: amount.clamp(0.0, 1.0))
      ..blendMode = BlendMode.screen);
  }

  void _grain(Canvas canvas, double W, double H, double amount) {
    final img = FxImages.noise;
    final r = math.Random((t * p.fps).floor());
    final paint = Paint()
      ..shader = ImageShader(img, TileMode.repeated, TileMode.repeated, (Matrix4.identity()..translateByDouble(r.nextDouble() * 128, r.nextDouble() * 128, 0, 1)).storage)
      ..color = Colors.white.withValues(alpha: amount)
      ..blendMode = BlendMode.overlay;
    canvas.drawRect(Rect.fromLTWH(0, 0, W, H), paint);
  }

  void _vignette(Canvas canvas, double W, double H, double angle) {
    // FFmpeg vignette angle → darkening strength of corners
    final s = (math.sin(angle.clamp(0.0, 1.5)) * 1.15).clamp(0.0, 1.0);
    final rect = Rect.fromLTWH(0, 0, W, H);
    canvas.drawRect(rect, Paint()..shader = ui.Gradient.radial(Offset(W / 2, H / 2), math.sqrt(W * W + H * H) / 2, [Colors.transparent, Colors.black.withValues(alpha: s)], [0.35, 1]));
  }

  void _texture(Canvas canvas, double W, double H, ParticleTex pt, double i) {
    final img = FxImages.get(pt.file);
    if (img == null) return;
    final (n, _, tw, th) = texTiling(W.round(), H.round());
    var op = (pt.opacity * (0.45 + 0.55 * i)).clamp(0.0, 1.0);
    if (fx.reactive && c.music != null) {
      op *= 0.3 + 0.7 * math.max(_musicBeatEnv(c, t, 4), c.energyAt(t) * 0.7).clamp(0.0, 1.0);
    }
    final fps = p.fps;
    // frame-quantised like the renderer
    final fr = (t * fps).floorToDouble() / fps;
    final ox = _frac(pt.vx * fr) * tw, oy = _frac(pt.vy * fr) * th;
    final sway = pt.sway > 0 ? (pt.sway * W).roundToDouble() * math.sin(t * 0.9) : 0.0;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: op)
      ..filterQuality = FilterQuality.medium;
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final tileW = tw / n;
    for (var yy = -1; yy <= 0; yy++) {
      for (var xx = -1; xx <= 0; xx++) {
        for (var k = 0; k < n; k++) {
          final x = ox + xx * tw + k * tileW + sway, y = oy + yy * th;
          final dst = Rect.fromLTWH(x, y, tileW, th.toDouble());
          if (dst.right < 0 || dst.left > W || dst.bottom < 0 || dst.top > H) continue;
          canvas.drawImageRect(img, src, dst, paint);
        }
      }
    }
    // rightmost wrap (sway can reveal the area right of the last tile)
    if (sway < 0 || ox > 0) {
      for (var yy = -1; yy <= 0; yy++) {
        for (var k = 0; k < n; k++) {
          final x = ox + tw + k * tileW + sway, y = oy + yy * th;
          final dst = Rect.fromLTWH(x, y, tileW, th.toDouble());
          if (dst.left > W || dst.bottom < 0 || dst.top > H) continue;
          canvas.drawImageRect(img, src, dst, paint);
        }
      }
    }
  }

  void _sprite(Canvas canvas, double W, double H, String file, double i) {
    final img = FxImages.get(file);
    if (img == null) return;
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final m = math.min(W, H);
    final tint = fx.color != '#FFFFFF' ? _hex(fx.color) : null;
    Paint paint(double a) {
      final pp = Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Colors.white.withValues(alpha: a.clamp(0.0, 1.0));
      if (tint != null) pp.colorFilter = ColorFilter.matrix([tint.r, 0, 0, 0, 0, 0, tint.g, 0, 0, 0, 0, 0, tint.b, 0, 0, 0, 0, 0, a.clamp(0.0, 1.0), 0]);
      return pp;
    }

    switch (fx.type) {
      case 'shockwave':
      case 'lightburst':
        final ring = fx.type == 'shockwave';
        final base0 = ring ? m * 0.25 : m * 0.6;
        final grow = ring ? m * 1.6 : m * 0.9;
        final beats = previewBeats(c);
        // renderer samples the envelope at min(fps,30) Hz
        final rate = math.min(p.fps, 30.0);
        final tq = (t * rate).floorToDouble() / rate;
        final v = previewBeatEnv(beats, tq, ring ? 3.5 : 5);
        final sz = (base0 + grow * (1 - v)).round() ~/ 2 * 2;
        final a = v * (0.5 + 0.5 * i);
        canvas.drawImageRect(img, src, Rect.fromCenter(center: Offset(W / 2, H / 2), width: sz.toDouble(), height: sz.toDouble()), paint(a));
        break;
      case 'godrays':
        final d = (math.sqrt(W * W + H * H)).roundToDouble();
        canvas.save();
        canvas.translate(W / 2, H / 2 + H * 0.25); // crop window is shifted up by H/4 in the renderer
        canvas.rotate(t * 0.12);
        canvas.drawImageRect(img, src, Rect.fromCenter(center: Offset.zero, width: d, height: d), paint(0.5 + 0.5 * i));
        canvas.restore();
        break;
      case 'speedlines':
        final d = (math.sqrt(W * W + H * H) * 1.05).roundToDouble();
        final n = (t * p.fps).floor();
        canvas.save();
        canvas.translate(W / 2, H / 2);
        canvas.rotate((n ~/ 3) * 2.39996);
        canvas.drawImageRect(img, src, Rect.fromCenter(center: Offset.zero, width: d, height: d), paint(0.55 + 0.45 * i));
        canvas.restore();
        break;
      default: // halftone, aura – square scaled to max(W,H), centre crop (FFmpeg crop default)
        final d = math.max(W, H);
        canvas.drawImageRect(img, src, Rect.fromLTWH(((W - d) / 2).floorToDouble(), ((H - d) / 2).floorToDouble(), d, d), paint(0.5 + 0.5 * i));
    }
  }

  void _paint(Canvas canvas, double W, double H) {
    final i = fx.intensity.clamp(0.0, 1.0);
    final col = fx.color;
    Color pick(String def) => _hex(col == '#FFFFFF' ? def : col);
    final pt = particleTextures[fx.type];
    if (pt != null) return _texture(canvas, W, H, pt, i);
    final fr = frameTextures[fx.type];
    if (fr != null) {
      final img = FxImages.get(fr);
      if (img != null) {
        canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), Rect.fromLTWH(0, 0, W, H), Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Colors.white.withValues(alpha: 0.6 + 0.4 * i));
      }
      return;
    }
    final sp = spriteEffects[fx.type];
    if (sp != null) return _sprite(canvas, W, H, sp, i);
    final react = fx.reactive && c.music != null;
    switch (fx.type) {
      case 'snow':
        _dots(canvas, W, H, density: 0.002 + 0.006 * i, cell: 4, blur: 2.5, vx: 0.0004, vy: -0.0025, color: _hex(col), opacity: _react(0.9), seed: 11);
        _dots(canvas, W, H, density: 0.0015 + 0.004 * i, cell: 7, blur: 4, vx: -0.0003, vy: -0.0045, color: _hex(col), opacity: _react(0.9), seed: 7, gain: 3);
        break;
      case 'rain':
        _dots(canvas, W, H, density: 0.004 + 0.01 * i, cell: 2, blur: 0.3, vx: 0.002, vy: -0.03, color: pick('#CFE3FF'), opacity: _react(0.55), seed: 5, stretch: 9, gain: 6);
        break;
      case 'sparks':
        _dots(canvas, W, H, density: 0.002 + 0.005 * i, cell: 3, blur: 1.2, vx: 0.001, vy: 0.006, color: pick('#FF9A2E'), opacity: _react(1, beats: true), seed: 9, gain: 6);
        break;
      case 'dust':
        _dots(canvas, W, H, density: 0.002 + 0.004 * i, cell: 2, blur: 0.8, vx: 0.0006, vy: 0.0004, color: pick('#E8D9B8'), opacity: _react(0.6), seed: 13, gain: 3);
        break;
      case 'ash':
        _dots(canvas, W, H, density: 0.001 + 0.003 * i, cell: 6, blur: 2, vx: 0.0008, vy: -0.0012, color: pick('#9A9A9A'), opacity: _react(0.8), seed: 21, gain: 2.5);
        break;
      case 'particles':
        _dots(canvas, W, H, density: 0.0008 + 0.002 * i, cell: 14, blur: 9, vx: 0.0005, vy: 0.0008, color: pick('#FFD27A'), opacity: _react(0.7, beats: true), seed: 17, gain: 2.2);
        break;
      case 'fog':
        _clouds(canvas, W, H, vx: 0.0015, vy: 0, color: pick('#DDE3EA'), opacity: 0.25 + 0.45 * i, seed: 4);
        break;
      case 'smoke':
        _clouds(canvas, W, H, vx: 0.0005, vy: 0.003, color: pick('#8C8C8C'), opacity: 0.3 + 0.5 * i, seed: 8, grid: 18);
        break;
      case 'fire':
        // flickering flame body rising from the bottom (noise × vertical mask)
        final op = 0.6 + 0.4 * i;
        final ps = _particles('fire', 130, 2, minS: 0.6, maxS: 1.4);
        final paint = Paint()..blendMode = BlendMode.screen;
        final fps = p.fps;
        for (final q in ps) {
          final y = _frac(q.y - 0.02 * fps * t);
          final yy = y * H;
          final m = math.pow(((yy / H - 0.45) / 0.55).clamp(0.0, 1.0), 1.6).toDouble();
          if (m <= 0.01) continue;
          final r = W * 0.13 * q.s * (0.6 + m);
          paint
            ..shader = ui.Gradient.radial(Offset(q.x * W, yy), r, [Color.fromARGB((255 * op * math.min(1.0, m * 1.6) * (0.6 + 0.4 * q.a)).round().clamp(0, 255), 255, (90 + 100 * (1 - yy / H)).round().clamp(0, 255), 20), const Color(0x00FF5A14)])
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.25);
          canvas.drawCircle(Offset(q.x * W + math.sin(t * 7 + q.ph) * r * 0.2, yy), r, paint);
        }
        break;
      case 'lightning':
        final times = _lightningTimes(c, react, c.duration);
        if (_within(times, t, 0.07)) {
          _flash(canvas, W, H, 0.35 + 0.4 * i, color: const Color(0xFFE6EEFF));
        } else if (_within(times, t, 0.05, offset: 0.12)) {
          _flash(canvas, W, H, 0.2 * i + 0.1);
        }
        break;
      case 'beatflash':
        final beats = c.music != null && c.music!.beats.isNotEmpty ? [for (final b in c.music!.beats) b + c.musicOffset] : [for (var x = 0.0; x < c.duration; x += 0.5) x];
        if (_within(beats, t, 0.06)) _flash(canvas, W, H, 0.15 + 0.3 * i);
        break;
      case 'strobe':
        if (_within(previewBeats(c), t, 0.04)) _flash(canvas, W, H, 0.5 + 0.4 * i);
        break;
      case 'lights':
        final op = 0.25 + 0.45 * i;
        final cs = [const Color(0xFFFF8A00), const Color(0xFFFF2E6B)];
        for (var k = 0; k < 2; k++) {
          final a = t * 0.015 * 6.283 * 6 + k * 3.1;
          final cx = W * (0.5 + 0.45 * math.cos(a)), cy = H * (0.5 + 0.45 * math.sin(a * 0.7));
          canvas.drawRect(Rect.fromLTWH(0, 0, W, H), Paint()
            ..blendMode = BlendMode.screen
            ..shader = ui.Gradient.radial(Offset(cx, cy), math.max(W, H) * 0.7, [cs[k].withValues(alpha: op), Colors.transparent]));
        }
        break;
      case 'flare':
        final r = math.min(W, H) * 0.5;
        final a = (0.5 + 0.4 * i) * (react ? (0.25 + 0.75 * math.max(_musicBeatEnv(c, t, 5), c.energyAt(t) * 0.5)) : 1);
        final x = _frac(0.75 - 0.0015 * p.fps * t) * W;
        canvas.drawRect(Rect.fromLTWH(0, 0, W, H), Paint()
          ..shader = ui.Gradient.radial(Offset(x, H * 0.2), r, [pick('#FFE7B0').withValues(alpha: a.clamp(0.0, 1.0)), pick('#FFE7B0').withValues(alpha: 0)], [0, 1]));
        break;
      case 'vhs':
        _grain(canvas, W, H, (8 + 14 * i) / 100);
        final line = Paint()..color = Colors.black.withValues(alpha: 0.15 + 0.2 * i);
        for (var y = 0.0; y < H; y += 3) {
          canvas.drawRect(Rect.fromLTWH(0, y, W, 1), line);
        }
        break;
      case 'retro':
        _grain(canvas, W, H, (6 + 10 * i) / 100);
        _vignette(canvas, W, H, 0.5);
        break;
      case 'oldfilm':
        _grain(canvas, W, H, (15 + 20 * i) / 100);
        _vignette(canvas, W, H, 0.6);
        if ((t % 0.9) < 0.3) canvas.drawRect(Rect.fromLTWH((t * 937) % W, 0, 2, H), Paint()..color = Colors.white.withValues(alpha: 0.35));
        if ((t % 1.3) < 0.2) canvas.drawRect(Rect.fromLTWH((t * 577 + 300) % W, 0, 1, H), Paint()..color = Colors.black.withValues(alpha: 0.4));
        break;
      case 'cinematic':
        _vignette(canvas, W, H, 0.35);
        final bar = (H * (0.06 + 0.06 * i)).roundToDouble();
        final bp = Paint()..color = Colors.black;
        canvas.drawRect(Rect.fromLTWH(0, 0, W, bar), bp);
        canvas.drawRect(Rect.fromLTWH(0, H - bar, W, bar), bp);
        break;
      case 'vignette':
        _vignette(canvas, W, H, 0.2 + 0.8 * i);
        break;
      case 'glitch':
        final times = react ? previewBeats(c) : [for (var x = 0.4; x < c.duration; x += 1.6 + (x * 13) % 1.3) x];
        if (_within(times, t, 0.05, offset: 0.04)) {
          _grain(canvas, W, H, (20 + 40 * i) / 100);
          canvas.drawRect(Rect.fromLTWH(0, 0, W, H), Paint()
            ..color = const Color(0x3300FF66)
            ..blendMode = BlendMode.hue);
        }
        break;
      case 'frame':
        final th = (math.min(W, H) * (0.015 + 0.03 * i)).roundToDouble();
        final hsv = HSVColor.fromColor(pick('#35D0BA'));
        final cc = hsv.withHue((hsv.hue + t * 60) % 360).toColor();
        canvas.drawRect(Rect.fromLTWH(th / 2, th / 2, W - th, H - th), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = th
          ..color = cc);
        break;
    }
  }
}

// ---------------------------------------------------------------------------
// Music visualisers
// ---------------------------------------------------------------------------

/// Live music visualiser driven by the real decoded audio (FFT/waveform of
/// the preview mix at the current playback time).
class VisualizerLayer extends StatefulWidget {
  final VisualizerItem v;
  final double t;
  final PreviewController c;
  const VisualizerLayer({super.key, required this.v, required this.t, required this.c});
  @override
  State<VisualizerLayer> createState() => _VisualizerLayerState();
}

class _VisualizerLayerState extends State<VisualizerLayer> {
  final List<Float32List> _history = []; // spectrogram columns
  double _lastT = -1;
  ui.Image? _logo;
  String? _logoPath;

  void _loadLogo() {
    final id = widget.v.logoAssetId;
    final path = id == null ? null : widget.c.assets.pathOf(id);
    if (path == _logoPath) return;
    _logoPath = path;
    _logo = null;
    if (path == null || !File(path).existsSync()) return;
    File(path).readAsBytes().then((b) => ui.instantiateImageCodec(b, targetWidth: 512)).then((codec) => codec.getNextFrame()).then((f) {
      if (mounted && _logoPath == path) setState(() => _logo = f.image);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    _loadLogo();
    final v = widget.v, c = widget.c, t = widget.t;
    if (v.style == 'spectrogram') {
      if ((t - _lastT).abs() > 0.5) _history.clear();
      if (t != _lastT) {
        _history.add(c.spectrum(t, bands: 64));
        if (_history.length > 160) _history.removeAt(0);
      }
    }
    _lastT = t;
    return LayoutBuilder(builder: (ctx, box) {
      final size = box.biggest;
      final p = c.project;
      final k = size.width / p.width;
      final rw = math.max(16, (v.width * p.width).round() ~/ 2 * 2) * k;
      final rh = math.max(16, (v.height * p.height).round() ~/ 2 * 2) * k;
      final cx = (v.x * p.width).round() * k + rw / 2, cy = (v.y * p.height).round() * k + rh / 2;
      return Stack(children: [
        Positioned(
          left: cx - rw / 2,
          top: cy - rh / 2,
          width: rw,
          height: rh,
          child: Opacity(opacity: v.opacity.clamp(0.0, 1.0), child: CustomPaint(painter: _VisPainter(v, t, c, _history, _logo))),
        ),
      ]);
    });
  }
}

class _VisPainter extends CustomPainter {
  final VisualizerItem v;
  final double t;
  final PreviewController c;
  final List<Float32List> history;
  final ui.Image? logo;
  _VisPainter(this.v, this.t, this.c, this.history, this.logo);

  @override
  bool shouldRepaint(covariant CustomPainter o) => true;

  double get _gainDb => 20 * math.log(v.intensity.clamp(0.1, 4)) / math.ln10;

  /// dB → 0..1 on a log amplitude scale like showfreqs ascale=log.
  double _lvl(double db) => ((db + _gainDb + 70) / 70).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final c1 = _hex(v.color), c2 = _hex(v.color2);
    switch (v.style) {
      case 'bars':
      case 'line':
      case 'dots':
        final n = 64;
        final s = c.spectrum(t, bands: n);
        final bw = w / n;
        if (v.style == 'bars') {
          final paint = Paint()..shader = ui.Gradient.linear(Offset(0, h), Offset.zero, [c1, Color.lerp(c1, c2, 0.6)!]);
          for (var b = 0; b < n; b++) {
            final bh = _lvl(s[b]) * h;
            canvas.drawRect(Rect.fromLTWH(b * bw + bw * 0.1, h - bh, bw * 0.8, bh), paint);
          }
        } else if (v.style == 'line') {
          final path = Path();
          for (var b = 0; b < n; b++) {
            final y = h - _lvl(s[b]) * h;
            b == 0 ? path.moveTo(0, y) : path.lineTo(b * bw + bw / 2, y);
          }
          canvas.drawPath(path, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.5, h / 90)
            ..color = c1);
        } else {
          final paint = Paint()..color = c1;
          for (var b = 0; b < n; b++) {
            canvas.drawCircle(Offset(b * bw + bw / 2, h - _lvl(s[b]) * h), math.max(1.5, bw * 0.22), paint);
          }
        }
        break;
      case 'circle':
        final sq = math.min(w, h);
        final pulse = v.bassPulse && c.music != null ? 1 + 0.18 * c.bassAt(t).clamp(0.0, 1.0) : 1.0;
        final s = c.spectrum(t, bands: 64);
        final r0 = sq * 0.28 * pulse, r1 = sq * 0.5 * pulse;
        final center = Offset(w / 2, h / 2);
        final paint = Paint()
          ..strokeWidth = math.max(1.5, sq * 0.012)
          ..strokeCap = StrokeCap.round
          ..color = c1;
        const n = 64;
        for (var k = 0; k < n * 2; k++) {
          final f = k < n ? k : 2 * n - 1 - k; // mirrored low→high→low
          final a = -math.pi / 2 + (k + 0.5) / (2 * n) * 2 * math.pi;
          final len = _lvl(s[f]) * (r1 - r0);
          final d = Offset(math.cos(a), math.sin(a));
          canvas.drawLine(center + d * r0, center + d * (r0 + math.max(1, len)), paint);
        }
        if (logo != null) {
          final lpulse = v.bassPulse && c.music != null ? 1 + 0.15 * c.bassAt(t).clamp(0.0, 1.0) : 1.0;
          final ls = sq * v.logoSize * lpulse;
          canvas.drawImageRect(logo!, Rect.fromLTWH(0, 0, logo!.width.toDouble(), logo!.height.toDouble()), Rect.fromCenter(center: center, width: ls, height: ls), Paint()..filterQuality = FilterQuality.medium);
        }
        break;
      case 'wave':
      case 'wavebars':
        final s = c.wave(t, n: 1024);
        final g = v.intensity.clamp(0.1, 4);
        if (v.style == 'wave') {
          final paint = Paint()
            ..color = c1
            ..strokeWidth = 1;
          final step = math.max(1, (1024 / w).floor());
          for (var x = 0; x < w; x++) {
            final k = (x / w * 1024).floor().clamp(0, 1023);
            var m = 0.0;
            for (var j = 0; j < step && k + j < 1024; j++) {
              m = math.max(m, s[k + j].abs());
            }
            final a = math.sqrt(m * g).clamp(0.0, 1.0) * h / 2;
            canvas.drawLine(Offset(x.toDouble(), h / 2 - a), Offset(x.toDouble(), h / 2 + a), paint);
          }
        } else {
          final path = Path();
          for (var k = 0; k < 1024; k += 2) {
            final y = h / 2 - (s[k] * g).clamp(-1.0, 1.0) * h / 2;
            k == 0 ? path.moveTo(0, y) : path.lineTo(k / 1024 * w, y);
          }
          canvas.drawPath(path, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = c1);
        }
        break;
      case 'oscilloscope':
        final sq = math.min(w, h);
        final pulse = v.bassPulse && c.music != null ? 1 + 0.18 * c.bassAt(t).clamp(0.0, 1.0) : 1.0;
        final s = c.wave(t, n: 1024);
        final g = v.intensity.clamp(0.1, 4) * 1.4;
        final path = Path();
        for (var k = 0; k + 9 < 1024; k++) {
          final a = s[k] * g, b = s[k + 9] * g;
          final x = w / 2 + (a - b) * sq / 2 * pulse, y = h / 2 - (a + b) / 2 * sq / 2 * pulse;
          k == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
        }
        canvas.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = c1);
        break;
      case 'spectrogram':
        if (history.isEmpty) return;
        final n = history.first.length;
        final cw = w / 160, bh = h / n;
        final paint = Paint();
        final x0 = w - history.length * cw;
        for (var col = 0; col < history.length; col++) {
          final s = history[col];
          for (var b = 0; b < n; b++) {
            final l = _lvl(s[b]);
            if (l < 0.05) continue;
            paint.color = HSVColor.fromAHSV(1, (260 - 260 * l).clamp(0, 360).toDouble(), 1, l).toColor();
            canvas.drawRect(Rect.fromLTWH(x0 + col * cw, h - (b + 1) * bh, cw + 0.5, bh + 0.5), paint);
          }
        }
        break;
      case 'cqt':
        const n = 72;
        final s = c.spectrum(t, bands: n);
        final bw = w / n;
        for (var b = 0; b < n; b++) {
          final l = _lvl(s[b]);
          final col = HSVColor.fromAHSV(1, (b / n * 300) % 360, 0.8, 1).toColor();
          canvas.drawRect(Rect.fromLTWH(b * bw, h - l * h, bw - 1, l * h), Paint()..color = col);
        }
        break;
      case 'volume':
        final s = c.wave(t, n: 1024);
        var acc = 0.0;
        for (final x in s) {
          acc += x * x;
        }
        final rms = math.sqrt(acc / s.length) * v.intensity.clamp(0.1, 4);
        final db = rms <= 1e-6 ? -60 : 20 * math.log(rms) / math.ln10;
        final l = ((db + 60) / 60).clamp(0.0, 1.0);
        final barH = h / 2 - 4;
        final paint = Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(w, 0), [const Color(0xFF2EE66B), const Color(0xFFFFE14A), const Color(0xFFFF3B3B)], [0, 0.7, 1]);
        canvas.drawRect(Rect.fromLTWH(0, 0, w * l, barH), paint);
        canvas.drawRect(Rect.fromLTWH(0, barH + 8, w * (l * 0.97), barH), paint);
        break;
      default:
        final s = c.spectrum(t, bands: 48);
        final bw = w / 48;
        for (var b = 0; b < 48; b++) {
          final bh = _lvl(s[b]) * h;
          canvas.drawRect(Rect.fromLTWH(b * bw, h - bh, bw - 1, bh), Paint()..color = c1);
        }
    }
  }
}
