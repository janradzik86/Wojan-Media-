import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../ffmpeg/escape.dart';
import '../util/json_util.dart';
import 'model.dart';
import 'vfx.dart';

const visualizerNames = <String, String>{
  'bars': 'Słupki częstotliwości',
  'line': 'Klasyczne spektrum liniowe',
  'dots': 'Punkty spektrum',
  'circle': 'Spektrum kołowe',
  'wave': 'Animowana fala audio',
  'wavebars': 'Fala – słupki',
  'oscilloscope': 'Oscyloskop (XY)',
  'spectrogram': 'Spektrogram przewijany',
  'cqt': 'Spektrum CQT (nuty)',
  'volume': 'Mierniki poziomu',
};

String _hex(String c) => FfEscape.color(c);

/// Generates remap maps (16-bit PGM) converting a linear spectrum image
/// (sw×sh, bars growing upward) into a circular ring of size s×s.
(String, String) polarMaps(Directory dir, int s, int sw, int sh, {double inner = 0.28, double outer = 0.5}) {
  final key = '${s}_${sw}_${sh}_${inner}_$outer';
  final xf = File('${dir.path}/polx_$key.pgm'), yf = File('${dir.path}/poly_$key.pgm');
  if (xf.existsSync() && yf.existsSync()) return (xf.path, yf.path);
  dir.createSync(recursive: true);
  final header = 'P5\n$s $s\n65535\n'.codeUnits;
  final xd = ByteData(s * s * 2), yd = ByteData(s * s * 2);
  final c = s / 2;
  final r0 = s * inner, r1 = s * outer;
  for (var y = 0; y < s; y++) {
    for (var x = 0; x < s; x++) {
      final dx = x - c, dy = y - c;
      final r = math.sqrt(dx * dx + dy * dy);
      var mx = 0, my = 0;
      if (r >= r0 && r <= r1) {
        var a = math.atan2(dx, -dy); // 0 at top, clockwise
        if (a < 0) a += 2 * math.pi;
        // mirror: 0..π → low..high freq, π..2π → high..low
        final f = a <= math.pi ? a / math.pi : (2 * math.pi - a) / math.pi;
        mx = (f * (sw - 1)).round().clamp(0, sw - 1);
        my = ((1 - (r - r0) / (r1 - r0)) * (sh - 1)).round().clamp(0, sh - 1);
      }
      final o = (y * s + x) * 2;
      xd.setUint16(o, mx, Endian.big);
      yd.setUint16(o, my, Endian.big);
    }
  }
  xf.writeAsBytesSync([...header, ...xd.buffer.asUint8List()]);
  yf.writeAsBytesSync([...header, ...yd.buffer.asUint8List()]);
  return (xf.path, yf.path);
}

