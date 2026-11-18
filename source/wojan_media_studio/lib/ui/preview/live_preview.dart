import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart' hide Easing;
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/theme.dart';
import '../../engine/util/expr.dart';
import '../../engine/util/json_util.dart';
import '../../engine/video/color.dart';
import '../../engine/video/model.dart';
import 'fx_painters.dart';
import 'preview_controller.dart';
import 'preview_math.dart';
import 'text_layer.dart';

/// FotoPlay-style real-time preview: the frame for the current timeline time
/// is composed by Flutter every display frame (no rendering wait). Final
/// export uses the FFmpeg engine with the same motion/timing math.
class LivePreview extends StatefulWidget {
  final PreviewController controller;
  final bool safeZones;
  final bool showControls;
  final bool pausedIcon;
  const LivePreview({super.key, required this.controller, this.safeZones = false, this.showControls = true, this.pausedIcon = true});
  @override
  State<LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<LivePreview> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => widget.controller.tick());

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onCtl);
    widget.controller.prepareAudio();
  }

  /// The frame clock only runs while playing (no battery drain when idle).
  void _onCtl() {
    final playing = widget.controller.playing;
    if (playing && !_ticker.isActive) {
      _ticker.start();
    } else if (!playing && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void didUpdateWidget(covariant LivePreview old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onCtl);
      widget.controller.addListener(_onCtl);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCtl);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final p = c.project;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: AspectRatio(
          aspectRatio: p.width / p.height,
          child: GestureDetector(
            onTap: c.toggle,
            child: ClipRect(
              child: LayoutBuilder(builder: (ctx, box) {
                return ListenableBuilder(
                  listenable: c,
                  builder: (ctx, _) => _Frame(c: c, size: box.biggest, safeZones: widget.safeZones, pausedIcon: widget.pausedIcon),
                );
              }),
            ),
          ),
        ),
      ),
      if (widget.showControls) PreviewControls(controller: c),
    ]);
  }
}

class PreviewControls extends StatelessWidget {
  final PreviewController controller;
  const PreviewControls({super.key, required this.controller});
  String _f(double s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).floor().toString().padLeft(2, '0')}.${((s * 10) % 10).floor()}';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (c, _) => Row(children: [
          IconButton.filled(iconSize: 30, icon: Icon(controller.playing ? Icons.pause : Icons.play_arrow), onPressed: controller.toggle, tooltip: controller.playing ? 'Pauza' : 'Odtwórz'),
          const SizedBox(width: 6),
          Text('${_f(controller.position)} / ${_f(controller.duration)}', style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
          Expanded(child: Slider(value: controller.duration <= 0 ? 0 : (controller.position / controller.duration).clamp(0.0, 1.0), onChanged: (v) => controller.seek(v * controller.duration))),
          if (!controller.audioReady && controller.project.audio.tracks.any((t) => t.clips.isNotEmpty)) const Tooltip(message: 'Przygotowanie dźwięku…', child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
        ]),
      );
}

class _Frame extends StatelessWidget {
  final PreviewController c;
  final Size size;
  final bool safeZones;
  final bool pausedIcon;
  const _Frame({required this.c, required this.size, required this.safeZones, this.pausedIcon = true});

