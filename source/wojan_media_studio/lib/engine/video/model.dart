import '../audio/audio_project.dart';
import '../lyrics/lyrics.dart';
import '../util/expr.dart';
import '../util/json_util.dart';
import 'color.dart';

enum ClipKind { image, video, color }
enum FitMode { cover, contain, blurBackground, stretch }

/// Motion presets for photos/videos ("animowanie zdjęć").
enum MotionPreset {
  none,
  kenBurnsIn,
  kenBurnsOut,
  panLeft,
  panRight,
  panUp,
  panDown,
  zoomInRotate,
  zoomOutRotate,
  parallax,
  shake,
  beatPulse,
  diagonal,
}

const motionNames = <MotionPreset, String>{
  MotionPreset.none: 'Brak',
  MotionPreset.kenBurnsIn: 'Ken Burns – przybliżenie',
  MotionPreset.kenBurnsOut: 'Ken Burns – oddalenie',
  MotionPreset.panLeft: 'Panorama w lewo',
  MotionPreset.panRight: 'Panorama w prawo',
  MotionPreset.panUp: 'Panorama w górę',
  MotionPreset.panDown: 'Panorama w dół',
  MotionPreset.zoomInRotate: 'Zoom z obrotem',
  MotionPreset.zoomOutRotate: 'Oddalenie z obrotem',
  MotionPreset.parallax: 'Paralaksa',
  MotionPreset.shake: 'Drgania kamery',
  MotionPreset.beatPulse: 'Pulsowanie do rytmu',
  MotionPreset.diagonal: 'Ruch po przekątnej',
};

/// Camera motion: either a preset or explicit keyframes. Values:
/// zoom ≥ 1, panX/panY 0..1 (focus point), rotation degrees.
class Motion {
  MotionPreset preset;
  double intensity; // 0..1 scales preset motion
  List<Keyframe> zoom;
  List<Keyframe> panX;
  List<Keyframe> panY;
  List<Keyframe> rotation;
  Motion({this.preset = MotionPreset.none, this.intensity = 0.5, List<Keyframe>? zoom, List<Keyframe>? panX, List<Keyframe>? panY, List<Keyframe>? rotation})
      : zoom = zoom ?? [],
        panX = panX ?? [],
        panY = panY ?? [],
        rotation = rotation ?? [];

  bool get hasKeyframes => zoom.isNotEmpty || panX.isNotEmpty || panY.isNotEmpty || rotation.isNotEmpty;
  bool get isStatic => preset == MotionPreset.none && !hasKeyframes;

  Map<String, dynamic> toJson() => {
        'preset': preset.name,
        'intensity': intensity,
        'zoom': zoom.map((e) => e.toJson()).toList(),
        'panX': panX.map((e) => e.toJson()).toList(),
        'panY': panY.map((e) => e.toJson()).toList(),
        'rotation': rotation.map((e) => e.toJson()).toList(),
      };
  factory Motion.fromJson(Map<String, dynamic> j) => Motion(
        preset: MotionPreset.values.firstWhere((e) => e.name == j['preset'], orElse: () => MotionPreset.none),
        intensity: jd(j['intensity'], 0.5),
        zoom: jl(j['zoom']).map(Keyframe.fromJson).toList(),
        panX: jl(j['panX']).map(Keyframe.fromJson).toList(),
        panY: jl(j['panY']).map(Keyframe.fromJson).toList(),
        rotation: jl(j['rotation']).map(Keyframe.fromJson).toList(),
      );
}

