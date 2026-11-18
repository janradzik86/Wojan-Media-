import '../util/json_util.dart';

/// Escaping and validation helpers for FFmpeg filtergraph arguments.
///
/// All FFmpeg invocations in WoJan Media Studio are made with an argument
/// list (never a shell string), so shell injection is impossible. Filtergraph
/// strings however have their own syntax; any user-provided text or path that
/// ends up inside a filtergraph MUST pass through [escapeFilterValue].
class FfEscape {
  /// Escapes a value for use as a filter option value inside a filtergraph.
  /// Level 1 (option parser): backslash-escape `\`, `'` and `:`.
  /// Level 2 (graph parser): wrap in single quotes; quotes inside are
  /// emitted as `'\''`.
  static String escapeFilterValue(String v) {
    final level1 = v
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll(':', '\\:');
    return "'${level1.replaceAll("'", "'\\''")}'";
  }

  /// Escapes a filesystem path for filters taking file names
  /// (`subtitles`, `ass`, `movie`, `lut3d`, `afir` via amovie...).
  static String escapePath(String path) => escapeFilterValue(path.replaceAll('\\', '/'));

  /// Validates a number before inserting it into a filter.
  static String num(double v, {double? min, double? max}) {
    if (v.isNaN || v.isInfinite) throw ArgumentError('Nieprawidłowa wartość: $v');
    if (min != null && v < min) v = min;
    if (max != null && v > max) v = max;
    return fsec(v);
  }

  static final _colorRe = RegExp(r'^(#|0x)?[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$');
  static final _namedColor = RegExp(r'^[a-zA-Z]{3,20}$');

  /// Validates color (hex RRGGBB[AA] or simple named colour).
  static String color(String c) {
    if (_colorRe.hasMatch(c)) {
      final h = c.replaceFirst('#', '').replaceFirst('0x', '');
      return '0x$h';
    }
    if (_namedColor.hasMatch(c)) return c;
    throw ArgumentError('Nieprawidłowy kolor: $c');
  }

  /// Identifier (filter label, codec name, preset) whitelist.
  static final _ident = RegExp(r'^[A-Za-z0-9_\-\.]{1,64}$');
  static String ident(String s) {
    if (!_ident.hasMatch(s)) throw ArgumentError('Nieprawidłowy identyfikator: $s');
    return s;
  }
}
