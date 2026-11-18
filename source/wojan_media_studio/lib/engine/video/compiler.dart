import 'dart:io';
import 'dart:math' as math;

import '../audio/audio_compiler.dart';
import '../audio/effects.dart';
import '../dsp/analysis.dart';
import '../export/video_export.dart';
import '../ffmpeg/escape.dart';
import '../ffmpeg/runner.dart';
import '../lyrics/ass.dart';
import '../project/asset.dart';
import '../util/expr.dart';
import '../util/json_util.dart';
import 'model.dart';
import 'transitions.dart';
import 'vfx.dart';
import 'visualizer.dart';

/// Options controlling a compile (preview vs final).
class CompileOptions {
  final double scale; // preview downscale (1 = full)
  final double? fps; // override fps (preview)
  final String fontsDir;
  final AudioAnalysis? music; // analysis of main music for reactive fx
  final double musicOffset; // where music starts on the timeline
  CompileOptions({this.scale = 1, this.fps, required this.fontsDir, this.music, this.musicOffset = 0});
}

class CompiledGraph {
  final List<String> inputs;
  final String graph;
  final String videoLabel;
  final String audioLabel;
  final double duration;
  final int width, height;
  final double fps;
  CompiledGraph(this.inputs, this.graph, this.videoLabel, this.audioLabel, this.duration, this.width, this.height, this.fps);
}

/// Compiles a [VideoProject] into one FFmpeg filter_complex.
class VideoCompiler {
  final VideoProject p;
  final AssetResolver assets;
  final Directory workDir;
  final CompileOptions opt;
  late final AudioGraphBuilder b;
  late final int W, H;
  late final double F;
  late final String fpsS;

  VideoCompiler(this.p, this.assets, this.workDir, this.opt) {
    int even(double v) => math.max(2, (v / 2).round() * 2);
    W = even(p.width * opt.scale);
    H = even(p.height * opt.scale);
    F = opt.fps ?? p.fps;
    fpsS = FfEscape.num(F);
    b = AudioGraphBuilder(sampleRate: 48000, workDir: workDir);
  }

  String get _bg => FfEscape.color(p.background);

  // ------------------------------------------------------------------ fit
  /// Scales [in] to cover/contain a WxH (*k) canvas.
  String _fit(String inp, FitMode fit, int cw, int ch) {
    final out = b.label('fit');
    switch (fit) {
      case FitMode.cover:
        b.chains.add('[$inp]scale=$cw:$ch:force_original_aspect_ratio=increase:flags=bicubic,crop=$cw:$ch,setsar=1[$out]');
        break;
      case FitMode.contain:
        b.chains.add('[$inp]scale=$cw:$ch:force_original_aspect_ratio=decrease:flags=bicubic,pad=$cw:$ch:(ow-iw)/2:(oh-ih)/2:color=$_bg,setsar=1[$out]');
        break;
      case FitMode.stretch:
        b.chains.add('[$inp]scale=$cw:$ch:flags=bicubic,setsar=1[$out]');
        break;
      case FitMode.blurBackground:
        final a = b.label('ba'), c = b.label('bb'), bg = b.label('bg'), fg = b.label('fg');
        final sw = math.max(2, cw ~/ 4 ~/ 2 * 2), sh = math.max(2, ch ~/ 4 ~/ 2 * 2);
        b.chains.add('[$inp]split[$a][$c];'
            '[$a]scale=$sw:$sh:force_original_aspect_ratio=increase,crop=$sw:$sh,gblur=sigma=12,eq=brightness=-0.08:saturation=1.2,scale=$cw:$ch,setsar=1[$bg];'
            '[$c]scale=$cw:$ch:force_original_aspect_ratio=decrease:flags=bicubic,setsar=1[$fg];'
            '[$bg][$fg]overlay=(W-w)/2:(H-h)/2[$out]');
        break;
    }
    return out;
  }

