import 'dart:io';
import 'dart:math' as math;

import '../audio/audio_compiler.dart';
import '../dsp/analysis.dart';
import '../ffmpeg/escape.dart';
import '../util/json_util.dart';
import 'model.dart';
import 'vfx_library.dart';

/// Catalogue of visual effects. All are procedurally generated with FFmpeg
/// filters (no third-party licensed assets).
const vfxNames = <String, String>{
  'snow': 'Śnieg',
  'rain': 'Deszcz',
  'sparks': 'Iskry',
  'fire': 'Ogień',
  'smoke': 'Dym',
  'fog': 'Mgła',
  'dust': 'Kurz',
  'ash': 'Popiół',
  'particles': 'Cząsteczki (bokeh)',
  'lightning': 'Błyskawice',
  'lights': 'Światła (light leaks)',
  'flare': 'Flara obiektywu',
  'neon': 'Neon',
  'glitch': 'Glitch',
  'vhs': 'VHS',
  'retro': 'Retro',
  'cinematic': 'Kinowy (pasy + grading)',
  'oldfilm': 'Stary film',
  'blur': 'Rozmycie',
  'vignette': 'Winieta',
  'tilt3d': 'Pochylenie 3D',
  'frame': 'Animowana ramka',
  'beatflash': 'Błysk na bit (muzyka)',
  'bassglow': 'Jasność wg basu (muzyka)',
  'mirror': 'Lustro',
  'kaleido': 'Kalejdoskop',
  'rgbsplit': 'Rozszczepienie RGB',
  'pixelate': 'Pikselizacja',
};

/// Every effect: procedural FFmpeg effects + the texture/impact library.
final allVfxNames = <String, String>{...vfxNames, ...vfxLibraryNames};

/// Effects that react to the music signal when `reactive` is set.
const reactiveCapable = {'tex_hearts_red', 'tex_sparkles', 'tex_stars_gold', 'tex_confetti', 'tex_notes', 'tex_bokeh', 'tex_gold_dust', 'snow', 'sparks', 'particles', 'dust', 'ash', 'rain', 'lightning', 'lights', 'flare', 'glitch', 'beatflash', 'bassglow', 'neon', 'rgbsplit', 'frame'};

class VfxContext {
  final AudioGraphBuilder b;
  final int w, h;
  final double fps, duration;
  final Directory workDir;
  final AudioAnalysis? music;
  final double musicOffset; // timeline time where analysed music starts
  VfxContext(this.b, this.w, this.h, this.fps, this.duration, this.workDir, this.music, this.musicOffset);

  /// Beat times on the project timeline.
  List<double> get beats => music == null ? const [] : [for (final t in music!.beats) t + musicOffset];
  List<double> get onsets => music == null ? const [] : [for (final t in music!.onsets) t + musicOffset];

  /// Writes a sendcmd script with per-frame values of [env] (0..1) mapped
  /// through [fmt] → command text. Returns escaped path for `sendcmd=f=`.
  String sendcmdFile(String name, String Function(double v) fmt, {double Function(double t)? env, double rate = 0}) {
    final f = File('${workDir.path}/$name.cmd');
    final sb = StringBuffer();
    final r = rate > 0 ? rate : math.min(fps, 30.0);
    String? last;
    for (var i = 0; i * (1 / r) < duration; i++) {
      final t = i / r;
      final v = env!(t).clamp(0.0, 1.0);
      final c = fmt(v);
      if (c != last) {
        sb.writeln('${fsec(t)} $c;');
        last = c;
      }
    }
    workDir.createSync(recursive: true);
    f.writeAsStringSync(sb.toString());
    return FfEscape.escapePath(f.path);
  }

  double bassAt(double t) => music == null ? 0 : music!.valueAt(music!.bass, t - musicOffset);
  double energyAt(double t) => music == null ? 0 : music!.valueAt(music!.rms, t - musicOffset);