/// Transition types (xfade based; 'cut' = hard cut).
const transitionNames = <String, String>{
  'cut': 'Cięcie',
  'fade': 'Przenikanie (Fade)',
  'dissolve': 'Rozpuszczanie (Dissolve)',
  'fadeblack': 'Przez czerń',
  'fadewhite': 'Błysk (Flash)',
  'slideleft': 'Przesunięcie w lewo',
  'slideright': 'Przesunięcie w prawo',
  'slideup': 'Przesunięcie w górę',
  'slidedown': 'Przesunięcie w dół',
  'wipeleft': 'Wymazanie w lewo',
  'wiperight': 'Wymazanie w prawo',
  'wipeup': 'Wymazanie w górę',
  'wipedown': 'Wymazanie w dół',
  'zoomin': 'Zoom',
  'circleopen': 'Otwarcie koła',
  'circleclose': 'Zamknięcie koła',
  'radial': 'Radialne',
  'hblur': 'Rozmycie',
  'pixelize': 'Pikselizacja',
  'distance': 'Odległość',
  'smoothleft': 'Płynne w lewo',
  'smoothright': 'Płynne w prawo',
  'squeezeh': 'Ściśnięcie',
  'diagtl': 'Przekątna',
  'hlslice': 'Plastry',
  'rectcrop': 'Prostokąt',
  'coverleft': 'Zasłonięcie',
  'revealright': 'Odsłonięcie',
  'spin': 'Obrót (Spin)',
  'glitch': 'Glitch',
  'cube': 'Przestrzenne (kostka)',
  'filmburn': 'Filmowe (wypalenie)',
};

class Transition {
  String type;
  double duration;
  Transition({this.type = 'cut', this.duration = 0.6});
  bool get isCut => type == 'cut' || duration <= 0.01;
  Map<String, dynamic> toJson() => {'type': type, 'duration': duration};
  factory Transition.fromJson(Map<String, dynamic> j) => Transition(type: js(j['type'], 'cut'), duration: jd(j['duration'], 0.6));
}

/// Entrance/exit animations of a clip or overlay.
const inOutAnimNames = <String, String>{
  'none': 'Brak',
  'fade': 'Pojawienie',
  'zoom': 'Powiększenie',
  'slideLeft': 'Wsunięcie z prawej',
  'slideRight': 'Wsunięcie z lewej',
  'slideUp': 'Wsunięcie z dołu',
  'slideDown': 'Wsunięcie z góry',
  'spin': 'Obrót',
  'pop': 'Wyskok',
};

/// An item on the main visual sequence.
class VisualClip {
  final String id;
  ClipKind kind;
  String? assetId;
  String color; // for ClipKind.color
  double srcIn; // video only
  double srcOut;
  double imageDuration; // image/color only
  double speed;
  bool reverse;
  double freezeAt; // freeze frame at src time (−1 = none)
  double freezeDuration;
  FitMode fit;
  Motion motion;
  ColorGrade grade;
  Transition transition; // to next clip
  int rotate; // 0/90/180/270
  bool flipH, flipV;
  // crop rectangle in normalised coordinates
  double cropX, cropY, cropW, cropH;
  double volumeDb;
  bool mute;
  String animIn, animOut;
  double animInDur, animOutDur;
  List<String> vfx; // per-clip looks (vfx ids)
  bool loopVideo; // loop a short video to fill imageDuration

  VisualClip({
    String? id,
    required this.kind,
    this.assetId,
    this.color = '#000000',
    this.srcIn = 0,
    this.srcOut = 0,
    this.imageDuration = 3,
    this.speed = 1,
    this.reverse = false,
    this.freezeAt = -1,
    this.freezeDuration = 0,
    this.fit = FitMode.cover,
    Motion? motion,
    ColorGrade? grade,
    Transition? transition,
    this.rotate = 0,
    this.flipH = false,
    this.flipV = false,
    this.cropX = 0,
    this.cropY = 0,
    this.cropW = 1,
    this.cropH = 1,
    this.volumeDb = 0,
    this.mute = false,
    this.animIn = 'none',
    this.animOut = 'none',
    this.animInDur = 0.5,
    this.animOutDur = 0.5,
    List<String>? vfx,
    this.loopVideo = false,
  })  : id = id ?? newId(),
        motion = motion ?? Motion(),
        grade = grade ?? ColorGrade(),
        transition = transition ?? Transition(),
        vfx = vfx ?? [];

  bool get isVideo => kind == ClipKind.video;

  /// Duration on the timeline (before transition overlaps).
  double get duration {
    if (kind != ClipKind.video) return imageDuration;
    final base = (srcOut - srcIn) / speed;
    final fr = freezeAt >= 0 ? freezeDuration : 0;
    return loopVideo && imageDuration > base ? imageDuration : base + fr;
  }