  // --------------------------------------------------------------- motion
  /// Converts preset into keyframes over [dur].
  Motion _resolveMotion(Motion m, double dur) {
    if (m.hasKeyframes || m.preset == MotionPreset.none) return m;
    final i = m.intensity.clamp(0.0, 1.0);
    final z = 1 + 0.12 + 0.3 * i;
    Keyframe k(double t, double v, [Easing e = Easing.easeInOut]) => Keyframe(t, v, e);
    switch (m.preset) {
      case MotionPreset.kenBurnsIn:
        return Motion(zoom: [k(0, 1.0), k(dur, z)], panX: [k(0, 0.5), k(dur, 0.42 + 0.16 * ((dur * 7) % 1))], panY: [k(0, 0.5), k(dur, 0.45)]);
      case MotionPreset.kenBurnsOut:
        return Motion(zoom: [k(0, z), k(dur, 1.0)], panX: [k(0, 0.55), k(dur, 0.5)], panY: [k(0, 0.45), k(dur, 0.5)]);
      case MotionPreset.panLeft:
        return Motion(zoom: [k(0, z)], panX: [k(0, 1.0), k(dur, 0.0)], panY: [k(0, 0.5)]);
      case MotionPreset.panRight:
        return Motion(zoom: [k(0, z)], panX: [k(0, 0.0), k(dur, 1.0)], panY: [k(0, 0.5)]);
      case MotionPreset.panUp:
        return Motion(zoom: [k(0, z)], panX: [k(0, 0.5)], panY: [k(0, 1.0), k(dur, 0.0)]);
      case MotionPreset.panDown:
        return Motion(zoom: [k(0, z)], panX: [k(0, 0.5)], panY: [k(0, 0.0), k(dur, 1.0)]);
      case MotionPreset.diagonal:
        return Motion(zoom: [k(0, z)], panX: [k(0, 0.0), k(dur, 1.0)], panY: [k(0, 0.0), k(dur, 1.0)]);
      case MotionPreset.zoomInRotate:
        return Motion(zoom: [k(0, 1.25), k(dur, 1.25 + 0.3 * i)], rotation: [k(0, 0), k(dur, 4 + 8 * i)]);
      case MotionPreset.zoomOutRotate:
        return Motion(zoom: [k(0, 1.25 + 0.3 * i), k(dur, 1.25)], rotation: [k(0, 4 + 8 * i), k(dur, 0)]);
      case MotionPreset.parallax:
        // 2.5D approximation: simultaneous zoom-in and lateral drift.
        return Motion(zoom: [k(0, 1.1), k(dur, 1.1 + 0.25 * i)], panX: [k(0, 0.2), k(dur, 0.8)], panY: [k(0, 0.55), k(dur, 0.45)]);
      case MotionPreset.shake:
      case MotionPreset.beatPulse:
        return m; // handled with expressions
      case MotionPreset.none:
        return m;
    }
  }