  /// Beat envelope: 1 at each beat decaying exponentially.
  double beatEnv(double t, {double decay = 8}) {
    final bs = beats;
    if (bs.isEmpty) return 0;
    var lo = 0, hi = bs.length - 1, idx = -1;
    while (lo <= hi) {
      final m = (lo + hi) >> 1;
      if (bs[m] <= t) {
        idx = m;
        lo = m + 1;
      } else {
        hi = m - 1;
      }
    }
    if (idx < 0) return 0;
    return math.exp(-(t - bs[idx]) * decay);
  }
}

String _c(String hex) => FfEscape.color(hex);

/// Particle layer (grey alpha) generated from a random `life` frame scrolled.
String _particleAlpha(VfxContext x, {required double density, required int cell, required double blur, required double vx, required double vy, double gain = 4, double stretchV = 0, int seed = 1}) {
  final gw = (x.w / cell).ceil(), gh = (x.h / cell).ceil();
  final l = x.b.label('pa');
  final st = stretchV > 0 ? ',gblur=sigma=0.5:sigmaV=${FfEscape.num(stretchV)}' : '';
  x.b.chains.add('life=s=${gw}x$gh:random_fill_ratio=${FfEscape.num(density)}:mold=0:rate=${FfEscape.num(x.fps)}:seed=$seed:death_color=black:life_color=white,'
      'trim=end_frame=1,scale=${x.w}:${x.h}:flags=neighbor,format=gray,gblur=sigma=${FfEscape.num(blur)}$st,'
      "lut=c0='min(255,val*${FfEscape.num(gain)})',loop=loop=-1:size=1,"
      'trim=duration=${fsec(x.duration)},scroll=h=${FfEscape.num(vx)}:v=${FfEscape.num(vy)}[$l]');
  return l;
}

/// Low-frequency noise alpha (fog/smoke/fire).
String _cloudAlpha(VfxContext x, {required double vx, required double vy, int grid = 24, double blur = 40, int seed = 3, double gain = 1.5}) {
  final gw = math.max(4, x.w ~/ grid), gh = math.max(4, x.h ~/ grid);
  final l = x.b.label('cl');
  x.b.chains.add('life=s=${gw}x$gh:random_fill_ratio=0.5:mold=0:rate=${FfEscape.num(x.fps)}:seed=$seed:death_color=black:life_color=white,'
      'trim=end_frame=1,scale=${x.w}:${x.h}:flags=bicubic,format=gray,gblur=sigma=${FfEscape.num(blur)},'
      "lut=c0='min(255,max(0,(val-60)*${FfEscape.num(gain)}))',loop=loop=-1:size=1,"
      'trim=duration=${fsec(x.duration)},scroll=h=${FfEscape.num(vx)}:v=${FfEscape.num(vy)}[$l]');
  return l;
}

/// Colours an alpha layer and overlays it on [base] in [start,end].
String _overlayAlpha(VfxContext x, String base, String alpha, String color, double opacity, VfxItem it, {(String, String)? reactiveCmd}) {
  final col = x.b.label('col'), lay = x.b.label('lay'), out = x.b.label('vo');
  x.b.chains.add('color=c=${_c(color)}:s=${x.w}x${x.h}:r=${FfEscape.num(x.fps)}:d=${fsec(x.duration)},format=rgba[$col]');
  final react = reactiveCmd == null ? '' : 'sendcmd=f=${reactiveCmd.$1},';
  final ccm = reactiveCmd == null ? 'colorchannelmixer' : 'colorchannelmixer@${reactiveCmd.$2}';
  x.b.chains.add('[$col][$alpha]alphamerge,$react$ccm=aa=${FfEscape.num(opacity)}[$lay]');
  final (s, e) = _range(x, it);
  x.b.chains.add("[$base][$lay]overlay=x=0:y=0:eof_action=pass:enable='between(t,${fsec(s)},${fsec(e)})'[$out]");
  return out;
}

(double, double) _range(VfxContext x, VfxItem it) => (it.start, it.duration > 0 ? it.start + it.duration : x.duration);