  bool get hasCrop => cropX > 0.0001 || cropY > 0.0001 || cropW < 0.9999 || cropH < 0.9999;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'assetId': assetId,
        'color': color,
        'srcIn': srcIn,
        'srcOut': srcOut,
        'imageDuration': imageDuration,
        'speed': speed,
        'reverse': reverse,
        'freezeAt': freezeAt,
        'freezeDuration': freezeDuration,
        'fit': fit.name,
        'motion': motion.toJson(),
        'grade': grade.toJson(),
        'transition': transition.toJson(),
        'rotate': rotate,
        'flipH': flipH,
        'flipV': flipV,
        'crop': [cropX, cropY, cropW, cropH],
        'volumeDb': volumeDb,
        'mute': mute,
        'animIn': animIn,
        'animOut': animOut,
        'animInDur': animInDur,
        'animOutDur': animOutDur,
        'vfx': vfx,
        'loopVideo': loopVideo,
      };

  factory VisualClip.fromJson(Map<String, dynamic> j, {bool newIdentity = false}) {
    final crop = (j['crop'] as List?)?.map((e) => jd(e)).toList() ?? [0.0, 0.0, 1.0, 1.0];
    return VisualClip(
      id: newIdentity ? null : js(j['id']),
      kind: ClipKind.values.firstWhere((e) => e.name == j['kind'], orElse: () => ClipKind.image),
      assetId: j['assetId'] as String?,
      color: js(j['color'], '#000000'),
      srcIn: jd(j['srcIn']),
      srcOut: jd(j['srcOut']),
      imageDuration: jd(j['imageDuration'], 3),
      speed: jd(j['speed'], 1),
      reverse: jb(j['reverse']),
      freezeAt: jd(j['freezeAt'], -1),
      freezeDuration: jd(j['freezeDuration']),
      fit: FitMode.values.firstWhere((e) => e.name == j['fit'], orElse: () => FitMode.cover),
      motion: Motion.fromJson(jm(j['motion'])),
      grade: ColorGrade.fromJson(jm(j['grade'])),
      transition: Transition.fromJson(jm(j['transition'])),
      rotate: ji(j['rotate']),
      flipH: jb(j['flipH']),
      flipV: jb(j['flipV']),
      cropX: crop[0],
      cropY: crop[1],
      cropW: crop[2],
      cropH: crop[3],
      volumeDb: jd(j['volumeDb']),
      mute: jb(j['mute']),
      animIn: js(j['animIn'], 'none'),
      animOut: js(j['animOut'], 'none'),
      animInDur: jd(j['animInDur'], 0.5),
      animOutDur: jd(j['animOutDur'], 0.5),
      vfx: (j['vfx'] as List?)?.map((e) => '$e').toList() ?? [],
      loopVideo: jb(j['loopVideo']),
    );
  }

  VisualClip copy() => VisualClip.fromJson(toJson(), newIdentity: true);
}

enum MaskShape { none, circle, rounded, ellipse, heart, star }

/// Overlay layer: PIP video, photo, logo, sticker, PNG/GIF/WebM with alpha.
class OverlayItem {
  final String id;
  String assetId;
  String name;
  double start;
  double duration;
  double srcIn; // for video overlays
  /// Position of centre in normalised frame coords (0..1); keyframes allowed.
  double x, y;
  double scale; // width relative to frame width
  double rotation;
  double opacity;
  List<Keyframe> xKf, yKf, scaleKf, rotKf;
  bool chromaKey;
  String keyColor;
  double keySimilarity, keyBlend;
  MaskShape mask;
  String? maskAssetId; // grayscale mask image
  double borderWidth;
  String borderColor;
  String animIn, animOut;
  double animInDur, animOutDur;
  bool loop;
  double volumeDb;
  bool mute;
  int layer; // z-order
  String group; // grouping id
  bool locked, hidden;