  /// Applies zoompan/rotate motion. Input is a WxH*k canvas.
  String _motion(String inp, VisualClip c, double dur, int cw, int ch) {
    final m = _resolveMotion(c.motion, dur);
    final out = b.label('mot');
    final t = '(on/$fpsS)';
    String zExpr;
    String pxExpr = '0.5', pyExpr = '0.5';
    if (m.preset == MotionPreset.shake) {
      final a = 0.012 + 0.03 * m.intensity;
      zExpr = '1.12';
      pxExpr = '(0.5+${FfEscape.num(a)}*sin($t*23)+${FfEscape.num(a * 0.6)}*sin($t*37))';
      pyExpr = '(0.5+${FfEscape.num(a)}*cos($t*19)+${FfEscape.num(a * 0.5)}*sin($t*29))';
    } else if (m.preset == MotionPreset.beatPulse) {
      final music = opt.music;
      var period = 0.5, phase = 0.0;
      if (music != null && music.beats.length > 2) {
        period = 60 / music.bpm;
        phase = music.beats.first + opt.musicOffset;
      }
      // absolute timeline time of clip start is added by caller via _clipStart
      final abs = '($t+${fsec(_clipStart)})';
      zExpr = '(1.06*(1+${FfEscape.num(0.04 + 0.1 * m.intensity)}*exp(-9*mod(max($abs-${fsec(phase)},0),${fsec(period)}))))';
    } else {
      zExpr = m.zoom.isEmpty ? '1' : keyframeExpr(m.zoom, v: t);
      if (m.panX.isNotEmpty) pxExpr = keyframeExpr(m.panX, v: t);
      if (m.panY.isNotEmpty) pyExpr = keyframeExpr(m.panY, v: t);
    }
    // Entrance zoom/pop animations multiply the zoom.
    if (c.animIn == 'zoom' || c.animIn == 'pop') {
      final d = fsec(math.max(0.05, c.animInDur));
      final from = c.animIn == 'zoom' ? 1.6 : 1.25;
      zExpr = '($zExpr)*if(lt($t,$d),${FfEscape.num(from)}-${FfEscape.num(from - 1)}*$t/$d,1)';
    }
    b.chains.add("[$inp]fps=$fpsS,zoompan=z='max(1,$zExpr)':x='(iw-iw/zoom)*clip($pxExpr,0,1)':y='(ih-ih/zoom)*clip($pyExpr,0,1)':d=1:s=${W}x$H:fps=$fpsS[$out]");
    var cur = out;
    if (m.rotation.isNotEmpty || c.animIn == 'spin') {
      var a = m.rotation.isEmpty ? '0' : keyframeExpr(m.rotation, v: 't');
      if (c.animIn == 'spin') {
        final d = fsec(math.max(0.05, c.animInDur));
        a = '($a)+if(lt(t,$d),360*(1-t/$d),0)';
      }
      final r = b.label('rot');
      // Extra zoom hides rotated corners.
      b.chains.add("[$cur]rotate=a='($a)*PI/180':c=$_bg:ow=iw:oh=ih[$r]");
      cur = r;
    }
    return cur;
  }

  double _clipStart = 0;