String _filterOnBase(VfxContext x, String base, String filters, VfxItem it) {
  final (s, e) = _range(x, it);
  final out = x.b.label('vf');
  // Apply only in range: split, filter, overlay with enable.
  if (s <= 0.001 && e >= x.duration - 0.001) {
    x.b.chains.add('[$base]$filters[$out]');
  } else {
    final a = x.b.label('sa'), bb = x.b.label('sb'), f = x.b.label('sf');
    x.b.chains.add('[$base]split[$a][$bb];[$bb]$filters[$f];[$a][$f]overlay=enable=\'between(t,${fsec(s)},${fsec(e)})\'[$out]');
  }
  return out;
}

/// Applies a multi-chain effect built by [build] only within the item range.
String _complexOnBase(VfxContext x, String base, String Function(String inLabel) build, VfxItem it) {
  final (s, e) = _range(x, it);
  final a = x.b.label('ca'), bb = x.b.label('cb'), out = x.b.label('co');
  x.b.chains.add('[$base]split[$a][$bb]');
  final fx = build(bb);
  x.b.chains.add("[$a][$fx]overlay=enable='between(t,${fsec(s)},${fsec(e)})'[$out]");
  return out;
}

String _timesEnable(List<double> ts, double len) {
  if (ts.isEmpty) return '0';
  return ts.take(400).map((t) => 'between(t,${fsec(t)},${fsec(t + len)})').join('+');
}

