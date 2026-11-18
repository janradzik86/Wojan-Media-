import 'package:uuid/uuid.dart';

import '../util/expr.dart';
import '../util/json_util.dart';
import 'effects.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// A non-destructive region of a source file placed on a track.
class AudioClip {
  final String id;
  String assetId;
  double srcIn; // seconds in source
  double srcOut;
  double position; // seconds on timeline
  double gainDb;
  double fadeIn;
  double fadeOut;
  bool muted;
  bool reverse;
  double tempo; // time-stretch factor, pitch preserved
  double pitch; // semitones, tempo preserved
  int loops; // number of repetitions (1 = no loop)
  List<AudioEffect> effects;
  List<Keyframe> volumeAuto; // gain multiplier keyframes (relative to clip start on timeline)
  String label;

  AudioClip({
    String? id,
    required this.assetId,
    required this.srcIn,
    required this.srcOut,
    this.position = 0,
    this.gainDb = 0,
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.muted = false,
    this.reverse = false,
    this.tempo = 1,
    this.pitch = 0,
    this.loops = 1,
    List<AudioEffect>? effects,
    List<Keyframe>? volumeAuto,
    this.label = '',
  })  : id = id ?? newId(),
        effects = effects ?? [],
        volumeAuto = volumeAuto ?? [];

  double get srcLength => srcOut - srcIn;
  double get singleLength => srcLength / tempo;
  double get length => singleLength * loops;
  double get end => position + length;

  /// Converts a timeline time into source time (first loop).
  double toSource(double t) => srcIn + ((t - position) % singleLength) * tempo;

  AudioClip copy({bool newIdentity = true}) => AudioClip.fromJson(toJson(), forceNewId: newIdentity);

  Map<String, dynamic> toJson() => {
        'id': id,
        'assetId': assetId,
        'srcIn': srcIn,
        'srcOut': srcOut,
        'position': position,
        'gainDb': gainDb,
        'fadeIn': fadeIn,
        'fadeOut': fadeOut,
        'muted': muted,
        'reverse': reverse,
        'tempo': tempo,
        'pitch': pitch,
        'loops': loops,
        'effects': effects.map((e) => e.toJson()).toList(),
        'volumeAuto': volumeAuto.map((e) => e.toJson()).toList(),
        'label': label,
      };

  factory AudioClip.fromJson(Map<String, dynamic> j, {bool forceNewId = false}) => AudioClip(
        id: forceNewId ? null : js(j['id']),
        assetId: js(j['assetId']),
        srcIn: jd(j['srcIn']),
        srcOut: jd(j['srcOut']),
        position: jd(j['position']),
        gainDb: jd(j['gainDb']),
        fadeIn: jd(j['fadeIn']),
        fadeOut: jd(j['fadeOut']),
        muted: jb(j['muted']),
        reverse: jb(j['reverse']),
        tempo: jd(j['tempo'], 1),
        pitch: jd(j['pitch']),
        loops: ji(j['loops'], 1).clamp(1, 1000),
        effects: jl(j['effects']).map(AudioEffect.fromJson).toList(),
        volumeAuto: jl(j['volumeAuto']).map(Keyframe.fromJson).toList(),
        label: js(j['label']),
      );
}

class AudioTrack {
  final String id;
  String name;
  double gainDb;
  double pan; // -1..1
  bool muted;
  bool solo;
  bool locked;
  List<AudioClip> clips;
  List<AudioEffect> effects;

  AudioTrack({String? id, required this.name, this.gainDb = 0, this.pan = 0, this.muted = false, this.solo = false, this.locked = false, List<AudioClip>? clips, List<AudioEffect>? effects})
      : id = id ?? newId(),
        clips = clips ?? [],
        effects = effects ?? [];

  double get end => clips.fold(0.0, (m, c) => c.end > m ? c.end : m);

  void sortClips() => clips.sort((a, b) => a.position.compareTo(b.position));

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'gainDb': gainDb,
        'pan': pan,
        'muted': muted,
        'solo': solo,
        'locked': locked,
        'clips': clips.map((c) => c.toJson()).toList(),
        'effects': effects.map((e) => e.toJson()).toList(),
      };

  factory AudioTrack.fromJson(Map<String, dynamic> j) => AudioTrack(
        id: js(j['id']),
        name: js(j['name']),
        gainDb: jd(j['gainDb']),
        pan: jd(j['pan']),
        muted: jb(j['muted']),
        solo: jb(j['solo']),
        locked: jb(j['locked']),
        clips: jl(j['clips']).map(AudioClip.fromJson).toList(),
        effects: jl(j['effects']).map(AudioEffect.fromJson).toList(),
      );
}