  // ----------------------------------------------------------------- clip
  ({String v, String? a}) _clipSegment(VisualClip c, double dur) {
    String src;
    int? inputIdx;
    switch (c.kind) {
      case ClipKind.color:
        src = b.label('cc');
        b.chains.add('color=c=${FfEscape.color(c.color)}:s=${W}x$H:r=$fpsS:d=${fsec(dur + 0.5)}[$src]');
        break;
      case ClipKind.image:
        inputIdx = b.addInput(assets.pathOf(c.assetId!), pre: ['-loop', '1', '-framerate', fpsS, '-t', fsec(dur + 1)]);
        src = '$inputIdx:v';
        break;
      case ClipKind.video:
        final len = c.srcOut - c.srcIn;
        inputIdx = b.addInput(assets.pathOf(c.assetId!), pre: [
          if (c.loopVideo) ...['-stream_loop', '-1'],
          '-ss', fsec(c.srcIn),
          if (!c.loopVideo) ...['-t', fsec(len + 0.05)],
        ]);
        src = '$inputIdx:v';
        break;
    }
    final pre = <String>['setpts=PTS-STARTPTS'];
    if (c.kind == ClipKind.video) {
      if (c.reverse) pre.add('reverse');
      if ((c.speed - 1).abs() > 1e-3) pre.add('setpts=PTS/${FfEscape.num(c.speed, min: 0.05, max: 16)}');
    }
    switch (c.rotate % 360) {
      case 90:
        pre.add('transpose=1');
        break;
      case 180:
        pre.addAll(['hflip', 'vflip']);
        break;
      case 270:
        pre.add('transpose=2');
        break;
    }
    if (c.flipH) pre.add('hflip');
    if (c.flipV) pre.add('vflip');
    if (c.hasCrop) {
      pre.add('crop=iw*${FfEscape.num(c.cropW, min: 0.05, max: 1)}:ih*${FfEscape.num(c.cropH, min: 0.05, max: 1)}:iw*${FfEscape.num(c.cropX, min: 0, max: 0.95)}:ih*${FfEscape.num(c.cropY, min: 0, max: 0.95)}');
    }
    pre.add('format=yuv420p');
    var cur = b.label('src');
    b.chains.add('[$src]${pre.join(',')}[$cur]');
    // Freeze frame
    if (c.kind == ClipKind.video && c.freezeAt >= 0 && c.freezeDuration > 0) {
      final fa = (c.freezeAt - c.srcIn) / c.speed;
      final a = b.label('fza'), bb = b.label('fzb'), o = b.label('fz');
      b.chains.add('[$cur]split[$a][$bb];[$a]trim=end=${fsec(fa)},setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=${fsec(c.freezeDuration)}[${a}p];'
          '[$bb]trim=start=${fsec(fa)},setpts=PTS-STARTPTS[${bb}p];[${a}p][${bb}p]concat=n=2:v=1:a=0[$o]');
      cur = o;
    }
    final staticMotion = c.motion.isStatic && c.animIn != 'zoom' && c.animIn != 'pop' && c.animIn != 'spin';
    final k = staticMotion ? 1.0 : (c.kind == ClipKind.image ? 1.6 : 1.25);
    int even(double v) => (v / 2).round() * 2;
    final cw = even(W * k), ch = even(H * k);
    cur = _fit(cur, c.fit, cw, ch);
    if (!staticMotion) {
      cur = _motion(cur, c, dur, cw, ch);
    }
    final post = <String>[];
    final lut = c.grade.lutAssetId == null ? null : assets.pathOf(c.grade.lutAssetId!);
    post.addAll(c.grade.filters(lutPath: lut));
    post.addAll(['fps=$fpsS', 'format=yuv420p', 'setsar=1']);
    // pad short sources (e.g. video shorter than requested) with last frame
    post.add('tpad=stop_mode=clone:stop_duration=${fsec(dur)}');
    post.add('trim=duration=${fsec(dur)}');
    post.add('setpts=PTS-STARTPTS');
    if (c.animIn == 'fade') post.add('fade=t=in:st=0:d=${fsec(math.min(c.animInDur, dur / 2))}');
    if (c.animOut == 'fade') post.add('fade=t=out:st=${fsec(dur - math.min(c.animOutDur, dur / 2))}:d=${fsec(math.min(c.animOutDur, dur / 2))}');
    final o = b.label('seg');
    b.chains.add('[$cur]${post.join(',')}[$o]');
    cur = o;
    // Slide entrances via overlay on background colour.
    if (c.animIn.startsWith('slide')) {
      final d = fsec(math.max(0.05, c.animInDur));
      final e = '(1-min(t/$d,1))';
      final (xe, ye) = switch (c.animIn) {
        'slideLeft' => ('W*$e', '0'),
        'slideRight' => ('-W*$e', '0'),
        'slideUp' => ('0', 'H*$e'),
        _ => ('0', '-H*$e'),
      };
      final bg = b.label('sbg'), so = b.label('sl');
      b.chains.add('color=c=$_bg:s=${W}x$H:r=$fpsS:d=${fsec(dur)}[$bg];[$bg][$cur]overlay=x=\'$xe\':y=\'$ye\':eof_action=pass,setsar=1[$so]');
      cur = so;
    }
    // Clip audio
    String? aLabel;
    if (c.kind == ClipKind.video && p.clipAudio && !c.mute && inputIdx != null && assets.asset(c.assetId!).hasAudio) {
      final af = <String>['asetpts=PTS-STARTPTS', 'aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo'];
      if (c.reverse) af.add('areverse');
      if ((c.speed - 1).abs() > 1e-3) af.addAll(atempoChain(c.speed));
      final vol = c.volumeDb + p.clipAudioDb;
      if (vol.abs() > 1e-3) af.add('volume=${FfEscape.num(vol)}dB');
      af.addAll(['apad', 'atrim=duration=${fsec(dur)}', 'afade=t=in:d=0.02', 'afade=t=out:st=${fsec(math.max(0, dur - 0.05))}:d=0.05']);
      aLabel = b.label('ca');
      b.chains.add('[$inputIdx:a]${af.join(',')}[$aLabel]');
    }
    return (v: cur, a: aLabel);
  }

