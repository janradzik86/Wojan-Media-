import 'dart:math' as math;

import 'json_util.dart';

enum Easing { linear, easeIn, easeOut, easeInOut, hold }

Easing easingFrom(String? s) =>
    Easing.values.firstWhere((e) => e.name == s, orElse: () => Easing.linear);

/// A keyframe: time (seconds, relative to the owning item) and value.
class Keyframe {
  final double t;
  final double v;
  final Easing ease;
  const Keyframe(this.t, this.v, [this.ease = Easing.linear]);
  Map<String, dynamic> toJson() => {'t': t, 'v': v, 'e': ease.name};
  factory Keyframe.fromJson(Map<String, dynamic> j) =>
      Keyframe(jd(j['t']), jd(j['v']), easingFrom(j['e'] as String?));
}

String _easeExpr(String p, Easing e) {
  switch (e) {
    case Easing.linear:
      return p;
    case Easing.easeIn:
      return '($p)*($p)';
    case Easing.easeOut:
      return '(1-(1-($p))*(1-($p)))';
    case Easing.easeInOut:
      return '(0.5-0.5*cos(PI*($p)))';
    case Easing.hold:
      return '0';
  }
}

/// Builds an FFmpeg expression evaluating the piecewise keyframe curve at
/// variable [v] (e.g. `t`). Constant outside the keyframe range.
/// [offset] is subtracted from the variable first (item start time).
String keyframeExpr(List<Keyframe> kfs, {String v = 't', double offset = 0, double scale = 1}) {
  if (kfs.isEmpty) return '0';
  final k = [...kfs]..sort((a, b) => a.t.compareTo(b.t));
  final x = offset == 0 ? v : '($v-${fsec(offset)})';
  String val(double d) => fsec(d * scale);
  if (k.length == 1) return val(k.first.v);
  var expr = val(k.last.v);
  for (var i = k.length - 2; i >= 0; i--) {
    final a = k[i], b = k[i + 1];
    final dt = b.t - a.t;
    String seg;
    if (dt <= 1e-6 || a.ease == Easing.hold) {
      seg = val(a.v);
    } else {
      final p = '(($x-${fsec(a.t)})/${fsec(dt)})';
      seg = '(${val(a.v)}+(${val(b.v - a.v)})*${_easeExpr(p, a.ease)})';
    }
    expr = 'if(lt($x,${fsec(b.t)}),$seg,$expr)';
  }
  return 'if(lt($x,${fsec(k.first.t)}),${val(k.first.v)},$expr)';
}

/// Dart-side evaluation of the same curve (UI previews & tests).
double evalKeyframes(List<Keyframe> kfs, double t) {
  if (kfs.isEmpty) return 0;
  final k = [...kfs]..sort((a, b) => a.t.compareTo(b.t));
  if (t <= k.first.t) return k.first.v;
  for (var i = 0; i < k.length - 1; i++) {
    final a = k[i], b = k[i + 1];
    if (t < b.t) {
      if (a.ease == Easing.hold) return a.v;
      final p = (t - a.t) / (b.t - a.t);
      double e;
      switch (a.ease) {
        case Easing.easeIn:
          e = p * p;
          break;
        case Easing.easeOut:
          e = 1 - (1 - p) * (1 - p);
          break;
        case Easing.easeInOut:
          e = 0.5 - 0.5 * math.cos(math.pi * p);
          break;
        default:
          e = p;
      }
      return a.v + (b.v - a.v) * e;
    }
  }
  return k.last.v;
}