  @override
  Widget build(BuildContext context) {
    final p = c.project;
    final t = c.position;
    final scale = size.width / p.width; // display px per output px
    final st = trackAt(p, c.starts, t);
    if (st != null) _precacheAhead(context, st.next ?? st.index);
    Widget base;
    if (st == null) {
      base = Container(color: hexColor(p.background));
    } else {
      final a = _clip(st.index, st.local);
      if (st.next == null) {
        base = a;
      } else {
        base = TransitionView(type: st.transition, progress: st.progress, a: a, b: _clip(st.next!, st.nextLocal), size: size);
      }
    }
    base = wrapBaseVfx(base, p, t, c, size);
    final gg = gradeMatrix(p.globalGrade);
    if (gg != null) base = ColorFiltered(colorFilter: ColorFilter.matrix(gg), child: base);
    final layers = <Widget>[
      Positioned.fill(child: Container(color: hexColor(p.background))),
      Positioned.fill(child: base),
      if (p.globalGrade.vignette > 0) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: VignettePainter(p.globalGrade.vignette)))),
      // effects
      for (final fx in p.vfx)
        if (t >= fx.start && (fx.duration <= 0 || t < fx.start + fx.duration)) Positioned.fill(child: IgnorePointer(child: VfxLayer(fx: fx, t: t, c: c, size: size))),
      // overlays
      for (final o in ([...p.overlays.where((o) => !o.hidden)]..sort((x, y) => x.layer.compareTo(y.layer))))
        if (t >= o.start && t < o.end) _overlay(o, t - o.start, scale),
      // visualisers
      for (final v in p.visualizers)
        if (t >= v.start && (v.duration <= 0 || t < v.start + v.duration)) Positioned.fill(child: IgnorePointer(child: VisualizerLayer(v: v, t: t, c: c))),
      // texts & lyrics
      Positioned.fill(child: IgnorePointer(child: TextLayer(project: p, t: t, scale: scale, size: size))),
      if (safeZones) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: SafeZonesPainter(p.height > p.width)))),
      if (!c.playing && pausedIcon)
        Positioned.fill(child: IgnorePointer(child: Center(child: Container(decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle), padding: const EdgeInsets.all(10), child: const Icon(Icons.play_arrow, color: Colors.white, size: 44))))),
    ];
    return Stack(clipBehavior: Clip.hardEdge, children: layers);
  }

  Widget _clip(int i, double local) {
    final p = c.project;
    final clip = p.clips[i];
    final dur = clip.duration;
    final cam = cameraAt(clip, local, dur, clipStart: c.starts[i], music: c.music, musicOffset: c.musicOffset);
    Widget media;
    switch (clip.kind) {
      case ClipKind.color:
        media = Container(color: hexColor(clip.color));
        break;
      case ClipKind.image:
        media = _imageCanvas(clip, c.assets.pathOf(clip.assetId!));
        break;
      case ClipKind.video:
        final slot = c.videoFor(clip.id);
        final w = slot == null ? Container(color: Colors.black) : Video(controller: slot.controller, controls: NoVideoControls, fit: BoxFit.cover, fill: Colors.black);
        media = _fitWidget(clip, w, isVideo: true);
        break;
    }
    // camera (zoompan) : visible window = 1/zoom of the canvas at pan offset
    final W = size.width, H = size.height;
    final z = cam.zoom;
    Widget out = ClipRect(
      child: Transform(
        transform: Matrix4.identity()
          ..translateByDouble(-(z - 1) * cam.px * W, -(z - 1) * cam.py * H, 0, 1)
          ..scaleByDouble(z, z, 1, 1),
        child: SizedBox(width: W, height: H, child: media),
      ),
    );
    if (cam.rotationDeg != 0) out = Transform.rotate(angle: cam.rotationDeg * math.pi / 180, child: out);
    final m = gradeMatrix(clip.grade);
    if (m != null) out = ColorFiltered(colorFilter: ColorFilter.matrix(m), child: out);
    if (clip.grade.vignette > 0) out = Stack(fit: StackFit.expand, children: [out, CustomPaint(painter: VignettePainter(clip.grade.vignette))]);
    final a = clipAlpha(clip, local, dur);
    if (a < 1) out = Opacity(opacity: a, child: out);
    if (clip.animIn.startsWith('slide')) {
      final d = math.max(0.05, clip.animInDur);
      final e = 1 - math.min(local / d, 1);
      final off = switch (clip.animIn) {
        'slideLeft' => Offset(W * e, 0),
        'slideRight' => Offset(-W * e, 0),
        'slideUp' => Offset(0, H * e),
        _ => Offset(0, -H * e),
      };
      out = Transform.translate(offset: off, child: out);
    }
    return SizedBox(width: W, height: H, child: out);
  }

  ImageProvider _provider(String path) => ResizeImage(FileImage(File(path)), width: (size.width * 2.2).round().clamp(320, 2160), policy: ResizeImagePolicy.fit, allowUpscaling: false);

  /// Decodes the next photos ahead of time so cuts never show an empty frame.
  void _precacheAhead(BuildContext context, int from) {
    final p = c.project;
    for (var k = from + 1; k <= from + 2 && k < p.clips.length; k++) {
      final cl = p.clips[k];
      if (cl.kind == ClipKind.image && cl.assetId != null) precacheImage(_provider(c.assets.pathOf(cl.assetId!)), context);
    }
  }

  Widget _imageCanvas(VisualClip clip, String path) {
    final img = Image(
      image: _provider(path),
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
    return _fitWidget(clip, img);
  }

  Widget _source(VisualClip clip, Widget w) {
    var x = w;
    if (clip.hasCrop) {
      final ax = clip.cropW >= 0.999 ? 0.0 : (clip.cropX / (1 - clip.cropW)) * 2 - 1;
      final ay = clip.cropH >= 0.999 ? 0.0 : (clip.cropY / (1 - clip.cropH)) * 2 - 1;
      x = ClipRect(child: Align(alignment: Alignment(ax, ay), widthFactor: clip.cropW, heightFactor: clip.cropH, child: x));
    }
    if (clip.rotate % 360 != 0) x = RotatedBox(quarterTurns: (clip.rotate ~/ 90) % 4, child: x);
    if (clip.flipH || clip.flipV) x = Transform.scale(scaleX: clip.flipH ? -1 : 1, scaleY: clip.flipV ? -1 : 1, child: x);
    return x;
  }

  Widget _fitWidget(VisualClip clip, Widget w, {bool isVideo = false}) {
    final src = _source(clip, w);
    switch (clip.fit) {
      case FitMode.cover:
        return FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: src);
      case FitMode.contain:
        return Container(color: hexColor(c.project.background), child: FittedBox(fit: BoxFit.contain, child: src));
      case FitMode.stretch:
        return FittedBox(fit: BoxFit.fill, child: src);
      case FitMode.blurBackground:
        return Stack(fit: StackFit.expand, children: [
          ImageFiltered(imageFilter: ImageFilterShim.blur(18), child: ColorFiltered(colorFilter: const ColorFilter.matrix([0.92, 0, 0, 0, -10, 0, 0.92, 0, 0, -10, 0, 0, 0.92, 0, -10, 0, 0, 0, 1, 0]), child: FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: src))),
          FittedBox(fit: BoxFit.contain, child: src),
        ]);
    }
  }

  Widget _overlay(OverlayItem o, double rel, double scale) {
    final W = size.width, H = size.height;
    final a = c.assets.asset(o.assetId);
    final aspect = (a.width ?? 1) / math.max(1, (a.height ?? 1));
    var s = o.scaleKf.isEmpty ? o.scale : evalKeyframes(o.scaleKf, rel);
    if ((o.animIn == 'zoom' || o.animIn == 'pop') && rel < o.animInDur) s *= (rel / o.animInDur).clamp(0.05, 1.0);
    if (o.animOut == 'zoom' && rel > o.duration - o.animOutDur) s *= ((o.duration - rel) / o.animOutDur).clamp(0.05, 1.0);
    var x = o.xKf.isEmpty ? o.x : evalKeyframes(o.xKf, rel);
    var y = o.yKf.isEmpty ? o.y : evalKeyframes(o.yKf, rel);
    final e = 1 - math.min(rel / math.max(0.05, o.animInDur), 1);
    if (o.animIn == 'slideLeft') x += e;
    if (o.animIn == 'slideRight') x -= e;
    if (o.animIn == 'slideUp') y += e;
    if (o.animIn == 'slideDown') y -= e;
    var rot = o.rotKf.isEmpty ? o.rotation : evalKeyframes(o.rotKf, rel);
    if (o.animIn == 'spin' && rel < o.animInDur) rot += 360 * (1 - rel / o.animInDur);
    var op = o.opacity;
    if (o.animIn == 'fade') op *= (rel / math.max(0.01, o.animInDur)).clamp(0.0, 1.0);
    if (o.animOut == 'fade') op *= ((o.duration - rel) / math.max(0.01, o.animOutDur)).clamp(0.0, 1.0);
    final w = s * W, h = w / aspect;
    Widget img = a.kind.name == 'video' ? Container(color: Colors.black54, child: const Icon(Icons.movie, color: Colors.white54)) : Image(image: ResizeImage(FileImage(File(c.assets.pathOf(o.assetId))), width: (w * 2).round().clamp(64, 1600)), fit: BoxFit.fill, gaplessPlayback: true);
    img = switch (o.mask) {
      MaskShape.circle => ClipOval(child: SizedBox.square(dimension: math.min(w, h), child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: w, height: h, child: img)))),
      MaskShape.ellipse => ClipOval(child: img),
      MaskShape.rounded => ClipRRect(borderRadius: BorderRadius.circular(math.min(w, h) * 0.12), child: img),
      MaskShape.heart || MaskShape.star => ClipPath(clipper: ShapeClipper(o.mask), child: img),
      MaskShape.none => o.borderWidth > 0 ? Container(decoration: BoxDecoration(border: Border.all(color: hexColor(o.borderColor), width: o.borderWidth * scale)), child: img) : img,
    };
    final boxW = o.mask == MaskShape.circle ? math.min(w, h) : w, boxH = o.mask == MaskShape.circle ? math.min(w, h) : h;
    return Positioned(
      left: x * W - boxW / 2,
      top: y * H - boxH / 2,
      width: boxW,
      height: boxH,
      child: Opacity(opacity: op.clamp(0.0, 1.0), child: Transform.rotate(angle: rot * math.pi / 180, child: img)),
    );
  }
}