  OverlayItem({
    String? id,
    required this.assetId,
    this.name = '',
    this.start = 0,
    this.duration = 3,
    this.srcIn = 0,
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 0.3,
    this.rotation = 0,
    this.opacity = 1,
    List<Keyframe>? xKf,
    List<Keyframe>? yKf,
    List<Keyframe>? scaleKf,
    List<Keyframe>? rotKf,
    this.chromaKey = false,
    this.keyColor = '#00FF00',
    this.keySimilarity = 0.15,
    this.keyBlend = 0.05,
    this.mask = MaskShape.none,
    this.maskAssetId,
    this.borderWidth = 0,
    this.borderColor = '#FFFFFF',
    this.animIn = 'none',
    this.animOut = 'none',
    this.animInDur = 0.4,
    this.animOutDur = 0.4,
    this.loop = true,
    this.volumeDb = 0,
    this.mute = true,
    this.layer = 0,
    this.group = '',
    this.locked = false,
    this.hidden = false,
  })  : id = id ?? newId(),
        xKf = xKf ?? [],
        yKf = yKf ?? [],
        scaleKf = scaleKf ?? [],
        rotKf = rotKf ?? [];

  double get end => start + duration;

  Map<String, dynamic> toJson() => {
        'id': id,
        'assetId': assetId,
        'name': name,
        'start': start,
        'duration': duration,
        'srcIn': srcIn,
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
        'opacity': opacity,
        'xKf': xKf.map((e) => e.toJson()).toList(),
        'yKf': yKf.map((e) => e.toJson()).toList(),
        'scaleKf': scaleKf.map((e) => e.toJson()).toList(),
        'rotKf': rotKf.map((e) => e.toJson()).toList(),
        'chromaKey': chromaKey,
        'keyColor': keyColor,
        'keySimilarity': keySimilarity,
        'keyBlend': keyBlend,
        'mask': mask.name,
        'maskAssetId': maskAssetId,
        'borderWidth': borderWidth,
        'borderColor': borderColor,
        'animIn': animIn,
        'animOut': animOut,
        'animInDur': animInDur,
        'animOutDur': animOutDur,
        'loop': loop,
        'volumeDb': volumeDb,
        'mute': mute,
        'layer': layer,
        'group': group,
        'locked': locked,
        'hidden': hidden,
      };

  factory OverlayItem.fromJson(Map<String, dynamic> j, {bool newIdentity = false}) => OverlayItem(
        id: newIdentity ? null : js(j['id']),
        assetId: js(j['assetId']),
        name: js(j['name']),
        start: jd(j['start']),
        duration: jd(j['duration'], 3),
        srcIn: jd(j['srcIn']),
        x: jd(j['x'], 0.5),
        y: jd(j['y'], 0.5),
        scale: jd(j['scale'], 0.3),
        rotation: jd(j['rotation']),
        opacity: jd(j['opacity'], 1),
        xKf: jl(j['xKf']).map(Keyframe.fromJson).toList(),
        yKf: jl(j['yKf']).map(Keyframe.fromJson).toList(),
        scaleKf: jl(j['scaleKf']).map(Keyframe.fromJson).toList(),
        rotKf: jl(j['rotKf']).map(Keyframe.fromJson).toList(),
        chromaKey: jb(j['chromaKey']),
        keyColor: js(j['keyColor'], '#00FF00'),
        keySimilarity: jd(j['keySimilarity'], 0.15),
        keyBlend: jd(j['keyBlend'], 0.05),
        mask: MaskShape.values.firstWhere((e) => e.name == j['mask'], orElse: () => MaskShape.none),
        maskAssetId: j['maskAssetId'] as String?,
        borderWidth: jd(j['borderWidth']),
        borderColor: js(j['borderColor'], '#FFFFFF'),
        animIn: js(j['animIn'], 'none'),
        animOut: js(j['animOut'], 'none'),
        animInDur: jd(j['animInDur'], 0.4),
        animOutDur: jd(j['animOutDur'], 0.4),
        loop: jb(j['loop'], true),
        volumeDb: jd(j['volumeDb']),
        mute: jb(j['mute'], true),
        layer: ji(j['layer']),
        group: js(j['group']),
        locked: jb(j['locked']),
        hidden: jb(j['hidden']),
      );
}

