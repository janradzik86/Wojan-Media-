import '../ffmpeg/escape.dart';
import '../util/json_util.dart';

/// Colour correction parameters (all neutral at default).
class ColorGrade {
  double brightness; // -1..1   (eq)
  double contrast; // 0..3, 1 neutral
  double saturation; // 0..3, 1 neutral
  double gamma; // 0.1..3, 1 neutral
  double exposure; // -3..3 EV
  double temperature; // 1000..12000 K, 6500 neutral
  double tint; // -1..1 (magenta/green)
  double sharpness; // -2..5, 0 neutral (unsharp)
  double shadows; // -1..1
  double highlights; // -1..1
  double hue; // degrees
  double vignette; // 0..1
  double grain; // 0..1
  String? lutAssetId; // .cube LUT (lut3d)
  String filter; // named look preset ('' = none)
  double filterStrength; // 0..1

  ColorGrade({
    this.brightness = 0,
    this.contrast = 1,
    this.saturation = 1,
    this.gamma = 1,
    this.exposure = 0,
    this.temperature = 6500,
    this.tint = 0,
    this.sharpness = 0,
    this.shadows = 0,
    this.highlights = 0,
    this.hue = 0,
    this.vignette = 0,
    this.grain = 0,
    this.lutAssetId,
    this.filter = '',
    this.filterStrength = 1,
  });

  bool get isNeutral =>
      brightness == 0 && contrast == 1 && saturation == 1 && gamma == 1 && exposure == 0 && temperature == 6500 && tint == 0 && sharpness == 0 && shadows == 0 && highlights == 0 && hue == 0 && vignette == 0 && grain == 0 && lutAssetId == null && filter.isEmpty;

  Map<String, dynamic> toJson() => {
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'gamma': gamma,
        'exposure': exposure,
        'temperature': temperature,
        'tint': tint,
        'sharpness': sharpness,
        'shadows': shadows,
        'highlights': highlights,
        'hue': hue,
        'vignette': vignette,
        'grain': grain,
        'lut': lutAssetId,
        'filter': filter,
        'filterStrength': filterStrength,
      };

  factory ColorGrade.fromJson(Map<String, dynamic> j) => ColorGrade(
        brightness: jd(j['brightness']),
        contrast: jd(j['contrast'], 1),
        saturation: jd(j['saturation'], 1),
        gamma: jd(j['gamma'], 1),
        exposure: jd(j['exposure']),
        temperature: jd(j['temperature'], 6500),
        tint: jd(j['tint']),
        sharpness: jd(j['sharpness']),
        shadows: jd(j['shadows']),
        highlights: jd(j['highlights']),
        hue: jd(j['hue']),
        vignette: jd(j['vignette']),
        grain: jd(j['grain']),
        lutAssetId: j['lut'] as String?,
        filter: js(j['filter']),
        filterStrength: jd(j['filterStrength'], 1),
      );

  ColorGrade copy() => ColorGrade.fromJson(toJson());

  /// FFmpeg filters implementing this grade. [lutPath] resolves LUT asset.
  List<String> filters({String? lutPath}) {
    final f = <String>[];
    if (exposure != 0) f.add('exposure=exposure=${FfEscape.num(exposure, min: -3, max: 3)}');
    if (brightness != 0 || contrast != 1 || saturation != 1 || gamma != 1) {
      f.add('eq=brightness=${FfEscape.num(brightness, min: -1, max: 1)}:contrast=${FfEscape.num(contrast, min: 0, max: 3)}:saturation=${FfEscape.num(saturation, min: 0, max: 3)}:gamma=${FfEscape.num(gamma, min: 0.1, max: 3)}');
    }
    if (temperature != 6500) f.add('colortemperature=temperature=${FfEscape.num(temperature, min: 1000, max: 40000)}');
    if (tint != 0) f.add('colorbalance=gm=${FfEscape.num(-tint * 0.3)}:gh=${FfEscape.num(-tint * 0.2)}');
    if (shadows != 0 || highlights != 0) {
      // curves: lift/lower dark & bright points
      final s = 0.25 + shadows * 0.15, h = 0.75 + highlights * 0.15;
      f.add("curves=all='0/0 0.25/${FfEscape.num(s, min: 0.02, max: 0.48)} 0.75/${FfEscape.num(h, min: 0.52, max: 0.98)} 1/1'");
    }
    if (hue != 0) f.add('hue=h=${FfEscape.num(hue)}');
    if (filter.isNotEmpty) f.addAll(lookFilters(filter, filterStrength));
    if (lutPath != null) f.add('lut3d=file=${FfEscape.escapePath(lutPath)}');
    if (sharpness != 0) f.add('unsharp=5:5:${FfEscape.num(sharpness, min: -2, max: 5)}:5:5:0');
    if (vignette > 0) f.add('vignette=angle=${FfEscape.num(0.2 + vignette * 0.6)}');
    if (grain > 0) f.add('noise=alls=${(grain * 30).round()}:allf=t');
    return f;
  }
}

