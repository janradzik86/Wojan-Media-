import 'dart:io';

import 'package:crypto/crypto.dart';

/// Streaming SHA-256 of a file (constant memory, works for multi-GB media).
Future<String> sha256File(File f) async {
  final out = _DigestSink();
  final input = sha256.startChunkedConversion(out);
  await for (final chunk in f.openRead()) {
    input.add(chunk);
  }
  input.close();
  return out.value.toString();
}

String sha256String(String s) => sha256.convert(s.codeUnits).toString();

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