/// Text style shared by titles, captions, lyrics.
class TextStyleSpec {
  String font; // family name; file resolved via fonts dir
  double size; // px at output height 1080 (scaled)
  String color; // #RRGGBB
  String highlightColor; // karaoke fill
  String outlineColor;
  double outline;
  String shadowColor;
  double shadow;
  bool bold, italic;
  String align; // 'bottom','center','top'
  double marginV; // px
  double opacity;
  String? gradientTo; // optional 2nd colour (vertical gradient via ASS \t)
  double letterSpacing;
  bool box; // background box
  String boxColor;

  TextStyleSpec({
    this.font = 'Noto Sans',
    this.size = 64,
    this.color = '#FFFFFF',
    this.highlightColor = '#FFD400',
    this.outlineColor = '#000000',
    this.outline = 3,
    this.shadowColor = '#000000',
    this.shadow = 2,
    this.bold = true,
    this.italic = false,
    this.align = 'bottom',
    this.marginV = 120,
    this.opacity = 1,
    this.gradientTo,
    this.letterSpacing = 0,
    this.box = false,
    this.boxColor = '#000000',
  });

  Map<String, dynamic> toJson() => {
        'font': font,
        'size': size,
        'color': color,
        'highlightColor': highlightColor,
        'outlineColor': outlineColor,
        'outline': outline,
        'shadowColor': shadowColor,
        'shadow': shadow,
        'bold': bold,
        'italic': italic,
        'align': align,
        'marginV': marginV,
        'opacity': opacity,
        'gradientTo': gradientTo,
        'letterSpacing': letterSpacing,
        'box': box,
        'boxColor': boxColor,
      };
  factory TextStyleSpec.fromJson(Map<String, dynamic> j) => TextStyleSpec(
        font: js(j['font'], 'Noto Sans'),
        size: jd(j['size'], 64),
        color: js(j['color'], '#FFFFFF'),
        highlightColor: js(j['highlightColor'], '#FFD400'),
        outlineColor: js(j['outlineColor'], '#000000'),
        outline: jd(j['outline'], 3),
        shadowColor: js(j['shadowColor'], '#000000'),
        shadow: jd(j['shadow'], 2),
        bold: jb(j['bold'], true),
        italic: jb(j['italic']),
        align: js(j['align'], 'bottom'),
        marginV: jd(j['marginV'], 120),
        opacity: jd(j['opacity'], 1),
        gradientTo: j['gradientTo'] as String?,
        letterSpacing: jd(j['letterSpacing']),
        box: jb(j['box']),
        boxColor: js(j['boxColor'], '#000000'),
      );
  TextStyleSpec copy() => TextStyleSpec.fromJson(toJson());
}

/// Text animations (rendered with libass override tags).
const textAnimNames = <String, String>{
  'none': 'Statyczny',
  'fade': 'Pojawianie',
  'typewriter': 'Maszyna do pisania (litery)',
  'wordPop': 'Słowo po słowie',
  'zoomIn': 'Powiększenie',
  'slideUp': 'Wjazd z dołu',
  'slideLeft': 'Wjazd z prawej',
  'bounce': 'Odbicie',
  'spin': 'Obrót',
  'glow': 'Pulsujące świecenie',
  'scroll': 'Przewijanie (napisy końcowe)',
  'marquee': 'Pasek przewijany',
  'letterWave': 'Fala liter',
};

class TextItem {
  final String id;
  String text;
  double start, duration;
  double x, y; // normalised position of anchor (centre); <0 => use style align
  TextStyleSpec style;
  String anim;
  double animDur;
  int layer;
  bool hidden;
  TextItem({String? id, required this.text, this.start = 0, this.duration = 3, this.x = -1, this.y = -1, TextStyleSpec? style, this.anim = 'fade', this.animDur = 0.5, this.layer = 0, this.hidden = false})
      : id = id ?? newId(),
        style = style ?? TextStyleSpec();
  double get end => start + duration;
  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'start': start, 'duration': duration, 'x': x, 'y': y, 'style': style.toJson(), 'anim': anim, 'animDur': animDur, 'layer': layer, 'hidden': hidden};
  factory TextItem.fromJson(Map<String, dynamic> j) => TextItem(
        id: js(j['id']),
        text: js(j['text']),
        start: jd(j['start']),
        duration: jd(j['duration'], 3),
        x: jd(j['x'], -1),
        y: jd(j['y'], -1),
        style: TextStyleSpec.fromJson(jm(j['style'])),
        anim: js(j['anim'], 'fade'),
        animDur: jd(j['animDur'], 0.5),
        layer: ji(j['layer']),
        hidden: jb(j['hidden']),
      );
}