/// Builds visualiser layer from audio label [audio] and overlays on [base].
String applyVisualizer(VfxContext x, String base, String audio, VisualizerItem v, String? logoPath) {
  final b = x.b;
  final rw = math.max(16, (v.width * x.w).round() ~/ 2 * 2);
  final rh = math.max(16, (v.height * x.h).round() ~/ 2 * 2);
  final px = (v.x * x.w).round(), py = (v.y * x.h).round();
  final fps = FfEscape.num(x.fps);
  final c1 = FfEscape.color(v.color), c2 = FfEscape.color(v.color2);
  final gain = FfEscape.num(v.intensity.clamp(0.1, 4));
  final a = b.label('va'), vis = b.label('vv');
  b.chains.add('[$audio]aformat=channel_layouts=stereo,volume=$gain[$a]');
  String keyed(String chain) => '$chain,format=rgba,colorkey=black:0.08:0.15,colorchannelmixer=aa=${FfEscape.num(v.opacity)}';
  switch (v.style) {
    case 'line':
    case 'dots':
    case 'bars':
      final mode = v.style == 'bars' ? 'bar' : v.style == 'dots' ? 'dot' : 'line';
      b.chains.add('[$a]${keyed('aformat=channel_layouts=mono,showfreqs=s=${rw}x$rh:rate=$fps:mode=$mode:ascale=log:fscale=log:win_size=2048:cmode=combined:colors=${_hex(v.color)}|${_hex(v.color2)}')}[$vis]');
      break;
    case 'circle':
      final s = math.min(rw, rh) ~/ 2 * 2;
      final (xm, ym) = polarMaps(x.workDir, s, 512, 128);
      final xi = b.addInput(xm, pre: ['-loop', '1', '-framerate', fps]);
      final yi = b.addInput(ym, pre: ['-loop', '1', '-framerate', fps]);
      final sp = b.label('sp');
      b.chains.add('[$a]aformat=channel_layouts=mono,showfreqs=s=512x128:rate=$fps:mode=bar:ascale=log:fscale=log:win_size=2048:cmode=combined:colors=${_hex(v.color)},format=gbrp[$sp]');
      final rm = b.label('rm');
      b.chains.add('[$xi:v]format=gray16[${sp}x];[$yi:v]format=gray16[${sp}y];[$sp][${sp}x][${sp}y]remap=fill=black:format=color,gblur=sigma=0.6[$rm]');
      b.chains.add('[$rm]${keyed('null')}[$vis]');
      break;
    case 'wave':
    case 'wavebars':
      final mode = v.style == 'wave' ? 'cline' : 'p2p';
      b.chains.add('[$a]${keyed('aformat=channel_layouts=mono,showwaves=s=${rw}x$rh:rate=$fps:mode=$mode:colors=${_hex(v.color)}:split_channels=0:scale=sqrt:draw=full')}[$vis]');
      break;
    case 'oscilloscope':
      final s = math.min(rw, rh);
      final col = c1.replaceFirst('0x', '');
      int ch(int i) => int.parse(col.substring(i * 2, i * 2 + 2), radix: 16);
      b.chains.add('[$a]${keyed('avectorscope=s=${s}x$s:r=$fps:mode=lissajous:draw=line:scale=sqrt:zoom=1.4:rc=${ch(0)}:gc=${ch(1)}:bc=${ch(2)}:rf=12:gf=12:bf=12')}[$vis]');
      break;
    case 'spectrogram':
      b.chains.add('[$a]${keyed('showspectrum=s=${rw}x$rh:slide=scroll:mode=combined:color=intensity:scale=log:fscale=log:legend=0,fps=$fps')}[$vis]');
      break;
    case 'cqt':
      b.chains.add('[$a]${keyed('showcqt=s=${math.max(rw, 640)}x${math.max(rh, 160)}:fps=$fps:sono_h=0:bar_g=2:axis=0:bar_v=12,scale=$rw:$rh')}[$vis]');
      break;
    case 'volume':
      b.chains.add('[$a]${keyed('showvolume=r=$fps:w=${math.max(rw, 100)}:h=${math.max(10, rh ~/ 4)}:f=0.9:b=4:dm=1:o=h:t=0:v=0,scale=$rw:$rh')}[$vis]');
      break;
    default:
      b.chains.add('[$a]${keyed('showfreqs=s=${rw}x$rh:rate=$fps:mode=bar:colors=${_hex(v.color)}')}[$vis]');
  }
  final s = v.start, e = v.duration > 0 ? v.start + v.duration : x.duration;
  final out = b.label('vzo');
  final vs = b.label('vs');
  // Bass pulse: scale the visual with the real bass envelope
  var cur = vis;
  if (v.bassPulse && x.music != null && (v.style == 'circle' || v.style == 'oscilloscope')) {
    final sz = v.style == 'circle' ? math.min(rw, rh) ~/ 2 * 2 : math.min(rw, rh);
    final inst = b.label('vpulse');
    final cmd = x.sendcmdFile(inst, (val) {
      final k = (sz * (1 + 0.18 * val)).round() ~/ 2 * 2;
      return 'scale@$inst w $k, scale@$inst h $k';
    }, env: x.bassAt);
    b.chains.add('[$cur]sendcmd=f=$cmd,scale@$inst=w=$sz:h=$sz[$vs]');
    cur = vs;
  }
  final cx = px + rw / 2, cy = py + rh / 2;
  b.chains.add("[$base][$cur]overlay=x='${FfEscape.num(cx)}-w/2':y='${FfEscape.num(cy)}-h/2':eof_action=pass:enable='between(t,${fsec(s)},${fsec(e)})'[$out]");
  if (logoPath == null) return out;
  // Logo in the centre, pulsing with bass.
  final li = b.addInput(logoPath, pre: ['-loop', '1', '-framerate', fps]);
  final logoSz = (math.min(rw, rh) * v.logoSize).round() ~/ 2 * 2;
  final lg = b.label('logo'), out2 = b.label('vzl');
  if (x.music != null && v.bassPulse) {
    final inst = b.label('lpulse');
    final cmd = x.sendcmdFile(inst, (val) {
      final k = (logoSz * (1 + 0.15 * val)).round() ~/ 2 * 2;
      return 'scale@$inst w $k, scale@$inst h $k';
    }, env: x.bassAt);
    b.chains.add('[$li:v]format=rgba,sendcmd=f=$cmd,scale@$inst=w=$logoSz:h=$logoSz[$lg]');
  } else {
    b.chains.add('[$li:v]format=rgba,scale=w=$logoSz:h=$logoSz[$lg]');
  }
  b.chains.add("[$out][$lg]overlay=x='${FfEscape.num(cx)}-w/2':y='${FfEscape.num(cy)}-h/2':shortest=0:eof_action=pass:enable='between(t,${fsec(s)},${fsec(e)})'[$out2]");
  return out2;
}
