import '../util/json_util.dart';

/// Editable music-video style template.
class StyleTemplate {
  String id;
  String name;
  bool builtIn;
  String font;
  String textColor;
  String accentColor;
  String outlineColor;
  List<String> transitions;
  double transitionBeats; // transition length in beats
  List<String> motions; // MotionPreset names
  double motionIntensity;
  int cutEveryBeats;
  List<String> vfx; // vfx ids
  bool reactiveVfx;
  String grade; // look name
  String textAnim;
  String visualizer; // visualizer style
  String visualizerColor;
  String visualizerColor2;
  String background;
  bool beatPulse;

  StyleTemplate({
    required this.id,
    required this.name,
    this.builtIn = false,
    this.font = 'Noto Sans',
    this.textColor = '#FFFFFF',
    this.accentColor = '#FFD400',
    this.outlineColor = '#000000',
    this.transitions = const ['fade'],
    this.transitionBeats = 1,
    this.motions = const ['kenBurnsIn', 'kenBurnsOut'],
    this.motionIntensity = 0.5,
    this.cutEveryBeats = 4,
    this.vfx = const [],
    this.reactiveVfx = true,
    this.grade = '',
    this.textAnim = 'fade',
    this.visualizer = 'bars',
    this.visualizerColor = '#35D0BA',
    this.visualizerColor2 = '#FF4FA3',
    this.background = '#000000',
    this.beatPulse = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'builtIn': builtIn,
        'font': font,
        'textColor': textColor,
        'accentColor': accentColor,
        'outlineColor': outlineColor,
        'transitions': transitions,
        'transitionBeats': transitionBeats,
        'motions': motions,
        'motionIntensity': motionIntensity,
        'cutEveryBeats': cutEveryBeats,
        'vfx': vfx,
        'reactiveVfx': reactiveVfx,
        'grade': grade,
        'textAnim': textAnim,
        'visualizer': visualizer,
        'visualizerColor': visualizerColor,
        'visualizerColor2': visualizerColor2,
        'background': background,
        'beatPulse': beatPulse,
      };

  factory StyleTemplate.fromJson(Map<String, dynamic> j) => StyleTemplate(
        id: js(j['id']),
        name: js(j['name']),
        builtIn: jb(j['builtIn']),
        font: js(j['font'], 'Noto Sans'),
        textColor: js(j['textColor'], '#FFFFFF'),
        accentColor: js(j['accentColor'], '#FFD400'),
        outlineColor: js(j['outlineColor'], '#000000'),
        transitions: (j['transitions'] as List?)?.map((e) => '$e').toList() ?? ['fade'],
        transitionBeats: jd(j['transitionBeats'], 1),
        motions: (j['motions'] as List?)?.map((e) => '$e').toList() ?? ['kenBurnsIn'],
        motionIntensity: jd(j['motionIntensity'], 0.5),
        cutEveryBeats: ji(j['cutEveryBeats'], 4),
        vfx: (j['vfx'] as List?)?.map((e) => '$e').toList() ?? [],
        reactiveVfx: jb(j['reactiveVfx'], true),
        grade: js(j['grade']),
        textAnim: js(j['textAnim'], 'fade'),
        visualizer: js(j['visualizer'], 'bars'),
        visualizerColor: js(j['visualizerColor'], '#35D0BA'),
        visualizerColor2: js(j['visualizerColor2'], '#FF4FA3'),
        background: js(j['background'], '#000000'),
        beatPulse: jb(j['beatPulse']),
      );

  StyleTemplate copyAs(String newId, String newName) => StyleTemplate.fromJson({...toJson(), 'id': newId, 'name': newName, 'builtIn': false});
}

/// 20 factory styles (all parameters editable; saved copies become user templates).
final factoryStyles = <StyleTemplate>[
  StyleTemplate(id: 'slavic_folk', name: 'Słowiański Folk', builtIn: true, font: 'Playfair Display', textColor: '#F4E3C1', accentColor: '#C8102E', transitions: ['fade', 'dissolve', 'filmburn'], transitionBeats: 2, motions: ['kenBurnsIn', 'panRight', 'kenBurnsOut', 'parallax'], cutEveryBeats: 8, vfx: ['fog', 'dust', 'vignette'], grade: 'golden', textAnim: 'fade', visualizer: 'circle', visualizerColor: '#E8C170'),
  StyleTemplate(id: 'reggae', name: 'Reggae', builtIn: true, font: 'Lobster', textColor: '#FFD400', accentColor: '#1DB954', transitions: ['slideleft', 'smoothleft', 'fade'], motions: ['panLeft', 'panRight', 'kenBurnsIn'], cutEveryBeats: 8, vfx: ['lights'], grade: 'warm', textAnim: 'bounce', visualizer: 'bars', visualizerColor: '#1DB954', visualizerColor2: '#E4002B'),
  StyleTemplate(id: 'hiphop', name: 'Hip-Hop', builtIn: true, font: 'Anton', textColor: '#FFFFFF', accentColor: '#FFC400', transitions: ['cut', 'slideup', 'zoomin'], transitionBeats: 0.5, motions: ['beatPulse', 'kenBurnsIn', 'shake'], motionIntensity: 0.7, cutEveryBeats: 4, vfx: ['beatflash', 'vignette'], grade: 'vivid', textAnim: 'wordPop', visualizer: 'wave', beatPulse: true),
  StyleTemplate(id: 'boombap', name: 'Boom Bap', builtIn: true, font: 'Bebas Neue', textColor: '#F1E9DA', accentColor: '#D9A441', transitions: ['cut', 'fadeblack'], transitionBeats: 0.5, motions: ['kenBurnsIn', 'beatPulse'], cutEveryBeats: 4, vfx: ['retro', 'dust'], grade: 'vintage', textAnim: 'typewriter', visualizer: 'bars', visualizerColor: '#D9A441', beatPulse: true),
  StyleTemplate(id: 'rock', name: 'Rock', builtIn: true, font: 'Oswald', textColor: '#FFFFFF', accentColor: '#E10600', transitions: ['fadewhite', 'cut', 'hblur'], transitionBeats: 0.5, motions: ['shake', 'kenBurnsIn', 'zoomInRotate'], motionIntensity: 0.6, cutEveryBeats: 4, vfx: ['sparks', 'lightning'], grade: 'noir', textAnim: 'zoomIn', visualizer: 'bars', visualizerColor: '#E10600'),
  StyleTemplate(id: 'punk', name: 'Punk Rock', builtIn: true, font: 'Rubik Glitch', textColor: '#FF2D95', accentColor: '#C6FF00', transitions: ['cut', 'glitch', 'pixelize'], transitionBeats: 0.5, motions: ['shake', 'beatPulse'], motionIntensity: 0.9, cutEveryBeats: 2, vfx: ['glitch', 'rgbsplit', 'vhs'], grade: 'cross', textAnim: 'wordPop', visualizer: 'wavebars', visualizerColor: '#C6FF00', beatPulse: true),
  StyleTemplate(id: 'dark_trap', name: 'Dark Trap', builtIn: true, font: 'Anton', textColor: '#E0E0E0', accentColor: '#8A2BE2', transitions: ['fadeblack', 'glitch', 'zoomin'], transitionBeats: 1, motions: ['beatPulse', 'kenBurnsOut', 'zoomOutRotate'], motionIntensity: 0.7, cutEveryBeats: 4, vfx: ['smoke', 'bassglow', 'vignette'], grade: 'horror', textAnim: 'glow', visualizer: 'circle', visualizerColor: '#8A2BE2', beatPulse: true),
  StyleTemplate(id: 'phonk', name: 'Phonk', builtIn: true, font: 'Press Start 2P', textColor: '#FF3EA5', accentColor: '#00F0FF', transitions: ['cut', 'glitch', 'fadewhite'], transitionBeats: 0.5, motions: ['shake', 'beatPulse'], motionIntensity: 1, cutEveryBeats: 2, vfx: ['vhs', 'beatflash', 'rgbsplit'], grade: 'neon_night', textAnim: 'wordPop', visualizer: 'oscilloscope', visualizerColor: '#FF3EA5', beatPulse: true),
  StyleTemplate(id: 'techno', name: 'Techno', builtIn: true, font: 'Monoton', textColor: '#00F0FF', accentColor: '#FF00E5', transitions: ['cut', 'pixelize', 'rectcrop'], transitionBeats: 0.5, motions: ['beatPulse', 'zoomInRotate'], motionIntensity: 0.8, cutEveryBeats: 4, vfx: ['neon', 'beatflash', 'lights'], grade: 'cool', textAnim: 'glow', visualizer: 'spectrogram', visualizerColor: '#00F0FF', beatPulse: true),
  StyleTemplate(id: 'cinematic', name: 'Cinematic', builtIn: true, font: 'Playfair Display', textColor: '#FFFFFF', accentColor: '#E6B656', transitions: ['fade', 'fadeblack', 'dissolve'], transitionBeats: 4, motions: ['kenBurnsIn', 'kenBurnsOut', 'panRight', 'parallax'], motionIntensity: 0.4, cutEveryBeats: 8, vfx: ['cinematic', 'flare'], grade: 'teal_orange', textAnim: 'fade', visualizer: 'line'),
  StyleTemplate(id: 'epic', name: 'Epic', builtIn: true, font: 'Oswald', textColor: '#FFF4D6', accentColor: '#FF8C00', transitions: ['fadewhite', 'zoomin', 'circleopen'], transitionBeats: 2, motions: ['zoomInRotate', 'kenBurnsIn', 'parallax'], motionIntensity: 0.7, cutEveryBeats: 8, vfx: ['sparks', 'lights', 'cinematic'], grade: 'golden', textAnim: 'zoomIn', visualizer: 'circle', visualizerColor: '#FF8C00'),
  StyleTemplate(id: 'minimal', name: 'Minimalistyczny', builtIn: true, font: 'Noto Sans', textColor: '#FFFFFF', accentColor: '#9E9E9E', transitions: ['fade'], transitionBeats: 2, motions: ['kenBurnsIn'], motionIntensity: 0.25, cutEveryBeats: 8, vfx: [], grade: '', textAnim: 'fade', visualizer: 'line', visualizerColor: '#FFFFFF'),
  StyleTemplate(id: 'patriotic', name: 'Patriotyczny', builtIn: true, font: 'Oswald', textColor: '#FFFFFF', accentColor: '#DC143C', transitions: ['fade', 'wiperight', 'dissolve'], transitionBeats: 2, motions: ['kenBurnsIn', 'panUp', 'parallax'], cutEveryBeats: 8, vfx: ['flare', 'vignette'], grade: 'golden', textAnim: 'slideUp', visualizer: 'bars', visualizerColor: '#FFFFFF', visualizerColor2: '#DC143C'),
  StyleTemplate(id: 'retro', name: 'Retro', builtIn: true, font: 'Pacifico', textColor: '#FFE6A7', accentColor: '#FF6F59', transitions: ['dissolve', 'wipeleft', 'circleclose'], transitionBeats: 2, motions: ['kenBurnsIn', 'panLeft'], cutEveryBeats: 8, vfx: ['retro', 'oldfilm'], grade: 'vintage', textAnim: 'typewriter', visualizer: 'bars', visualizerColor: '#FF6F59'),
  StyleTemplate(id: 'neon', name: 'Neon', builtIn: true, font: 'Monoton', textColor: '#FF2BD6', accentColor: '#2BFFF5', transitions: ['fadeblack', 'radial', 'glitch'], transitionBeats: 1, motions: ['beatPulse', 'zoomInRotate'], cutEveryBeats: 4, vfx: ['neon', 'bassglow', 'frame'], grade: 'neon_night', textAnim: 'glow', visualizer: 'circle', visualizerColor: '#2BFFF5', beatPulse: true),
  StyleTemplate(id: 'horror', name: 'Horror', builtIn: true, font: 'Nosifer', textColor: '#B30000', accentColor: '#FFFFFF', transitions: ['fadeblack', 'glitch', 'hblur'], transitionBeats: 2, motions: ['shake', 'kenBurnsOut'], motionIntensity: 0.5, cutEveryBeats: 8, vfx: ['fog', 'lightning', 'oldfilm'], grade: 'horror', textAnim: 'fade', visualizer: 'oscilloscope', visualizerColor: '#B30000'),
  StyleTemplate(id: 'romantic', name: 'Romantyczny', builtIn: true, font: 'Caveat', textColor: '#FFF0F5', accentColor: '#FF69B4', transitions: ['fade', 'dissolve', 'circleopen'], transitionBeats: 3, motions: ['kenBurnsIn', 'kenBurnsOut'], motionIntensity: 0.35, cutEveryBeats: 8, vfx: ['particles', 'lights'], grade: 'pastel', textAnim: 'fade', visualizer: 'circle', visualizerColor: '#FF69B4'),
  StyleTemplate(id: 'comedy', name: 'Komediowy', builtIn: true, font: 'Lobster', textColor: '#FFEB3B', accentColor: '#03A9F4', transitions: ['spin', 'squeezeh', 'slideright'], transitionBeats: 1, motions: ['zoomInRotate', 'shake', 'beatPulse'], motionIntensity: 0.8, cutEveryBeats: 4, vfx: ['frame'], grade: 'vivid', textAnim: 'bounce', visualizer: 'bars', visualizerColor: '#03A9F4'),
  StyleTemplate(id: 'christmas', name: 'Świąteczny', builtIn: true, font: 'Lobster', textColor: '#FFFFFF', accentColor: '#C62828', transitions: ['fade', 'circleopen', 'dissolve'], transitionBeats: 2, motions: ['kenBurnsIn', 'panDown'], cutEveryBeats: 8, vfx: ['snow', 'lights'], grade: 'warm', textAnim: 'letterWave', visualizer: 'circle', visualizerColor: '#C62828', visualizerColor2: '#2E7D32'),
  StyleTemplate(id: 'birthday', name: 'Urodzinowy', builtIn: true, font: 'Pacifico', textColor: '#FFFFFF', accentColor: '#FF9800', transitions: ['spin', 'zoomin', 'circleopen'], transitionBeats: 1, motions: ['zoomInRotate', 'kenBurnsIn', 'beatPulse'], cutEveryBeats: 4, vfx: ['particles', 'sparks', 'frame'], grade: 'vivid', textAnim: 'bounce', visualizer: 'bars', visualizerColor: '#FF9800'),
];

StyleTemplate styleById(String id, [List<StyleTemplate> user = const []]) =>
    [...user, ...factoryStyles].firstWhere((s) => s.id == id, orElse: () => factoryStyles.first);