/// Shim to keep imports tidy.
class ImageFilterShim {
  static ui.ImageFilter blur(double s) => ui.ImageFilter.blur(sigmaX: s, sigmaY: s);
}

Color hexColor(String h) {
  var x = h.replaceFirst('#', '').replaceFirst('0x', '');
  if (x.length == 6) x = 'FF$x';
  return Color(int.tryParse(x, radix: 16) ?? 0xFF000000);
}

/// 5×4 colour matrix approximating [ColorGrade] (brightness, contrast,
/// saturation, exposure, temperature, tint, looks) for live preview.
List<double>? gradeMatrix(ColorGrade g) {
  if (g.isNeutral || (g.vignette > 0 && g.brightness == 0 && g.contrast == 1 && g.saturation == 1 && g.filter.isEmpty && g.temperature == 6500 && g.exposure == 0 && g.tint == 0 && g.gamma == 1 && g.hue == 0)) return null;
  List<double> mul(List<double> a, List<double> b) {
    final r = List<double>.filled(20, 0);
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 5; j++) {
        var s = j == 4 ? a[i * 5 + 4] : 0.0;
        for (var k = 0; k < 4; k++) {
          s += a[i * 5 + k] * b[k * 5 + j];
        }
        r[i * 5 + j] = s;
      }
    }
    return r;
  }

  List<double> id() => [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
  List<double> sat(double s) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    return [lr * (1 - s) + s, lg * (1 - s), lb * (1 - s), 0, 0, lr * (1 - s), lg * (1 - s) + s, lb * (1 - s), 0, 0, lr * (1 - s), lg * (1 - s), lb * (1 - s) + s, 0, 0, 0, 0, 0, 1, 0];
  }

  List<double> contrastBright(double c, double b) {
    final o = 128 * (1 - c) + b * 255;
    return [c, 0, 0, 0, o, 0, c, 0, 0, o, 0, 0, c, 0, o, 0, 0, 0, 1, 0];
  }

  List<double> gain(double r, double gg, double b) => [r, 0, 0, 0, 0, 0, gg, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0];
  var m = id();
  final ex = math.pow(2, g.exposure).toDouble();
  if (ex != 1) m = mul(gain(ex, ex, ex), m);
  m = mul(contrastBright(g.contrast, g.brightness), m);
  if (g.saturation != 1) m = mul(sat(g.saturation), m);
  if (g.temperature != 6500) {
    final k = ((g.temperature - 6500) / 6500).clamp(-1.0, 1.0);
    m = mul(gain(1 - 0.18 * k, 1 - 0.02 * k, 1 + 0.18 * k), m);
  }
  if (g.tint != 0) m = mul(gain(1 + 0.08 * g.tint, 1 - 0.12 * g.tint, 1 + 0.08 * g.tint), m);
  if (g.gamma != 1) m = mul(contrastBright(1, (g.gamma - 1) * 0.12), m);
  final s = g.filterStrength.clamp(0.0, 1.0);
  switch (g.filter) {
    case 'bw':
    case 'noir':
      m = mul(sat(1 - s), m);
      if (g.filter == 'noir') m = mul(contrastBright(1 + 0.5 * s, -0.05 * s), m);
      break;
    case 'sepia':
      m = mul([1 - 0.607 * s, 0.769 * s, 0.189 * s, 0, 0, 0.349 * s, 1 - 0.314 * s, 0.168 * s, 0, 0, 0.272 * s, 0.534 * s, 1 - 0.869 * s, 0, 0, 0, 0, 0, 1, 0], m);
      break;
    case 'vintage':
      m = mul(gain(1 + 0.08 * s, 1 + 0.02 * s, 1 - 0.12 * s), mul(sat(1 - 0.25 * s), m));
      break;
    case 'warm':
    case 'golden':
      m = mul(gain(1 + 0.12 * s, 1 + 0.03 * s, 1 - 0.14 * s), m);
      break;
    case 'cool':
      m = mul(gain(1 - 0.1 * s, 1, 1 + 0.15 * s), m);
      break;
    case 'teal_orange':
      m = mul(gain(1 + 0.08 * s, 1 + 0.02 * s, 1 + 0.06 * s), mul(sat(1 + 0.15 * s), m));
      break;
    case 'vivid':
      m = mul(sat(1 + 0.6 * s), m);
      break;
    case 'fade':
    case 'pastel':
      m = mul(contrastBright(1 - 0.15 * s, 0.05 * s), mul(sat(1 - 0.3 * s), m));
      break;
    case 'horror':
      m = mul(contrastBright(1 + 0.4 * s, -0.08 * s), mul(sat(1 - 0.6 * s), m));
      break;
    case 'negative':
      m = mul([-1, 0, 0, 0, 255, 0, -1, 0, 0, 255, 0, 0, -1, 0, 255, 0, 0, 0, 1, 0], m);
      break;
    case 'neon_night':
      m = mul(gain(1 + 0.05 * s, 0.95, 1 + 0.25 * s), mul(sat(1 + 0.5 * s), m));
      break;
    case 'forest':
      m = mul(gain(0.97, 1 + 0.1 * s, 0.95), m);
      break;
    case 'cross':
      m = mul(gain(1.08, 1.05, 0.85), mul(contrastBright(1.1, 0), m));
      break;
  }
  return m;
}

