import 'model.dart';

/// Ready-made intro ("Wstęp") presets. An intro inserts a short opening
/// card at the beginning of the film (colour or first-photo clip), an
/// animated title and matching effects limited to the intro time range.
/// Everything is built from regular project elements, so it is editable
/// afterwards and rendered by the same engine as the rest of the film.
class IntroPreset {
  final String id, name;
  final String background; // colour of the opening card ('' = use first clip)
  final double duration;
  final String font, color, anim;
  final String? gradientTo, outlineColor;
  final double size;
  final List<String> vfx;
  final String transition;
  final String subtitle;
  const IntroPreset(this.id, this.name,
      {this.background = '#000000',
      this.duration = 3,
      this.font = 'Oswald',
      this.color = '#FFFFFF',
      this.anim = 'zoomIn',
      this.gradientTo,
      this.outlineColor,
      this.size = 110,
      this.vfx = const [],
      this.transition = 'fade',
      this.subtitle = ''});
}

const introPresets = <IntroPreset>[
  IntroPreset('cinema', 'Kinowe otwarcie', font: 'Oswald', color: '#F5E6C8', anim: 'fade', vfx: ['cinematic', 'godrays', 'tex_gold_dust'], transition: 'fadeblack', subtitle: 'presents'),
  IntroPreset('neon', 'Neon', background: '#05010F', font: 'Monoton', color: '#FF4FA3', anim: 'glow', outlineColor: '#35D0BA', vfx: ['frame_neon', 'tex_stars_white'], transition: 'circleopen'),
  IntroPreset('gold', 'Złote', background: '#120C02', font: 'Playfair Display', color: '#FFE08A', gradientTo: '#C8902A', anim: 'zoomIn', vfx: ['tex_gold_dust', 'lightburst', 'frame_gold']),
  IntroPreset('birthday', 'Urodziny', background: '#2A0A3D', font: 'Lobster', color: '#FFD400', anim: 'bounce', vfx: ['tex_confetti', 'tex_balloons'], subtitle: 'Wszystkiego najlepszego!'),
  IntroPreset('wedding', 'Ślub i miłość', background: '#FFF4F6', font: 'Playfair Display', color: '#B0244E', outlineColor: '#FFFFFF', anim: 'fade', vfx: ['tex_petals', 'tex_hearts_pink', 'frame_hearts'], transition: 'fadewhite'),
  IntroPreset('love', 'Serca', background: '#3A0010', font: 'Pacifico', color: '#FFFFFF', anim: 'zoomIn', vfx: ['tex_hearts_red', 'heartbeat'], transition: 'circleopen'),
  IntroPreset('summer', 'Wakacje', background: '#0B8FD6', font: 'Pacifico', color: '#FFF6C9', anim: 'slideUp', vfx: ['tex_bubbles', 'lights'], transition: 'wiperight'),
  IntroPreset('winter', 'Zima i święta', background: '#06213A', font: 'Playfair Display', color: '#FFFFFF', anim: 'fade', vfx: ['tex_snowflakes', 'snow', 'tex_sparkles'], subtitle: 'Wesołych Świąt'),
  IntroPreset('party', 'Impreza', background: '#000000', font: 'Bebas Neue', color: '#FFFFFF', anim: 'wordPop', vfx: ['strobe', 'zoompunch', 'tex_confetti'], transition: 'fadewhite', size: 140),
  IntroPreset('glitch', 'Glitch', background: '#000000', font: 'Rubik Glitch', color: '#FFFFFF', anim: 'typewriter', vfx: ['glitch', 'rgbsplit', 'speedlines'], transition: 'hblur'),
  IntroPreset('retro', 'Retro VHS', background: '#1A1020', font: 'Press Start 2P', color: '#FFD400', anim: 'typewriter', size: 70, vfx: ['vhs', 'frame_vhs'], transition: 'fade'),
  IntroPreset('anime', 'Anime', background: '#FFFFFF', font: 'Anton', color: '#111111', outlineColor: '#FFFFFF', anim: 'zoomIn', vfx: ['speedlines', 'shockwave', 'halftone'], transition: 'fadewhite', size: 130),
  IntroPreset('epic', 'Epickie', background: '#000000', font: 'Anton', color: '#FFFFFF', gradientTo: '#FF8C00', anim: 'zoomIn', vfx: ['lightning', 'fire', 'shake'], transition: 'fadeblack', size: 140),
  IntroPreset('nature', 'Natura', background: '', font: 'Caveat', color: '#FFFFFF', anim: 'fade', vfx: ['tex_butterflies', 'tex_fireflies', 'vignette']),
  IntroPreset('photo', 'Tytuł na zdjęciu', background: '', font: 'Noto Sans', color: '#FFFFFF', anim: 'slideUp', vfx: ['vignette', 'tex_bokeh']),
  IntroPreset('minimal', 'Minimalistyczne', background: '#FFFFFF', font: 'Noto Sans', color: '#111111', outlineColor: '#FFFFFF', anim: 'letterWave', vfx: [], transition: 'fade', size: 90),
];