/// Visual effect layer (particles, looks) over a time range.
class VfxItem {
  final String id;
  String type; // see vfx.dart
  double start, duration; // duration <= 0 => until end
  double intensity; // 0..1
  String color;
  bool reactive; // modulated by music energy/beats
  VfxItem({String? id, required this.type, this.start = 0, this.duration = 0, this.intensity = 0.6, this.color = '#FFFFFF', this.reactive = false}) : id = id ?? newId();
  Map<String, dynamic> toJson() => {'id': id, 'type': type, 'start': start, 'duration': duration, 'intensity': intensity, 'color': color, 'reactive': reactive};
  factory VfxItem.fromJson(Map<String, dynamic> j) =>
      VfxItem(id: js(j['id']), type: js(j['type']), start: jd(j['start']), duration: jd(j['duration']), intensity: jd(j['intensity'], 0.6), color: js(j['color'], '#FFFFFF'), reactive: jb(j['reactive']));
}

/// Music visualiser layer.
class VisualizerItem {
  final String id;
  String style; // see visualizer.dart
  double start, duration; // duration <= 0 => whole
  double x, y, width, height; // normalised rect
  String color, color2;
  double intensity;
  double opacity;
  String? logoAssetId;
  double logoSize; // fraction of min(W,H)
  bool bassPulse;
  VisualizerItem({String? id, this.style = 'bars', this.start = 0, this.duration = 0, this.x = 0, this.y = 0.6, this.width = 1, this.height = 0.4, this.color = '#35D0BA', this.color2 = '#FF4FA3', this.intensity = 1, this.opacity = 0.9, this.logoAssetId, this.logoSize = 0.25, this.bassPulse = true})
      : id = id ?? newId();
  Map<String, dynamic> toJson() => {
        'id': id,
        'style': style,
        'start': start,
        'duration': duration,
        'rect': [x, y, width, height],
        'color': color,
        'color2': color2,
        'intensity': intensity,
        'opacity': opacity,
        'logo': logoAssetId,
        'logoSize': logoSize,
        'bassPulse': bassPulse,
      };
  factory VisualizerItem.fromJson(Map<String, dynamic> j) {
    final r = (j['rect'] as List?)?.map((e) => jd(e)).toList() ?? [0.0, 0.6, 1.0, 0.4];
    return VisualizerItem(
      id: js(j['id']),
      style: js(j['style'], 'bars'),
      start: jd(j['start']),
      duration: jd(j['duration']),
      x: r[0],
      y: r[1],
      width: r[2],
      height: r[3],
      color: js(j['color'], '#35D0BA'),
      color2: js(j['color2'], '#FF4FA3'),
      intensity: jd(j['intensity'], 1),
      opacity: jd(j['opacity'], 0.9),
      logoAssetId: j['logo'] as String?,
      logoSize: jd(j['logoSize'], 0.25),
      bassPulse: jb(j['bassPulse'], true),
    );
  }
}

/// Complete video project.
class VideoProject {
  int width, height;
  double fps;
  String background;
  List<VisualClip> clips;
  List<OverlayItem> overlays;
  List<TextItem> texts;
  List<VfxItem> vfx;
  List<VisualizerItem> visualizers;
  LyricsTrack? lyrics;
  AudioProject audio; // music / voice-over tracks
  bool clipAudio; // include audio of video clips
  double clipAudioDb;
  /// Asset id of the main music (used for beat analysis / reactive fx).
  String? musicAssetId;
  List<double> beatMarkers; // manual or analysed beats
  ColorGrade globalGrade;
  double? fixedDuration; // when set, output is padded/trimmed to this

