/// Small helpers for tolerant JSON decoding of persisted models.
double jd(Object? v, [double def = 0]) =>
    v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? def : def);
int ji(Object? v, [int def = 0]) =>
    v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? def : def);
bool jb(Object? v, [bool def = false]) => v is bool ? v : def;
String js(Object? v, [String def = '']) => v is String ? v : (v?.toString() ?? def);
List<Map<String, dynamic>> jl(Object? v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];
Map<String, dynamic> jm(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Formats seconds as ffmpeg-friendly decimal (no exponent, max 6 decimals).
String fsec(double s) {
  if (s.isNaN || s.isInfinite) throw ArgumentError('Invalid time value: $s');
  var t = s.toStringAsFixed(6);
  t = t.replaceFirst(RegExp(r'0+$'), '');
  if (t.endsWith('.')) t = t.substring(0, t.length - 1);
  return t == '-0' ? '0' : t;
}

/// Human readable mm:ss.mmm
String fmtTime(double s) {
  if (s.isNaN || s < 0) s = 0;
  final m = s ~/ 60;
  final sec = s - m * 60;
  return '${m.toString().padLeft(2, '0')}:${sec.toStringAsFixed(2).padLeft(5, '0')}';
}

String fmtBytes(num b) {
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = b.toDouble();
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${u[i]}';
}

double clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);