/// Named colour filter presets ("filtry kolorystyczne").
const lookNames = <String, String>{
  'bw': 'Czarno-biały',
  'sepia': 'Sepia',
  'vintage': 'Vintage',
  'warm': 'Ciepły',
  'cool': 'Chłodny',
  'teal_orange': 'Teal & Orange (kinowy)',
  'vivid': 'Żywy',
  'fade': 'Wyblakły',
  'noir': 'Noir',
  'cross': 'Cross process',
  'neon_night': 'Neonowa noc',
  'golden': 'Złota godzina',
  'forest': 'Las',
  'horror': 'Horror',
  'pastel': 'Pastelowy',
  'negative': 'Negatyw',
};

List<String> lookFilters(String name, double strength) {
  final s = strength.clamp(0.0, 1.0);
  String n(double v) => FfEscape.num(v);
  switch (name) {
    case 'bw':
      return ['hue=s=${n(1 - s)}'];
    case 'sepia':
      return ['colorchannelmixer=${n(1 - 0.607 * s)}:${n(0.769 * s)}:${n(0.189 * s)}:0:${n(0.349 * s)}:${n(1 - 0.314 * s)}:${n(0.168 * s)}:0:${n(0.272 * s)}:${n(0.534 * s)}:${n(1 - 0.869 * s)}'];
    case 'vintage':
      return ['curves=preset=vintage', 'eq=saturation=${n(1 - 0.25 * s)}'];
    case 'warm':
      return ['colortemperature=temperature=${n(6500 - 2000 * s)}'];
    case 'cool':
      return ['colortemperature=temperature=${n(6500 + 4000 * s)}'];
    case 'teal_orange':
      return ['colorbalance=rs=${n(-0.15 * s)}:bs=${n(0.2 * s)}:rh=${n(0.15 * s)}:bh=${n(-0.15 * s)}', 'eq=contrast=${n(1 + 0.1 * s)}:saturation=${n(1 + 0.15 * s)}'];
    case 'vivid':
      return ['eq=saturation=${n(1 + 0.6 * s)}:contrast=${n(1 + 0.1 * s)}'];
    case 'fade':
      return ["curves=all='0/${n(0.12 * s)} 1/${n(1 - 0.08 * s)}'", 'eq=saturation=${n(1 - 0.3 * s)}'];
    case 'noir':
      return ['hue=s=0', 'eq=contrast=${n(1 + 0.5 * s)}:brightness=${n(-0.05 * s)}'];
    case 'cross':
      return ['curves=preset=cross_process'];
    case 'neon_night':
      return ['colorbalance=bs=${n(0.3 * s)}:rh=${n(0.2 * s)}', 'eq=saturation=${n(1 + 0.5 * s)}:contrast=${n(1 + 0.2 * s)}'];
    case 'golden':
      return ['colortemperature=temperature=${n(6500 - 2500 * s)}', 'eq=saturation=${n(1 + 0.2 * s)}:gamma=${n(1 + 0.05 * s)}'];
    case 'forest':
      return ['colorbalance=gm=${n(0.15 * s)}:bh=${n(-0.1 * s)}', 'eq=saturation=${n(1 + 0.1 * s)}'];
    case 'horror':
      return ['eq=saturation=${n(1 - 0.6 * s)}:contrast=${n(1 + 0.4 * s)}:brightness=${n(-0.08 * s)}', 'colorbalance=gs=${n(0.1 * s)}'];
    case 'pastel':
      return ["curves=all='0/${n(0.15 * s)} 1/1'", 'eq=saturation=${n(1 - 0.35 * s)}:brightness=${n(0.04 * s)}'];
    case 'negative':
      return ['negate'];
  }
  return [];
}
