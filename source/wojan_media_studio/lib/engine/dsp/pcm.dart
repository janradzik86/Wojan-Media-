import 'dart:io';
import 'dart:typed_data';

import '../ffmpeg/runner.dart';

/// Decoded mono PCM signal used for analysis (waveform, BPM, spectrum).
class PcmData {
  final Float32List samples;
  final int sampleRate;
  PcmData(this.samples, this.sampleRate);
  double get duration => samples.length / sampleRate;
}

/// Decodes any FFmpeg-readable media to mono float PCM (via a temp file so it
/// works identically with FFmpegKit on Android/Windows).
class PcmDecoder {
  final MediaRunner runner;
  final Directory tempDir;
  PcmDecoder(this.runner, this.tempDir);

  Future<PcmData> decode(String path,
      {int sampleRate = 22050, double? start, double? duration, CancelToken? cancel, bool stereo = false}) async {
    await tempDir.create(recursive: true);
    final out = File('${tempDir.path}/pcm_${DateTime.now().microsecondsSinceEpoch}.f32');
    try {
      await runner.run([
        if (start != null) ...['-ss', start.toStringAsFixed(3)],
        if (duration != null) ...['-t', duration.toStringAsFixed(3)],
        '-i', path,
        '-vn', '-sn', '-dn',
        '-ac', stereo ? '2' : '1',
        '-ar', '$sampleRate',
        '-f', 'f32le', '-acodec', 'pcm_f32le',
        out.path,
      ], cancel: cancel, what: 'Nie udało się zdekodować audio');
      final bytes = await out.readAsBytes();
      final data = bytes.buffer.asFloat32List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 4);
      return PcmData(Float32List.fromList(data), sampleRate);
    } finally {
      if (await out.exists()) await out.delete();
    }
  }
}

/// Writes a 16-bit PCM WAV (used for generated impulse responses etc.)
Future<void> writeWav16(File f, List<Float32List> channels, int sampleRate) async {
  final n = channels.first.length;
  final ch = channels.length;
  final dataLen = n * ch * 2;
  final b = BytesBuilder();
  void u32(int v) => b.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void u16(int v) => b.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));
  b.add('RIFF'.codeUnits);
  u32(36 + dataLen);
  b.add('WAVEfmt '.codeUnits);
  u32(16);
  u16(1);
  u16(ch);
  u32(sampleRate);
  u32(sampleRate * ch * 2);
  u16(ch * 2);
  u16(16);
  b.add('data'.codeUnits);
  u32(dataLen);
  final pcm = ByteData(dataLen);
  var o = 0;
  for (var i = 0; i < n; i++) {
    for (var c = 0; c < ch; c++) {
      var v = channels[c][i];
      if (v > 1) v = 1;
      if (v < -1) v = -1;
      pcm.setInt16(o, (v * 32767).round(), Endian.little);
      o += 2;
    }
  }
  b.add(pcm.buffer.asUint8List());
  await f.writeAsBytes(b.toBytes(), flush: true);
}