  // ------------------------------------------------------------- overlays
  String _overlay(String base, OverlayItem o, double total) {
    final asset = assets.asset(o.assetId);
    final path = assets.pathOf(o.assetId);
    final isVideo = asset.kind.name == 'video';
    final isGifLike = path.toLowerCase().endsWith('.gif') || path.toLowerCase().endsWith('.webp') || path.toLowerCase().endsWith('.webm') || path.toLowerCase().endsWith('.mov');
    final idx = b.addInput(path, pre: [
      if (!isVideo && !isGifLike) ...['-loop', '1', '-framerate', fpsS],
      if ((isVideo || isGifLike) && o.loop) ...['-stream_loop', '-1'],
      if (isVideo && o.srcIn > 0) ...['-ss', fsec(o.srcIn)],
      '-t', fsec(o.duration + 0.5),
    ]);
    final f = <String>['fps=$fpsS', 'format=rgba'];
    if (o.chromaKey) {
      f.add('chromakey=${FfEscape.color(o.keyColor)}:${FfEscape.num(o.keySimilarity, min: 0.01, max: 1)}:${FfEscape.num(o.keyBlend, min: 0, max: 1)}');
    }
    final wpx = math.max(2, (o.scale * W).round() ~/ 2 * 2);
    if (o.scaleKf.isNotEmpty || o.animIn == 'zoom' || o.animIn == 'pop' || o.animOut == 'zoom') {
      // per-frame size via sendcmd (scale supports runtime w/h commands)
      final vx = VfxContext(b, W, H, F, o.start + o.duration, workDir, null, 0);
      final inst = b.label('osc');
      final cmd = vx.sendcmdFile(inst, (v) => 'scale@$inst w ${math.max(2, (v * 4 * W).round() ~/ 2 * 2)}', env: (t) {
        final rel = t;
        var s = o.scaleKf.isEmpty ? o.scale : evalKeyframes(o.scaleKf, rel);
        if ((o.animIn == 'zoom' || o.animIn == 'pop') && rel < o.animInDur) s *= (rel / o.animInDur).clamp(0.05, 1.0);
        if (o.animOut == 'zoom' && rel > o.duration - o.animOutDur) s *= ((o.duration - rel) / o.animOutDur).clamp(0.05, 1.0);
        return (s / 4).clamp(0.0, 1.0);
      });
      f.add('sendcmd=f=$cmd');
      f.add('scale@$inst=w=$wpx:h=-2');
    } else {
      f.add('scale=w=$wpx:h=-2');
    }
    switch (o.mask) {
      case MaskShape.circle:
        f.add("geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='alpha(X,Y)*lte(hypot(X-W/2,Y-H/2),min(W,H)/2)'");
        break;
      case MaskShape.ellipse:
        f.add("geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='alpha(X,Y)*lte(pow((X-W/2)/(W/2),2)+pow((Y-H/2)/(H/2),2),1)'");
        break;
      case MaskShape.rounded:
        f.add("geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='alpha(X,Y)*lte(hypot(max(abs(X-W/2)-(W/2-min(W,H)*0.12),0),max(abs(Y-H/2)-(H/2-min(W,H)*0.12),0)),min(W,H)*0.12)'");
        break;
      case MaskShape.heart:
        f.add("geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='alpha(X,Y)*lte(pow(pow((X-W/2)/(W/2.2),2)+pow(-(Y-H/2.2)/(H/2.4),2)-1,3)-pow((X-W/2)/(W/2.2),2)*pow(-(Y-H/2.2)/(H/2.4),3),0)'");
        break;
      case MaskShape.star:
        f.add("geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='alpha(X,Y)*lte(hypot(X-W/2,Y-H/2),min(W,H)/2*(0.62+0.38*cos(5*atan2(Y-H/2,X-W/2))))'");
        break;
      case MaskShape.none:
        break;
    }
    if (o.borderWidth > 0 && o.mask == MaskShape.none) {
      final bw = math.max(1, (o.borderWidth * opt.scale).round());
      f.add('pad=iw+${bw * 2}:ih+${bw * 2}:$bw:$bw:color=${FfEscape.color(o.borderColor)}');
    }
    if (o.rotKf.isNotEmpty || o.rotation != 0 || o.animIn == 'spin') {
      var a = o.rotKf.isEmpty ? FfEscape.num(o.rotation) : keyframeExpr(o.rotKf, v: 't');
      if (o.animIn == 'spin') a = '($a)+if(lt(t,${fsec(o.animInDur)}),360*(1-t/${fsec(o.animInDur)}),0)';
      f.add("rotate=a='($a)*PI/180':c=none:ow='hypot(iw,ih)':oh=ow");
    }
    if (o.opacity < 1) f.add('colorchannelmixer=aa=${FfEscape.num(o.opacity, min: 0, max: 1)}');
    if (o.animIn == 'fade') f.add('fade=t=in:st=0:d=${fsec(o.animInDur)}:alpha=1');
    if (o.animOut == 'fade') f.add('fade=t=out:st=${fsec(math.max(0, o.duration - o.animOutDur))}:d=${fsec(o.animOutDur)}:alpha=1');
    f.add('trim=duration=${fsec(o.duration)}');
    f.add('setpts=PTS-STARTPTS+${fsec(o.start)}/TB');
    final ol = b.label('ov');
    b.chains.add('[$idx:v]${f.join(',')}[$ol]');
    final rt = '(t-${fsec(o.start)})';
    var xe = o.xKf.isEmpty ? '${FfEscape.num(o.x)}*W' : '(${keyframeExpr(o.xKf, v: rt)})*W';
    var ye = o.yKf.isEmpty ? '${FfEscape.num(o.y)}*H' : '(${keyframeExpr(o.yKf, v: rt)})*H';
    final d = fsec(math.max(0.05, o.animInDur));
    final e = '(1-min($rt/$d,1))';
    switch (o.animIn) {
      case 'slideLeft':
        xe = '$xe+W*$e';
        break;
      case 'slideRight':
        xe = '$xe-W*$e';
        break;
      case 'slideUp':
        ye = '$ye+H*$e';
        break;
      case 'slideDown':
        ye = '$ye-H*$e';
        break;
    }
    final out = b.label('ovo');
    b.chains.add("[$base][$ol]overlay=x='$xe-w/2':y='$ye-h/2':eof_action=pass:enable='between(t,${fsec(o.start)},${fsec(o.end)})'[$out]");
    // overlay audio (PIP video with sound)
    if (isVideo && !o.mute && asset.hasAudio) {
      final al = b.label('oa');
      b.chains.add('[$idx:a]asetpts=PTS-STARTPTS,aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,volume=${FfEscape.num(o.volumeDb)}dB,apad,atrim=duration=${fsec(o.duration)},adelay=delays=${(o.start * 1000).round()}:all=1[$al]');
      _extraAudio.add(al);
    }
    return out;
  }