class VignettePainter extends CustomPainter {
  final double amount;
  VignettePainter(this.amount);
  @override
  void paint(Canvas canvas, Size s) {
    final r = s.longestSide * 0.75;
    canvas.drawRect(Offset.zero & s, Paint()..shader = RadialGradient(colors: [Colors.transparent, Colors.black.withValues(alpha: (0.25 + 0.6 * amount).clamp(0, 0.95))], stops: [0.55 - 0.2 * amount, 1]).createShader(Rect.fromCircle(center: s.center(Offset.zero), radius: r)));
  }

  @override
  bool shouldRepaint(covariant VignettePainter o) => o.amount != amount;
}

class SafeZonesPainter extends CustomPainter {
  final bool vertical;
  SafeZonesPainter(this.vertical);
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = WmsColors.warn.withValues(alpha: 0.18);
    if (vertical) {
      c.drawRect(Rect.fromLTWH(0, 0, s.width, s.height * 0.12), p);
      c.drawRect(Rect.fromLTWH(0, s.height * 0.78, s.width, s.height * 0.22), p);
      c.drawRect(Rect.fromLTWH(s.width * 0.84, s.height * 0.35, s.width * 0.16, s.height * 0.43), p);
    } else {
      c.drawRect(Rect.fromLTWH(0, s.height * 0.85, s.width, s.height * 0.15), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}

class ShapeClipper extends CustomClipper<Path> {
  final MaskShape shape;
  ShapeClipper(this.shape);
  @override
  Path getClip(Size s) {
    final p = Path();
    if (shape == MaskShape.heart) {
      final w = s.width, h = s.height;
      p.moveTo(w / 2, h * 0.92);
      p.cubicTo(w * -0.25, h * 0.45, w * 0.18, h * -0.12, w / 2, h * 0.22);
      p.cubicTo(w * 0.82, h * -0.12, w * 1.25, h * 0.45, w / 2, h * 0.92);
      return p..close();
    }
    final c = s.center(Offset.zero);
    final r = math.min(s.width, s.height) / 2;
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final rr = i.isEven ? r : r * 0.45;
      final pt = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> o) => false;
}

/// Approximations of the FFmpeg xfade transitions for live preview.
class TransitionView extends StatelessWidget {
  final String type;
  final double progress; // 0..1
  final Widget a, b;
  final Size size;
  const TransitionView({super.key, required this.type, required this.progress, required this.a, required this.b, required this.size});

  @override
  Widget build(BuildContext context) {
    final q = progress.clamp(0.0, 1.0);
    final W = size.width, H = size.height;
    Widget stack(List<Widget> c) => Stack(fit: StackFit.expand, clipBehavior: Clip.hardEdge, children: c);
    // Shows the [wf]×[hf] part of [w] anchored at [al] (real clipping; the
    // child keeps its full size so nothing moves).
    Widget clip(Widget w, Alignment al, double wf, double hf) => ClipRect(clipper: _FracClip(al, wf, hf), child: w);
    switch (type) {
      case 'fadeblack':
      case 'fadewhite':
        // FFmpeg xfade (P = 1-q): out = P·mix(A,c,S(0.8,1,P)) + (1-P)·mix(B,c,S(0.2,1,P))
        final col = type == 'fadeblack' ? Colors.black : Colors.white;
        final pp = 1 - q;
        final wa = pp * _ss(0.8, 1, pp), wb = (1 - pp) * _ss(0.2, 1, pp);
        return stack([Container(color: col), Opacity(opacity: wa.clamp(0.0, 1.0), child: a), Opacity(opacity: wb.clamp(0.0, 1.0), child: b)]);
      case 'slideleft':
      case 'slideright':
      case 'slideup':
      case 'slidedown':
      case 'smoothleft':
      case 'smoothright':
      case 'coverleft':
      case 'revealright':
        final dx = type.contains('left') ? -1.0 : type.contains('right') ? 1.0 : 0.0;
        final dy = type.contains('up') ? -1.0 : type.contains('down') ? 1.0 : 0.0;
        final cover = type == 'coverleft', reveal = type == 'revealright';
        if (type == 'smoothleft' || type == 'smoothright') {
          // xfade: B weight = smoothstep(0,1, 1 + x/W - 2P) (mirrored for right)
          final pp = 1 - q;
          final stops = <double>[for (var k = 0; k <= 16; k++) k / 16];
          final al = [for (final x in stops) 1 - _ss(0, 1, 1 + (type == 'smoothleft' ? x : 1 - x) - 2 * pp)];
          return stack([a, ShaderMask(blendMode: BlendMode.dstIn, shaderCallback: (r) => ui.Gradient.linear(r.centerLeft, r.centerRight, [for (final v in al) Color.fromRGBO(255, 255, 255, 1 - v)], stops), child: b)]);
        }
        if (reveal) {
          // A slides away to the right revealing B, which stays still
          return stack([b, Transform.translate(offset: Offset(q * W, 0), child: a)]);
        }
        return stack([
          Transform.translate(offset: cover ? Offset.zero : Offset(dx * q * W, dy * q * H), child: reveal ? b : a),
          Transform.translate(offset: reveal ? Offset(dx * q * W, dy * q * H) : Offset(-dx * (1 - q) * W, -dy * (1 - q) * H), child: reveal ? a : b),
        ]);
      case 'wipeleft':
        return stack([a, Positioned.fill(child: clip(b, Alignment.centerRight, q, 1))]);
      case 'wiperight':
        return stack([a, Positioned.fill(child: clip(b, Alignment.centerLeft, q, 1))]);
      case 'wipeup':
        return stack([a, Positioned.fill(child: clip(b, Alignment.bottomCenter, 1, q))]);
      case 'wipedown':
        return stack([a, Positioned.fill(child: clip(b, Alignment.topCenter, 1, q))]);
      case 'zoomin':
        // FFmpeg xfade: A zooms in (zf = S(0.5,1,P)), then fades to B with S(0,0.5,P)
        final pp = 1 - q;
        final zf = _ss(0.5, 1, pp), wa = _ss(0, 0.5, pp);
        return stack([b, Opacity(opacity: wa, child: Transform.scale(scale: 1 / math.max(zf, 0.002), child: a))]);
      case 'dissolve':
        // xfade: per-pixel random threshold → B appears pixel by pixel
        return stack([a, ShaderMask(blendMode: BlendMode.dstIn, shaderCallback: (r) => ImageShader(_dissolveMask(q), TileMode.repeated, TileMode.repeated, Matrix4.identity().storage, filterQuality: FilterQuality.none), child: b)]);
      case 'rectcrop':
        // A shrinks to a centred rectangle on black, then B grows from it
        final f = q < 0.5 ? 1 - 2 * q : 2 * q - 1;
        return stack([Container(color: Colors.black), clip(q < 0.5 ? a : b, Alignment.center, f, f)]);
      case 'hlslice':
        const n = 10;
        final pp = 1 - q;
        return stack([
          a,
          for (var k = 0; k < n; k++)
            Positioned(left: W * k / n, top: 0, width: W / n + 0.5, height: H, child: ClipRect(clipper: _FracClip(Alignment.centerLeft, _ss(-0.5, 0, (k + 0.5) / n - pp * 1.5), 1), child: OverflowBox(alignment: Alignment(-1 + 2 * k / (n - 1), 0), minWidth: W, maxWidth: W, child: SizedBox(width: W, height: H, child: b)))),
        ]);
      case 'pixelize':
        final blk = 1 + 0.05 * W * math.sin(math.pi * q); // ~5% of the width at the midpoint, like xfade
        final k = 1 / blk.clamp(1.0, 200.0);
        return Transform.scale(
          scale: 1 / k,
          alignment: Alignment.topLeft,
          filterQuality: FilterQuality.none,
          child: Transform.scale(scale: k, alignment: Alignment.topLeft, filterQuality: FilterQuality.none, child: stack([a, Opacity(opacity: q, child: b)])),
        );
      case 'circleopen':
      case 'circleclose':
        // FFmpeg xfade: smooth = dist/halfDiag + p, p = ±(progress-0.5)*3,
        // blended with smoothstep(0,1,smooth) – reproduced as a radial mask.
        final open = type == 'circleopen';
        double sstep(double x) {
          final v = x.clamp(0.0, 1.0);
          return v * v * (3 - 2 * v);
        }
        final stops = <double>[for (var k = 0; k <= 16; k++) k / 16];
        final alphas = [for (final r in stops) open ? 1 - sstep(r + (0.5 - q) * 3) : sstep(r + (q - 0.5) * 3)];
        return stack([
          a,
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => ui.Gradient.radial(rect.center, math.sqrt(rect.width * rect.width + rect.height * rect.height) / 2, [for (final al in alphas) Color.fromRGBO(255, 255, 255, al)], stops),
            child: b,
          ),
        ]);
      case 'radial':
        return stack([a, ClipPath(clipper: _CircleClip(q, true), child: b)]);
      case 'hblur':
        final bl = math.sin(q * math.pi) * 18 + 0.01;
        return ImageFiltered(imageFilter: ImageFilterShim.blur(bl), child: stack([a, Opacity(opacity: q, child: b)]));
      case 'spin':
        if (q < 0.5) return stack([Container(color: Colors.black), Transform.rotate(angle: q * 2 * math.pi, child: Transform.scale(scale: math.max(0.001, 1 - 2 * q), child: a))]);
        return stack([Container(color: Colors.black), Transform.rotate(angle: q * 2 * math.pi, child: Transform.scale(scale: math.max(0.001, 2 * q - 1), child: b))]);
      case 'glitch':
        const n = 18;
        return stack([
          for (var i = 0; i < n; i++)
            Positioned(
              left: 0,
              right: 0,
              top: H * i / n,
              height: H / n + 1,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment(0, -1 + 2 * (i + 0.5) / n),
                  maxHeight: H,
                  minHeight: H,
                  child: Transform.translate(
                    offset: Offset(((i * 53) % 7 - 3) * W * 0.02 * math.sin(math.pi * q), 0),
                    child: (((i * 37 + (q * 14).floor() * 91) % 100) / 100) > (1 - q) ? b : a,
                  ),
                ),
              ),
            ),
        ]);
      case 'cube':
        // engine: A squeezed into [0, P·W], B into [P·W, W], tapered edges
        final pp = 1 - q;
        return stack([
          Container(color: Colors.black),
          // projective w = 1 + v·x reproduces persA/persB (height shrinks by
          // 1+0.25·(1-P) at the shared edge)
          Transform(alignment: Alignment.centerLeft, transform: Matrix4.identity()..setEntry(3, 0, 0.25 * q / math.max(pp * W, 1))..scaleByDouble(math.max(pp, 0.001), 1, 1, 1), child: a),
          Transform(alignment: Alignment.centerRight, transform: Matrix4.identity()..setEntry(3, 0, -0.25 * pp / math.max(q * W, 1))..scaleByDouble(math.max(q, 0.001), 1, 1, 1), child: b),
        ]);
      case 'filmburn':
        return stack([a, Opacity(opacity: q, child: b), IgnorePointer(child: Container(color: const Color(0xFFFFE2B0).withValues(alpha: math.sin(math.pi * q) * 0.75)))]);
      case 'squeezeh':
        // xfade squeezeh: A squeezed vertically into a centred band over B
        return stack([b, Transform.scale(scaleY: math.max(0.001, 1 - q), child: a)]);
      default:
        return stack([a, Opacity(opacity: q, child: b)]);
    }
  }
}

