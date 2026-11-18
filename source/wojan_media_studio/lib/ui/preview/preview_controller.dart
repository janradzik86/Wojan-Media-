import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide AudioTrack;
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/services.dart';
import '../../engine/audio/audio_compiler.dart';
import '../../engine/dsp/analysis.dart';
import '../../engine/dsp/fft.dart';
import '../../engine/dsp/pcm.dart';
import '../../engine/export/audio_formats.dart';
import '../../engine/project/asset.dart';
import '../../engine/util/hash.dart';
import '../../engine/video/model.dart';

class VideoSlot {
  final Player player;
  final VideoController controller;
  final String clipId;
  bool opened = false;
  VideoSlot(this.clipId, this.player, this.controller);
}

/// Real-time preview clock and media sources (FotoPlay-style live preview).
/// The timeline is drawn by Flutter every frame; the audio mix is the same
/// AudioProject the exporter uses (rendered once to a cached file).
class PreviewController extends ChangeNotifier {
  VideoProject project;
  final AssetResolver assets;
  AudioAnalysis? music;
  double musicOffset;
  double _pos = 0;
  bool _playing = false;
  final Player audio = Player();
  bool audioReady = false;
  String? audioError;
  String? _audioKey;
  Duration _lastAudioPos = Duration.zero;
  DateTime _lastAudioStamp = DateTime.now();
  DateTime _lastTick = DateTime.now();
  StreamSubscription<Duration>? _posSub;
  PcmData? pcm; // mono 22.05 kHz of the main music for live visualisers
  final _fft = FFT(1024);
  final Map<String, VideoSlot> _videos = {};
  List<double> _starts = [];

  PreviewController({required this.project, required this.assets, this.music, this.musicOffset = 0}) {
    _starts = project.clipStarts();
    _posSub = audio.stream.position.listen((d) {
      _lastAudioPos = d;
      _lastAudioStamp = DateTime.now();
    });
    audio.stream.completed.listen((done) {
      if (done && _playing) {
        _playing = false;
        notifyListeners();
      }
    });
  }

  double get position => _pos;
  bool get playing => _playing;
  double get duration => project.duration;
  List<double> get starts => _starts;

  /// Call after any edit of the project.
  void projectChanged(VideoProject p) {
    project = p;
    _starts = p.clipStarts();
    if (_pos > duration) _pos = duration;
    prepareAudio();
    notifyListeners();
  }

  Future<void> prepareAudio() async {
    final ap = project.audio;
    final hasAudio = ap.tracks.any((t) => !t.muted && t.clips.isNotEmpty);
    if (!hasAudio) {
      audioReady = false;
      return;
    }
    final paths = [for (final t in ap.tracks) for (final c in t.clips) assets.pathOf(c.assetId)];
    final key = sha256String(jsonEncode({'a': ap.toJson(), 'p': paths}));
    if (key == _audioKey && audioReady) return;
    _audioKey = key;
    audioReady = false;
    notifyListeners();
    try {
      final dir = Directory('${Services.i.store.cacheDir.path}/preview_audio');
      await dir.create(recursive: true);
      final f = File('${dir.path}/$key.m4a');
      if (!f.existsSync()) {
        final tmp = '${f.path}.tmp.m4a';
        await AudioRenderer(Services.i.runner, Directory('${Services.i.store.cacheDir.path}/audio')).render(ap, assets, tmp, AudioExportSettings(format: AudioFormat.m4a, bitrateKbps: 160, sampleRate: 44100));
        await File(tmp).rename(f.path);
      }
      if (key != _audioKey) return; // superseded by a newer edit
      await audio.open(Media(f.path), play: false);
      await audio.seek(Duration(milliseconds: (_pos * 1000).round()));
      if (_playing) await audio.play();
      audioReady = true;
      audioError = null;
      // live spectrum source: decode main music once
      if (pcm == null && project.musicAssetId != null) {
        final p = await PcmDecoder(Services.i.runner, Directory('${Services.i.store.cacheDir.path}/pcm')).decode(f.path, sampleRate: 22050);
        pcm = p;
      }
    } catch (e) {
      audioError = '$e';
    }
    notifyListeners();
  }

  /// Advances the clock; called by the preview's ticker every frame.
  void tick() {
    final now = DateTime.now();
    if (_playing) {
      if (audioReady) {
        final est = _lastAudioPos + now.difference(_lastAudioStamp);
        _pos = est.inMicroseconds / 1e6;
      } else {
        _pos += now.difference(_lastTick).inMicroseconds / 1e6;
      }
      if (_pos >= duration) {
        _pos = duration;
        pause();
      }
      _syncVideos();
      notifyListeners();
    }
    _lastTick = now;
  }