class Marker {
  double t;
  String label;
  Marker(this.t, this.label);
  Map<String, dynamic> toJson() => {'t': t, 'label': label};
  factory Marker.fromJson(Map<String, dynamic> j) => Marker(jd(j['t']), js(j['label']));
}

/// Multitrack, non-destructive audio arrangement.
class AudioProject {
  int sampleRate;
  int channels;
  List<AudioTrack> tracks;
  List<AudioEffect> masterEffects;
  List<Marker> markers;
  double masterGainDb;

  AudioProject({this.sampleRate = 44100, this.channels = 2, List<AudioTrack>? tracks, List<AudioEffect>? masterEffects, List<Marker>? markers, this.masterGainDb = 0})
      : tracks = tracks ?? [AudioTrack(name: 'Ścieżka 1')],
        masterEffects = masterEffects ?? [],
        markers = markers ?? [];

  double get duration => tracks.fold(0.0, (m, t) => t.end > m ? t.end : m);

  Map<String, dynamic> toJson() => {
        'sampleRate': sampleRate,
        'channels': channels,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'masterEffects': masterEffects.map((e) => e.toJson()).toList(),
        'markers': markers.map((m) => m.toJson()).toList(),
        'masterGainDb': masterGainDb,
      };

  factory AudioProject.fromJson(Map<String, dynamic> j) => AudioProject(
        sampleRate: ji(j['sampleRate'], 44100),
        channels: ji(j['channels'], 2),
        tracks: jl(j['tracks']).map(AudioTrack.fromJson).toList(),
        masterEffects: jl(j['masterEffects']).map(AudioEffect.fromJson).toList(),
        markers: jl(j['markers']).map(Marker.fromJson).toList(),
        masterGainDb: jd(j['masterGainDb']),
      );

  AudioTrack track(String id) => tracks.firstWhere((t) => t.id == id);

  // ---------------------------------------------------------------- editing

  /// Appends a whole source to a track (after the last clip).
  AudioClip appendAsset(String trackId, String assetId, double sourceDuration) {
    final t = track(trackId);
    final c = AudioClip(assetId: assetId, srcIn: 0, srcOut: sourceDuration, position: t.end);
    t.clips.add(c);
    return c;
  }

  /// Splits the clip covering time [t] on a track. Returns the right part.
  AudioClip? splitAt(String trackId, double t) {
    final tr = track(trackId);
    for (final c in List.of(tr.clips)) {
      if (t > c.position + 1e-6 && t < c.end - 1e-6) {
        if (c.loops > 1) {
          _unrollLoops(tr, c);
          return splitAt(trackId, t);
        }
        return _splitClip(tr, c, t);
      }
    }
    return null;
  }

  AudioClip? _splitClip(AudioTrack tr, AudioClip c, double t) {
    if (!(t > c.position + 1e-6 && t < c.end - 1e-6)) return null;
    final rel = (t - c.position) * c.tempo;
    final right = c.copy();
    if (c.reverse) {
      // In reversed clips, timeline-left corresponds to source end.
      right.srcOut = c.srcOut - rel;
      c.srcIn = c.srcOut - rel;
    } else {
      right.srcIn = c.srcIn + rel;
      c.srcOut = c.srcIn + rel;
    }
    right.position = t;
    right.fadeIn = 0;
    c.fadeOut = 0;
    right.volumeAuto = [for (final k in c.volumeAuto) Keyframe(k.t - (t - c.position), k.v, k.ease)];
    tr.clips.insert(tr.clips.indexOf(c) + 1, right);
    return right;
  }

  void _unrollLoops(AudioTrack tr, AudioClip c) {
    final n = c.loops;
    c.loops = 1;
    var idx = tr.clips.indexOf(c);
    for (var i = 1; i < n; i++) {
      final cp = c.copy()..position = c.position + c.singleLength * i;
      tr.clips.insert(++idx, cp);
    }
  }