IntroPreset introById(String id) => introPresets.firstWhere((e) => e.id == id, orElse: () => introPresets.first);

/// Marker used to find (and replace) a previously applied intro.
const introTag = 'intro';

/// Removes an intro previously added by [applyIntro].
void removeIntro(VideoProject p) {
  if (p.clips.isNotEmpty && p.clips.first.label == introTag) {
    final d = p.clips.first.duration - (p.clips.length > 1 ? p.effectiveTransition(0) : 0);
    p.clips.removeAt(0);
    // shift everything else back
    for (final o in p.overlays) {
      o.start = (o.start - d).clamp(0, double.infinity).toDouble();
    }
    for (final t in p.texts) {
      t.start = (t.start - d).clamp(0, double.infinity).toDouble();
    }
    for (final v in p.vfx) {
      v.start = (v.start - d).clamp(0, double.infinity).toDouble();
    }
    for (final tr in p.audio.tracks) {
      for (final c in tr.clips) {
        c.position = (c.position - d).clamp(0, double.infinity).toDouble();
      }
    }
  }
  p.texts.removeWhere((t) => t.layer == 90);
  p.vfx.removeWhere((v) => v.id.startsWith('intro_'));
}

/// Applies [preset] with [title] (and optional [subtitle]). When
/// [shiftContent] is true and the intro uses its own card, the rest of the
/// film (including music) starts after the card; otherwise the title is
/// laid over the first clip.
void applyIntro(VideoProject p, IntroPreset preset, String title, {String? subtitle, bool shiftContent = true}) {
  removeIntro(p);
  final ownCard = preset.background.isNotEmpty || p.clips.isEmpty;
  final d = preset.duration;
  double offset = 0;
  if (ownCard) {
    final card = VisualClip(kind: ClipKind.color, color: preset.background.isEmpty ? '#000000' : preset.background, imageDuration: d, transition: Transition(type: preset.transition, duration: 0.6))..label = introTag;
    p.clips.insert(0, card);
    if (shiftContent && p.clips.length > 1) {
      offset = d - p.effectiveTransition(0);
      for (final o in p.overlays) {
        o.start += offset;
      }
      for (final t in p.texts) {
        t.start += offset;
      }
      for (final v in p.vfx) {
        v.start += offset;
      }
      for (final tr in p.audio.tracks) {
        for (final c in tr.clips) {
          c.position += offset;
        }
      }
    }
  }
  final style = TextStyleSpec(
    font: preset.font,
    size: preset.size,
    color: preset.color,
    gradientTo: preset.gradientTo,
    outlineColor: preset.outlineColor ?? '#000000',
    outline: preset.outlineColor == null ? 3 : 5,
    shadow: 3,
    align: 'center',
  );
  p.texts.add(TextItem(text: title, start: 0.2, duration: d - 0.3, style: style, anim: preset.anim, animDur: 0.8, layer: 90));
  final sub = subtitle ?? preset.subtitle;
  if (sub.isNotEmpty) {
    p.texts.add(TextItem(
      text: sub,
      start: 0.7,
      duration: d - 0.8,
      x: 0.5,
      y: 0.62,
      style: style.copy()
        ..size = preset.size * 0.42
        ..gradientTo = null,
      anim: 'fade',
      animDur: 0.6,
      layer: 90,
    ));
  }
  var k = 0;
  for (final fx in preset.vfx) {
    p.vfx.add(VfxItem(id: 'intro_${k++}_$fx', type: fx, start: 0, duration: d, intensity: 0.75));
  }
}