class _CircleClip extends CustomClipper<Path> {
  final double q;
  final bool sector;
  _CircleClip(this.q, this.sector);
  @override
  Path getClip(Size s) {
    final c = s.center(Offset.zero);
    final r = math.sqrt(s.width * s.width + s.height * s.height) / 2;
    if (sector) {
      return Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(Rect.fromCircle(center: c, radius: r), -math.pi / 2, q * 2 * math.pi, false)
        ..close();
    }
    return Path()..addOval(Rect.fromCircle(center: c, radius: r * q));
  }

  @override
  bool shouldReclip(covariant _CircleClip o) => o.q != q;
}

/// Utility used by toolbars to show time.
String fmtPreviewTime(double s) => fmtTime(s);

class _FracClip extends CustomClipper<Rect> {
  final Alignment al;
  final double wf, hf;
  _FracClip(this.al, this.wf, this.hf);
  @override
  Rect getClip(Size size) {
    final w = size.width * wf.clamp(0.0, 1.0), h = size.height * hf.clamp(0.0, 1.0);
    final x = (size.width - w) * (al.x + 1) / 2, y = (size.height - h) * (al.y + 1) / 2;
    return Rect.fromLTWH(x, y, w, h);
  }

  @override
  bool shouldReclip(covariant _FracClip o) => o.wf != wf || o.hf != hf || o.al != al;
}

double _ss(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Binary random masks for 'dissolve' (xfade: frand*2 + progress*2 - 1.5 ≥ 0.5).
final Map<int, ui.Image> _dissolveCache = {};
ui.Image _dissolveMask(double q) {
  final lvl = (q * 32).round().clamp(0, 32);
  return _dissolveCache.putIfAbsent(lvl, () {
    final r = math.Random(12345);
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final paint = Paint()..color = Colors.white;
    final pp = 1 - lvl / 32;
    for (var y = 0; y < 96; y++) {
      for (var x = 0; x < 96; x++) {
        final smooth = r.nextDouble() * 2 + pp * 2 - 1.5;
        if (smooth < 0.5) c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), paint); // B visible
      }
    }
    return rec.endRecording().toImageSync(96, 96);
  });
}