  final _extraAudio = <String>[];

  // ---------------------------------------------------------------- build
  CompiledGraph compile() {
    workDir.createSync(recursive: true);
    final total = p.duration;
    if (total <= 0) throw MediaEngineException('Projekt jest pusty – dodaj zdjęcia, klipy lub muzykę.');
    final starts = p.clipStarts();
    String base;
    final clipAudios = <String>[];
    if (p.clips.isEmpty) {
      base = b.label('bgc');
      b.chains.add('color=c=$_bg:s=${W}x$H:r=$fpsS:d=${fsec(total)},format=yuv420p,setsar=1[$base]');
    } else {
      final segs = <String>[];
      for (var i = 0; i < p.clips.length; i++) {
        _clipStart = starts[i];
        final seg = _clipSegment(p.clips[i], p.clips[i].duration);
        segs.add(seg.v);
        if (seg.a != null) {
          final del = b.label('cad');
          final ms = (starts[i] * 1000).round();
          b.chains.add('[${seg.a}]${ms > 0 ? 'adelay=delays=$ms:all=1' : 'anull'}[$del]');
          clipAudios.add(del);
        }
      }
      var cur = segs.first;
      var acc = p.clips.first.duration;
      for (var i = 1; i < segs.length; i++) {
        final prev = p.clips[i - 1];
        final out = b.label('x');
        if (prev.transition.isCut) {
          b.chains.add('[$cur][${segs[i]}]concat=n=2:v=1:a=0[$out]');
          acc += p.clips[i].duration;
        } else {
          final td = p.effectiveTransition(i - 1);
          b.chains.add('[$cur][${segs[i]}]xfade=${xfadeOptions(prev.transition.type)}:duration=${fsec(td)}:offset=${fsec(acc - td)}[$out]');
          acc += p.clips[i].duration - td;
        }
        cur = out;
      }
      base = cur;
      if (total > acc + 1e-3) {
        final o = b.label('ext');
        b.chains.add('[$base]tpad=stop_mode=add:stop_duration=${fsec(total - acc)}:color=$_bg[$o]');
        base = o;
      }
    }
    // Global colour grade
    final gg = p.globalGrade.filters(lutPath: p.globalGrade.lutAssetId == null ? null : assets.pathOf(p.globalGrade.lutAssetId!));
    if (gg.isNotEmpty) {
      final o = b.label('gg');
      b.chains.add('[$base]${gg.join(',')}[$o]');
      base = o;
    }
    final vctx = VfxContext(b, W, H, F, total, workDir, opt.music, opt.musicOffset);
    for (final fx in p.vfx) {
      base = applyVfx(vctx, base, fx);
    }
    final ovs = [...p.overlays.where((o) => !o.hidden)]..sort((a, c) => a.layer.compareTo(c.layer));
    for (final o in ovs) {
      base = _overlay(base, o, total);
    }

    // ---------------- audio
    final audioParts = <String>[];
    final ac = AudioProjectCompiler(p.audio, assets);
    final hasAudioClips = p.audio.tracks.any((t) => t.clips.isNotEmpty && !t.muted);
    if (hasAudioClips) {
      // Audio project uses its own sample rate; force 48k for video.
      p.audio.sampleRate = 48000;
      final l = ac.compile(b);
      if (l != null) audioParts.add(l);
    }
    audioParts.addAll(clipAudios);
    audioParts.addAll(_extraAudio);
    String audio;
    if (audioParts.isEmpty) {
      audio = b.label('sil');
      b.chains.add('anullsrc=r=48000:cl=stereo,atrim=duration=${fsec(total)}[$audio]');
    } else {
      final mixed = b.label('amx');
      if (audioParts.length == 1) {
        b.chains.add('[${audioParts.first}]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,apad,atrim=duration=${fsec(total)}[$mixed]');
      } else {
        b.chains.add('${audioParts.map((e) => '[$e]').join()}amix=inputs=${audioParts.length}:normalize=0:duration=longest:dropout_transition=0,apad,atrim=duration=${fsec(total)}[$mixed]');
      }
      audio = mixed;
    }
    // Visualisers need copies of the final mix
    final vis = p.visualizers;
    if (vis.isNotEmpty) {
      final copies = [for (var i = 0; i <= vis.length; i++) b.label('as')];
      b.chains.add('[$audio]asplit=${copies.length}${copies.map((e) => '[$e]').join()}');
      audio = copies.first;
      for (var i = 0; i < vis.length; i++) {
        final v = vis[i];
        base = applyVisualizer(vctx, base, copies[i + 1], v, v.logoAssetId == null ? null : assets.pathOf(v.logoAssetId!));
      }
    }

    // ---------------- text, lyrics (libass)
    final ass = AssBuilder(W, H);
    for (final t in p.texts.where((t) => !t.hidden)) {
      ass.addText(t);
    }
    if (p.lyrics != null && p.lyrics!.lines.isNotEmpty) {
      final st = TextStyleSpec.fromJson(p.lyrics!.style);
      ass.addLyrics(p.lyrics!, st, songDuration: total);
    }
    if (!ass.isEmpty) {
      final f = File('${workDir.path}/text_${DateTime.now().microsecondsSinceEpoch}.ass');
      f.writeAsStringSync(ass.build());
      final o = b.label('txt');
      b.chains.add('[$base]subtitles=filename=${FfEscape.escapePath(f.path)}:fontsdir=${FfEscape.escapePath(opt.fontsDir)}[$o]');
      base = o;
    }
    final fin = b.label('vout');
    b.chains.add('[$base]fps=$fpsS,format=yuv420p,setsar=1,trim=duration=${fsec(total)}[$fin]');
    return CompiledGraph(b.inputs, b.graph, fin, audio, total, W, H, F);
  }
}

