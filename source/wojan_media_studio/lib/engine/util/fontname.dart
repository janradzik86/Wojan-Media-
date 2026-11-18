import 'dart:convert';
import 'dart:typed_data';

/// Reads the font family name (nameID 1/16) from a TTF/OTF file.
String? fontFamilyName(Uint8List b) {
  final bd = ByteData.sublistView(b);
  if (b.length < 12) return null;
  final numTables = bd.getUint16(4);
  for (var i = 0; i < numTables; i++) {
    final rec = 12 + i * 16;
    if (rec + 16 > b.length) return null;
    final tag = ascii.decode(b.sublist(rec, rec + 4), allowInvalid: true);
    if (tag != 'name') continue;
    final off = bd.getUint32(rec + 8);
    final count = bd.getUint16(off + 2);
    final strOff = off + bd.getUint16(off + 4);
    String? best;
    for (var j = 0; j < count; j++) {
      final r = off + 6 + j * 12;
      final platform = bd.getUint16(r), nameId = bd.getUint16(r + 6), len = bd.getUint16(r + 8), o = bd.getUint16(r + 10);
      if (nameId != 1 && nameId != 16) continue;
      final raw = b.sublist(strOff + o, strOff + o + len);
      String s;
      if (platform == 3 || platform == 0) {
        final u = <int>[];
        for (var k = 0; k + 1 < raw.length; k += 2) {
          u.add((raw[k] << 8) | raw[k + 1]);
        }
        s = String.fromCharCodes(u);
      } else {
        s = latin1.decode(raw, allowInvalid: true);
      }
      if (nameId == 16) return s;
      best ??= s;
    }
    return best;
  }
  return null;
}