/// Applies one VFX item to the [base] video label; returns new label.
String applyVfx(VfxContext x, String base, VfxItem it) {
  final lib = applyLibraryVfx(x, base, it);
  if (lib != null) return lib;
  final i = it.intensity.clamp(0.0, 1.0);
  final react = it.reactive && x.music != null;
  (String, String)? aaCmd(double baseOp, {bool useBeats = false}) {
    if (!react) return null;
    final inst = x.b.label('ccm');
    final path = x.sendcmdFile(inst, (v) => 'colorchannelmixer@$inst aa ${FfEscape.num(baseOp * (0.25 + 0.75 * v))}',
        env: (t) => useBeats ? math.max(x.beatEnv(t, decay: 5), x.energyAt(t) * 0.5) : x.energyAt(t));
    return (path, inst);
  }
  switch (it.type) {
    case 'snow':
      final a1 = _particleAlpha(x, density: 0.002 + 0.006 * i, cell: 4, blur: 2.5, vx: 0.0004, vy: -0.0025, seed: 11);
      final a2 = _particleAlpha(x, density: 0.0015 + 0.004 * i, cell: 7, blur: 4, vx: -0.0003, vy: -0.0045, seed: 7, gain: 3);
      final m = x.b.label('sn');
      x.b.chains.add('[$a1][$a2]blend=all_mode=lighten[$m]');
      return _overlayAlpha(x, base, m, it.color, 0.9, it, reactiveCmd: aaCmd(0.9));
    case 'rain':
      final a = _particleAlpha(x, density: 0.004 + 0.01 * i, cell: 2, blur: 0.3, vx: 0.002, vy: -0.03, stretchV: 9, gain: 6, seed: 5);
      return _overlayAlpha(x, base, a, it.color == '#FFFFFF' ? '#CFE3FF' : it.color, 0.55, it, reactiveCmd: aaCmd(0.55));
    case 'sparks':
      final a = _particleAlpha(x, density: 0.002 + 0.005 * i, cell: 3, blur: 1.2, vx: 0.001, vy: 0.006, gain: 6, seed: 9);
      return _overlayAlpha(x, base, a, it.color == '#FFFFFF' ? '#FF9A2E' : it.color, 1, it, reactiveCmd: aaCmd(1, useBeats: true));
    case 'dust':
      final a = _particleAlpha(x, density: 0.002 + 0.004 * i, cell: 2, blur: 0.8, vx: 0.0006, vy: 0.0004, gain: 3, seed: 13);
      return _overlayAlpha(x, base, a, it.color == '#FFFFFF' ? '#E8D9B8' : it.color, 0.6, it, reactiveCmd: aaCmd(0.6));
    case 'ash':
      final a = _particleAlpha(x, density: 0.001 + 0.003 * i, cell: 6, blur: 2, vx: 0.0008, vy: -0.0012, gain: 2.5, seed: 21);
      return _overlayAlpha(x, base, a, it.color == '#FFFFFF' ? '#9A9A9A' : it.color, 0.8, it, reactiveCmd: aaCmd(0.8));
    case 'particles':
      final a = _particleAlpha(x, density: 0.0008 + 0.002 * i, cell: 14, blur: 9, vx: 0.0005, vy: 0.0008, gain: 2.2, seed: 17);
      return _overlayAlpha(x, base, a, it.color == '#FFFFFF' ? '#FFD27A' : it.color, 0.7, it, reactiveCmd: aaCmd(0.7, useBeats: true));
    case 'fog':
      final a = _cloudAlpha(x, vx: 0.0015, vy: 0, seed: 4);
      return _overlayAlpha(x, base, a, it.color == '#FFFFFF' ? '#DDE3EA' : it.color, 0.25 + 0.45 * i, it);
    case 'smoke':
      final a = _cloudAlpha(x, vx: 0.0005, vy: 0.003, grid: 18, blur: 30, seed: 8);
      return _overlayAlpha(x, base, a, it.color == '#FFFFFF' ? '#8C8C8C' : it.color, 0.3 + 0.5 * i, it);
    case 'fire':
      final n = _cloudAlpha(x, vx: 0.0, vy: 0.02, grid: 14, blur: 10, seed: 2, gain: 2.2);
      final mask = x.b.label('fm'), al = x.b.label('fa');
      x.b.chains.add("color=c=black:s=${x.w}x${x.h}:r=${FfEscape.num(x.fps)}:d=1,format=gray,geq=lum='255*pow(clip((Y/H-0.45)/0.55,0,1),1.6)',loop=loop=-1:size=1,trim=duration=${fsec(x.duration)}[$mask]");
      x.b.chains.add('[$n][$mask]blend=all_mode=multiply[$al]');
      final col = x.b.label('fc'), lay = x.b.label('fl'), out = x.b.label('fo');
      x.b.chains.add("color=c=0xFF7A1A:s=${x.w}x${x.h}:r=${FfEscape.num(x.fps)}:d=${fsec(x.duration)},format=rgba,geq=r='255':g='90+100*(1-Y/H)':b='20':a='255'[$col]");
      x.b.chains.add('[$col][$al]alphamerge,colorchannelmixer=aa=${FfEscape.num(0.6 + 0.4 * i)}[$lay]');
      final (s, e) = _range(x, it);
      x.b.chains.add("[$base][$lay]overlay=enable='between(t,${fsec(s)},${fsec(e)})'[$out]");
      return out;
    case 'lightning':
      final times = react
          ? [for (final t in x.onsets) if (x.music!.valueAt(x.music!.onsetEnv, t - x.musicOffset) > 0.8) t]
          : [for (var t = 1.3; t < x.duration; t += 3.7 + (t * 7) % 2.1) t];
      final en = _timesEnable(times, 0.07);
      final en2 = _timesEnable([for (final t in times) t + 0.12], 0.05);
      return _filterOnBase(x, base, "eq=brightness=${FfEscape.num(0.35 + 0.4 * i)}:contrast=1.3:enable='$en',eq=brightness=${FfEscape.num(0.2 * i + 0.1)}:enable='$en2',colorbalance=bs=0.2:enable='$en'", it);
    case 'beatflash':
      final en = _timesEnable(x.beats.isEmpty ? [for (var t = 0.0; t < x.duration; t += 0.5) t] : x.beats, 0.06);
      return _filterOnBase(x, base, "eq=brightness=${FfEscape.num(0.15 + 0.3 * i)}:enable='$en'", it);
    case 'bassglow':
      final inst = x.b.label('eqb');
      final cmd = x.sendcmdFile(inst, (v) => 'eq@$inst brightness ${FfEscape.num(v * 0.18 * (0.3 + i))}, eq@$inst saturation ${FfEscape.num(1 + v * 0.5 * i)}', env: x.bassAt);
      return _filterOnBase(x, base, 'sendcmd=f=$cmd,eq@$inst=brightness=0:saturation=1', it);
    case 'lights':
      final g = x.b.label('lg'), out = x.b.label('lo');
      x.b.chains.add('gradients=s=${x.w}x${x.h}:r=${FfEscape.num(x.fps)}:d=${fsec(x.duration)}:type=radial:speed=0.015:c0=0xFF8A00:c1=0x000000:c2=0xFF2E6B:c3=0x000000:nb_colors=4:seed=5,format=rgba[$g]');
      final (s, e) = _range(x, it);
      x.b.chains.add("[$base][$g]blend=all_mode=screen:all_opacity=${FfEscape.num(0.25 + 0.45 * i)}:enable='between(t,${fsec(s)},${fsec(e)})'[$out]");
      return out;
    case 'flare':
      final fl = x.b.label('fr'), out = x.b.label('fo');
      final r = (math.min(x.w, x.h) * 0.5).round();
      x.b.chains.add("color=c=black:s=${x.w}x${x.h}:r=${FfEscape.num(x.fps)}:d=1,format=gray,geq=lum='255*exp(-((X-W*0.75)*(X-W*0.75)+(Y-H*0.2)*(Y-H*0.2))/(2*$r*$r/9))',loop=loop=-1:size=1,trim=duration=${fsec(x.duration)},scroll=h=0.0015[$fl]");
      final col = x.b.label('fc'), lay = x.b.label('fly');
      x.b.chains.add('color=c=${_c(it.color == '#FFFFFF' ? '#FFE7B0' : it.color)}:s=${x.w}x${x.h}:r=${FfEscape.num(x.fps)}:d=${fsec(x.duration)},format=rgba[$col]');
      final cmd = aaCmd(0.8, useBeats: true);
      x.b.chains.add('[$col][$fl]alphamerge,${cmd == null ? '' : 'sendcmd=f=${cmd.$1},'}colorchannelmixer${cmd == null ? '' : '@${cmd.$2}'}=aa=${FfEscape.num(0.5 + 0.4 * i)}[$lay]');
      final (s, e) = _range(x, it);
      x.b.chains.add("[$base][$lay]overlay=enable='between(t,${fsec(s)},${fsec(e)})'[$out]");
      return out;
    case 'neon':
      return _complexOnBase(x, base, (inp) {
        final d = x.b.label('nd'), g = x.b.label('ng'), ed = x.b.label('ne'), out = x.b.label('no');
        x.b.chains.add('[$inp]split[$d][$g];[$g]edgedetect=low=0.08:high=0.25:mode=colormix,hue=h=t*40,eq=saturation=2.2:brightness=0.05,gblur=sigma=1.5[$ed];'
            '[$d]eq=brightness=-0.25:saturation=0.6[${d}x];[${d}x][$ed]blend=all_mode=screen:all_opacity=${FfEscape.num(0.6 + 0.4 * i)}[$out]');
        return out;
      }, it);
    case 'glitch':
      final times = react ? x.beats.where((t) => x.beatEnv(t) > 0).toList() : [for (var t = 0.4; t < x.duration; t += 1.6 + (t * 13) % 1.3) t];
      final en = _timesEnable(times, 0.12);
      final en2 = _timesEnable([for (final t in times) t + 0.04], 0.05);
      final sh = (8 + 20 * i).round();
      return _filterOnBase(x, base, "rgbashift=rh=$sh:bh=-$sh:gv=${sh ~/ 3}:enable='$en',noise=alls=${(20 + 40 * i).round()}:allf=t:enable='$en2',hue=h=90:enable='$en2'", it);
    case 'rgbsplit':
      final sh = (3 + 10 * i).round();
      return _filterOnBase(x, base, 'rgbashift=rh=$sh:bh=-$sh', it);
    case 'vhs':
      return _filterOnBase(x, base, 'chromashift=cbh=${(2 + 4 * i).round()}:crh=-${(2 + 4 * i).round()},noise=alls=${(8 + 14 * i).round()}:allf=t,gblur=sigma=0.7,eq=saturation=1.25:contrast=1.05,drawgrid=w=iw:h=3:t=1:c=black@${FfEscape.num(0.15 + 0.2 * i)}', it);
    case 'retro':
      return _filterOnBase(x, base, 'curves=preset=vintage,eq=saturation=0.85,noise=alls=${(6 + 10 * i).round()}:allf=t,vignette=angle=0.5', it);
    case 'cinematic':
      final bar = (x.h * (0.06 + 0.06 * i)).round();
      return _filterOnBase(x, base, 'colorbalance=rs=-0.08:bs=0.12:rh=0.1:bh=-0.08,eq=contrast=1.08,vignette=angle=0.35,drawbox=x=0:y=0:w=iw:h=$bar:color=black:t=fill,drawbox=x=0:y=ih-$bar:w=iw:h=$bar:color=black:t=fill', it);
    case 'oldfilm':
      return _filterOnBase(x, base,
          "colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131,noise=alls=${(15 + 20 * i).round()}:allf=t,eq=eval=frame:brightness='0.04*sin(t*47)*${FfEscape.num(i)}',vignette=angle=0.6,"
          "drawbox=x='mod(t*937,iw)':y=0:w=2:h=ih:color=white@0.35:t=fill:enable='lt(mod(t,0.9),0.3)',drawbox=x='mod(t*577+300,iw)':y=0:w=1:h=ih:color=black@0.4:t=fill:enable='lt(mod(t,1.3),0.2)'",
          it);
    case 'blur':
      return _filterOnBase(x, base, 'gblur=sigma=${FfEscape.num(2 + 18 * i)}', it);
    case 'vignette':
      return _filterOnBase(x, base, 'vignette=angle=${FfEscape.num(0.2 + 0.8 * i)}', it);
    case 'tilt3d':
      final d = (0.04 + 0.08 * i);
      String e(String base0, String sgn) => "'$base0$sgn${FfEscape.num(d)}*W*sin(in/${FfEscape.num(x.fps)}*1.3)'";
      return _filterOnBase(x, base, 'perspective=x0=${e('0', '+')}:y0=0:x1=${e('W', '-')}:y1=0:x2=${e('0', '-')}:y2=H:x3=${e('W', '+')}:y3=H:interpolation=linear:eval=frame', it);
    case 'frame':
      final th = (math.min(x.w, x.h) * (0.015 + 0.03 * i)).round();
      final fr = x.b.label('frm'), out = x.b.label('fro');
      x.b.chains.add('color=c=${_c(it.color == '#FFFFFF' ? '#35D0BA' : it.color)}:s=${x.w}x${x.h}:r=${FfEscape.num(x.fps)}:d=${fsec(x.duration)},format=rgba,'
          'drawbox=x=$th:y=$th:w=iw-${th * 2}:h=ih-${th * 2}:color=black@0:t=fill:replace=1,hue=h=t*60[$fr]');
      final (s, e) = _range(x, it);
      x.b.chains.add("[$base][$fr]overlay=enable='between(t,${fsec(s)},${fsec(e)})'[$out]");
      return out;
    case 'mirror':
      return _complexOnBase(x, base, (inp) {
        final a = x.b.label('ma'), bb = x.b.label('mb'), out = x.b.label('mo');
        x.b.chains.add('[$inp]split[$a][$bb];[$bb]crop=iw/2:ih:0:0,hflip[${bb}h];[$a][${bb}h]overlay=x=W/2:y=0[$out]');
        return out;
      }, it);
    case 'kaleido':
      return _complexOnBase(x, base, (inp) {
        final a = x.b.label('ka'), out = x.b.label('ko');
        x.b.chains.add('[$inp]crop=iw/2:ih/2:0:0,split=4[${a}1][${a}2][${a}3][${a}4];[${a}2]hflip[${a}h];[${a}3]vflip[${a}v];[${a}4]hflip,vflip[${a}hv];'
            '[${a}1][${a}h]hstack[${a}t];[${a}v][${a}hv]hstack[${a}b];[${a}t][${a}b]vstack,scale=${x.w}:${x.h}[$out]');
        return out;
      }, it);
    case 'pixelate':
      final px = (8 + 40 * i).round();
      return _filterOnBase(x, base, 'scale=iw/$px:ih/$px:flags=neighbor,scale=${x.w}:${x.h}:flags=neighbor', it);
  }
  return base;
}