/// High level renderer with encoder fallback, progress and cancellation.
class VideoRenderer {
  final MediaRunner runner;
  final Directory workDir;
  final String fontsDir;
  Set<String>? _encoders;
  VideoRenderer(this.runner, this.workDir, this.fontsDir);

  Future<Set<String>> availableEncoders() async {
    if (_encoders != null) return _encoders!;
    final r = await runner.ffmpeg(['-encoders']);
    final set = <String>{};
    for (final l in r.log.split('\n')) {
      final m = RegExp(r'^\s*[VAS][F.][S.][X.][B.][D.]\s+(\S+)').firstMatch(l);
      if (m != null) set.add(m.group(1)!);
    }
    return _encoders = set;
  }

  List<String> buildArgs(CompiledGraph g, VideoExportSettings s, String out, String encoder) {
    // Graph is kept for diagnostics; passed inline (FFmpegKit runs in-process,
    // so no command-line length limit applies; works with FFmpeg 6–8).
    final graphFile = File('${workDir.path}/last_graph.txt');
    graphFile.writeAsStringSync(g.graph);
    if (s.container == VideoContainer.gif) {
      final gw = s.gifWidth ~/ 2 * 2;
      final extra = ';[${g.videoLabel}]fps=${FfEscape.num(s.gifFps)},scale=$gw:-2:flags=lanczos,split[ga][gb];[ga]palettegen=stats_mode=diff[gp];[gb][gp]paletteuse=dither=bayer:bayer_scale=4[gif]';
      return [
        ...g.inputs,
        '-filter_complex', g.graph + extra,
        '-map', '[gif]',
        if (s.rangeStart != null) ...['-ss', fsec(s.rangeStart!)],
        if (s.rangeEnd != null) ...['-to', fsec(s.rangeEnd!)],
        '-loop', '0',
        out,
      ];
    }
    return [
      ...g.inputs,
      '-filter_complex', g.graph,
      '-map', '[${g.videoLabel}]',
      '-map', '[${g.audioLabel}]',
      if (s.rangeStart != null) ...['-ss', fsec(s.rangeStart!)],
      if (s.rangeEnd != null) ...['-to', fsec(s.rangeEnd!)],
      ...s.videoArgs(encoder),
      ...s.audioArgs(),
      '-r', FfEscape.num(g.fps),
      '-t', fsec(g.duration),
      '-metadata', 'encoder=WoJan Media Studio',
      out,
    ];
  }