  VideoProject({
    this.width = 1080,
    this.height = 1920,
    this.fps = 30,
    this.background = '#000000',
    List<VisualClip>? clips,
    List<OverlayItem>? overlays,
    List<TextItem>? texts,
    List<VfxItem>? vfx,
    List<VisualizerItem>? visualizers,
    this.lyrics,
    AudioProject? audio,
    this.clipAudio = true,
    this.clipAudioDb = 0,
    this.musicAssetId,
    List<double>? beatMarkers,
    ColorGrade? globalGrade,
    this.fixedDuration,
  })  : clips = clips ?? [],
        overlays = overlays ?? [],
        texts = texts ?? [],
        vfx = vfx ?? [],
        visualizers = visualizers ?? [],
        audio = audio ?? AudioProject(tracks: [AudioTrack(name: 'Muzyka'), AudioTrack(name: 'Lektor')]),
        beatMarkers = beatMarkers ?? [],
        globalGrade = globalGrade ?? ColorGrade();

  /// Start time of each clip accounting for transition overlaps.
  List<double> clipStarts() {
    final out = <double>[];
    var t = 0.0;
    for (var i = 0; i < clips.length; i++) {
      out.add(t);
      final c = clips[i];
      t += c.duration;
      if (i < clips.length - 1 && !c.transition.isCut) {
        t -= effectiveTransition(i);
      }
    }
    return out;
  }

  /// Transition duration clamped to half of neighbouring clips.
  double effectiveTransition(int i) {
    if (i >= clips.length - 1) return 0;
    final c = clips[i];
    if (c.transition.isCut) return 0;
    final maxD = [c.duration, clips[i + 1].duration].reduce((a, b) => a < b ? a : b) * 0.5;
    return c.transition.duration.clamp(0.05, maxD);
  }

  double get visualDuration {
    if (clips.isEmpty) return 0;
    final s = clipStarts();
    return s.last + clips.last.duration;
  }