  /// Removes [t0,t1) from a track; later clips shift left when [ripple].
  void deleteRange(String trackId, double t0, double t1, {bool ripple = true}) {
    if (t1 <= t0) return;
    final tr = track(trackId);
    splitAt(trackId, t0);
    splitAt(trackId, t1);
    tr.clips.removeWhere((c) => c.position >= t0 - 1e-6 && c.end <= t1 + 1e-6);
    if (ripple) {
      for (final c in tr.clips) {
        if (c.position >= t1 - 1e-6) c.position -= (t1 - t0);
      }
    }
    tr.sortClips();
  }

  /// Keeps only [t0,t1) of the track (trim start & end).
  void trimTo(String trackId, double t0, double t1) {
    final tr = track(trackId);
    final end = tr.end;
    if (t1 < end) deleteRange(trackId, t1, end, ripple: false);
    if (t0 > 0) deleteRange(trackId, 0, t0, ripple: true);
  }

  /// Copies [t0,t1) of a track into independent clip copies (clipboard).
  List<AudioClip> copyRange(String trackId, double t0, double t1) {
    final snapshot = AudioProject.fromJson(toJson());
    final tr = snapshot.track(trackId);
    snapshot.splitAt(trackId, t0);
    snapshot.splitAt(trackId, t1);
    return [
      for (final c in tr.clips)
        if (c.position >= t0 - 1e-6 && c.end <= t1 + 1e-6) c.copy()..position = c.position - t0
    ];
  }

  /// Inserts clipboard clips at [t] shifting existing material (ripple).
  void paste(String trackId, double t, List<AudioClip> clipboard, {bool ripple = true}) {
    if (clipboard.isEmpty) return;
    final len = clipboard.fold(0.0, (m, c) => c.end > m ? c.end : m);
    final tr = track(trackId);
    if (ripple) {
      splitAt(trackId, t);
      for (final c in tr.clips) {
        if (c.position >= t - 1e-6) c.position += len;
      }
    }
    for (final c in clipboard) {
      tr.clips.add(c.copy()..position = c.position + t);
    }
    tr.sortClips();
  }

  void insertSilence(String trackId, double t, double dur) {
    final tr = track(trackId);
    splitAt(trackId, t);
    for (final c in tr.clips) {
      if (c.position >= t - 1e-6) c.position += dur;
    }
  }

  /// Silences [t0,t1) without changing timing.
  void muteRange(String trackId, double t0, double t1) {
    final tr = track(trackId);
    splitAt(trackId, t0);
    splitAt(trackId, t1);
    for (final c in tr.clips) {
      if (c.position >= t0 - 1e-6 && c.end <= t1 + 1e-6) c.muted = true;
    }
  }

  /// Duplicates [t0,t1) right after itself [times] times.
  void duplicateRange(String trackId, double t0, double t1, {int times = 1}) {
    final cb = copyRange(trackId, t0, t1);
    for (var i = 0; i < times; i++) {
      paste(trackId, t1 + i * (t1 - t0), cb);
    }
  }

  /// Moves clip to a new index in sequential arrangement and re-packs
  /// all clips gap-less (reordering fragments).
  void reorder(String trackId, int from, int to) {
    final tr = track(trackId);
    tr.sortClips();
    final c = tr.clips.removeAt(from);
    tr.clips.insert(to.clamp(0, tr.clips.length), c);
    var pos = tr.clips.isEmpty ? 0.0 : tr.clips.map((e) => e.position).reduce((a, b) => a < b ? a : b);
    pos = 0;
    for (final cl in tr.clips) {
      cl.position = pos;
      pos = cl.end;
    }
  }

  /// Packs clips sequentially (merge / join mode) with optional crossfade.
  void packSequential(String trackId, {double crossfade = 0}) {
    final tr = track(trackId);
    tr.sortClips();
    var pos = 0.0;
    for (var i = 0; i < tr.clips.length; i++) {
      final c = tr.clips[i];
      c.position = pos;
      if (crossfade > 0) {
        if (i > 0) c.fadeIn = crossfade;
        if (i < tr.clips.length - 1) c.fadeOut = crossfade;
      }
      pos = c.end - (i < tr.clips.length - 1 ? crossfade : 0);
    }
  }

  AudioTrack addTrack([String? name]) {
    final t = AudioTrack(name: name ?? 'Ścieżka ${tracks.length + 1}');
    tracks.add(t);
    return t;
  }
}