  /// Renders with automatic fallback from hardware to software encoders.
  Future<String> render(VideoProject p, AssetResolver assets, VideoExportSettings s, String out,
      {AudioAnalysis? music, double musicOffset = 0, ProgressCb? onProgress, CancelToken? cancel, bool preview = false}) async {
    await workDir.create(recursive: true);
    final scale = s.width / p.width;
    final g = VideoCompiler(p, assets, workDir, CompileOptions(scale: scale, fps: s.fps, fontsDir: fontsDir, music: music, musicOffset: musicOffset)).compile();
    final encs = s.container == VideoContainer.gif ? ['gif'] : s.encoderCandidates(await availableEncoders());
    if (encs.isEmpty) throw MediaEngineException('Brak dostępnego enkodera dla ${s.codec.name}');
    MediaEngineException? last;
    for (final enc in encs) {
      final r = await runner.ffmpeg(buildArgs(g, s, out, enc), onProgress: onProgress, cancel: cancel);
      if (r.cancelled) throw MediaEngineException('Renderowanie anulowane');
      if (r.ok) return enc;
      last = MediaEngineException('Renderowanie nie powiodło się (enkoder $enc)', r.errorSummary);
      if (!enc.contains('_')) break; // software encoder failed: no further fallback
    }
    throw last!;
  }
}