  double get duration {
    if (fixedDuration != null) return fixedDuration!;
    var d = visualDuration;
    for (final o in overlays) {
      if (o.end > d) d = o.end;
    }
    for (final t in texts) {
      if (t.end > d) d = t.end;
    }
    if (clips.isEmpty) d = audio.duration > d ? audio.duration : d;
    return d;
  }

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'fps': fps,
        'background': background,
        'clips': clips.map((e) => e.toJson()).toList(),
        'overlays': overlays.map((e) => e.toJson()).toList(),
        'texts': texts.map((e) => e.toJson()).toList(),
        'vfx': vfx.map((e) => e.toJson()).toList(),
        'visualizers': visualizers.map((e) => e.toJson()).toList(),
        'lyrics': lyrics?.toJson(),
        'audio': audio.toJson(),
        'clipAudio': clipAudio,
        'clipAudioDb': clipAudioDb,
        'musicAssetId': musicAssetId,
        'beatMarkers': beatMarkers,
        'globalGrade': globalGrade.toJson(),
        'fixedDuration': fixedDuration,
      };

  factory VideoProject.fromJson(Map<String, dynamic> j) => VideoProject(
        width: ji(j['width'], 1080),
        height: ji(j['height'], 1920),
        fps: jd(j['fps'], 30),
        background: js(j['background'], '#000000'),
        clips: jl(j['clips']).map(VisualClip.fromJson).toList(),
        overlays: jl(j['overlays']).map(OverlayItem.fromJson).toList(),
        texts: jl(j['texts']).map(TextItem.fromJson).toList(),
        vfx: jl(j['vfx']).map(VfxItem.fromJson).toList(),
        visualizers: jl(j['visualizers']).map(VisualizerItem.fromJson).toList(),
        lyrics: j['lyrics'] == null ? null : LyricsTrack.fromJson(jm(j['lyrics'])),
        audio: j['audio'] == null ? null : AudioProject.fromJson(jm(j['audio'])),
        clipAudio: jb(j['clipAudio'], true),
        clipAudioDb: jd(j['clipAudioDb']),
        musicAssetId: j['musicAssetId'] as String?,
        beatMarkers: (j['beatMarkers'] as List?)?.map((e) => jd(e)).toList() ?? [],
        globalGrade: ColorGrade.fromJson(jm(j['globalGrade'])),
        fixedDuration: j['fixedDuration'] == null ? null : jd(j['fixedDuration']),
      );

  // --------------------------------------------------------------- editing
  void moveClip(int from, int to) {
    final c = clips.removeAt(from);
    clips.insert(to.clamp(0, clips.length), c);
  }

  /// Splits clip [index] at timeline time [t]. Returns the new clip.
  VisualClip? splitClip(int index, double t) {
    final starts = clipStarts();
    final c = clips[index];
    final rel = t - starts[index];
    if (rel <= 0.05 || rel >= c.duration - 0.05) return null;
    final right = c.copy();
    if (c.kind == ClipKind.video) {
      final srcRel = rel * c.speed;
      right.srcIn = c.srcIn + srcRel;
      c.srcOut = c.srcIn + srcRel;
    } else {
      right.imageDuration = c.imageDuration - rel;
      c.imageDuration = rel;
    }
    right.transition = c.transition;
    c.transition = Transition();
    right.animIn = 'none';
    c.animOut = 'none';
    clips.insert(index + 1, right);
    return right;
  }

  VisualClip duplicateClip(int index) {
    final c = clips[index].copy();
    clips.insert(index + 1, c);
    return c;
  }

  /// Applies one transition to all clips (auto-apply).
  void applyTransitionToAll(String type, double duration) {
    for (var i = 0; i < clips.length - 1; i++) {
      clips[i].transition = Transition(type: type, duration: duration);
    }
  }

  /// Duration of the music/audio tracks (0 if none).
  double get audioDuration => audio.duration;

  /// Stretches the TIMING (never the pixels) of the visual track so the film
  /// lasts exactly as long as the audio. Photos get proportionally longer
  /// display times (one photo = whole song); video clips keep their speed –
  /// if they are longer than the audio the film is trimmed, if shorter the
  /// last clip loops. Images are never stretched: [FitMode.stretch] is
  /// replaced by [fit] (default: blurred background, whole picture visible).
  /// Returns false when there is no audio or no visual clip.
  bool fitToAudio({FitMode fit = FitMode.blurBackground, double? target}) {
    final t = target ?? audioDuration;
    if (t <= 0 || clips.isEmpty) return false;
    for (final c in clips) {
      if (c.fit == FitMode.stretch) c.fit = fit;
    }
    double transitions() {
      var s = 0.0;
      for (var i = 0; i < clips.length - 1; i++) {
        s += effectiveTransition(i);
      }
      return s;
    }

    final images = clips.where((c) => c.kind != ClipKind.video).toList();
    final videoLen = clips.where((c) => c.kind == ClipKind.video).fold(0.0, (s, c) => s + c.duration);
    if (images.isNotEmpty) {
      // iterate: transition lengths depend on clip lengths
      for (var k = 0; k < 4; k++) {
        final imgLen = images.fold(0.0, (s, c) => s + c.imageDuration);
        final need = t + transitions() - videoLen;
        if (need <= 0.1 * images.length || imgLen <= 0) break;
        final f = need / imgLen;
        for (final c in images) {
          c.imageDuration = (c.imageDuration * f).clamp(0.3, 36000.0);
        }
      }
    } else if (visualDuration < t) {
      final last = clips.last;
      last.loopVideo = true;
      last.imageDuration = last.duration + (t - visualDuration);
    }
    // Long single shots: keep camera motion gentle over the whole song.
    for (final c in images) {
      if (c.imageDuration > 20 && c.motion.intensity > 0.35) c.motion.intensity = 0.35;
    }
    fixedDuration = t;
    return true;
  }

  /// Sets display duration for all photos.
  void setAllImageDurations(double d) {
    for (final c in clips) {
      if (c.kind != ClipKind.video) c.imageDuration = d;
    }
  }
}