  Future<void> play() async {
    if (_pos >= duration - 0.05) seek(0);
    _playing = true;
    _lastTick = DateTime.now();
    if (audioReady) {
      await audio.seek(Duration(milliseconds: (_pos * 1000).round()));
      _lastAudioPos = Duration(milliseconds: (_pos * 1000).round());
      _lastAudioStamp = DateTime.now();
      await audio.play();
    }
    _syncVideos(force: true);
    notifyListeners();
  }

  Future<void> pause() async {
    _playing = false;
    await audio.pause();
    for (final v in _videos.values) {
      await v.player.pause();
    }
    notifyListeners();
  }

  Future<void> toggle() => _playing ? pause() : play();

  Future<void> seek(double t) async {
    _pos = t.clamp(0, duration).toDouble();
    _lastAudioPos = Duration(milliseconds: (_pos * 1000).round());
    _lastAudioStamp = DateTime.now();
    if (audioReady) await audio.seek(_lastAudioPos);
    _syncVideos(force: true);
    notifyListeners();
  }

  /// Keeps one muted/unmuted player per visible video clip in sync.
  void _syncVideos({bool force = false}) {
    final want = <String>{};
    for (var i = 0; i < project.clips.length; i++) {
      final c = project.clips[i];
      if (c.kind != ClipKind.video || c.assetId == null) continue;
      final s = _starts[i], e = s + c.duration;
      if (_pos >= s - 0.6 && _pos < e) want.add(c.id);
    }
    for (final id in _videos.keys.toList()) {
      if (!want.contains(id)) {
        _videos.remove(id)!.player.dispose();
      }
    }
    for (var i = 0; i < project.clips.length; i++) {
      final c = project.clips[i];
      if (!want.contains(c.id)) continue;
      var slot = _videos[c.id];
      final local = (_pos - _starts[i]).clamp(0.0, c.duration);
      final srcT = c.srcIn + (local * c.speed) % math.max(0.05, c.srcOut - c.srcIn);
      if (slot == null) {
        final pl = Player();
        slot = VideoSlot(c.id, pl, VideoController(pl));
        _videos[c.id] = slot;
        final vol = project.clipAudio && !c.mute ? (100 * math.pow(10, (c.volumeDb + project.clipAudioDb) / 20)).clamp(0, 100).toDouble() : 0.0;
        pl.setVolume(vol);
        pl.setPlaylistMode(c.loopVideo ? PlaylistMode.single : PlaylistMode.none);
        pl.open(Media(assets.pathOf(c.assetId!), start: Duration(milliseconds: (srcT * 1000).round())), play: _playing && _pos >= _starts[i]).then((_) {
          slot!.opened = true;
          pl.setRate(c.speed);
        });
        continue;
      }
      if (!slot.opened) continue;
      final active = _pos >= _starts[i];
      if (force) slot.player.seek(Duration(milliseconds: (srcT * 1000).round()));
      if (_playing && active && !slot.player.state.playing) {
        slot.player.seek(Duration(milliseconds: (srcT * 1000).round()));
        slot.player.play();
      } else if ((!_playing || !active) && slot.player.state.playing) {
        slot.player.pause();
      }
    }
  }

  VideoSlot? videoFor(String clipId) => _videos[clipId];

  /// Real spectrum (dB, [bands] log bands) of the music at timeline [t].
  Float32List spectrum(double t, {int bands = 48}) {
    final p = pcm;
    final out = Float32List(bands);
    if (p == null) return out..fillRange(0, bands, -90);
    final off = ((t) * p.sampleRate).round() - 512;
    final m = _fft.magnitudes(p.samples, off);
    final binHz = p.sampleRate / 1024;
    for (var b = 0; b < bands; b++) {
      final lo = (40 * math.pow((p.sampleRate / 2) / 40, b / bands) / binHz).floor().clamp(1, 511);
      final hi = math.max(lo + 1, (40 * math.pow((p.sampleRate / 2) / 40, (b + 1) / bands) / binHz).floor().clamp(1, 512));
      var acc = 0.0;
      for (var k = lo; k < hi; k++) {
        acc = math.max(acc, m[k]);
      }
      out[b] = acc <= 1e-9 ? -90 : 20 * math.log(acc) / math.ln10;
    }
    return out;
  }

  /// Waveform window (mono samples) around [t].
  Float32List wave(double t, {int n = 1024}) {
    final p = pcm;
    if (p == null) return Float32List(n);
    final start = (t * p.sampleRate).round() - n ~/ 2;
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      final k = start + i;
      out[i] = k >= 0 && k < p.samples.length ? p.samples[k] : 0;
    }
    return out;
  }

  double bassAt(double t) => music == null ? 0 : music!.valueAt(music!.bass, t - musicOffset);
  double energyAt(double t) => music == null ? 0 : music!.valueAt(music!.rms, t - musicOffset);

  @override
  void dispose() {
    _posSub?.cancel();
    audio.dispose();
    for (final v in _videos.values) {
      v.player.dispose();
    }
    super.dispose();
  }
}
