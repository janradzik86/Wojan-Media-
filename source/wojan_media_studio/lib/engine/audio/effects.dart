import 'dart:math' as math;

import '../ffmpeg/escape.dart';
import '../util/json_util.dart';

/// Every supported audio effect type. Each maps to real FFmpeg filters.
enum AudioFx {
  volume,
  equalizer,
  bassBoost,
  trebleBoost,
  highpass,
  lowpass,
  compressor,
  limiter,
  gate,
  loudnorm,
  dynamicNormalize,
  noiseReduction,
  deesser,
  echo,
  delay,
  reverb,
  chorus,
  flanger,
  phaser,
  tremolo,
  vibrato,
  balance,
  stereoWidth,
  mono,
  swapChannels,
  tempo,
  pitch,
  speed,
  reverse,
  silenceRemove,
  vocalRemove,
  vocalIsolate,
  telephone,
  bitcrush,
}

class FxParamDef {
  final String key;
  final String labelPl;
  final String labelEn;
  final double min, max, def;
  final String unit;
  const FxParamDef(this.key, this.labelPl, this.labelEn, this.min, this.max, this.def, [this.unit = '']);
}

class FxDef {
  final AudioFx type;
  final String namePl, nameEn;
  final List<FxParamDef> params;
  const FxDef(this.type, this.namePl, this.nameEn, this.params);
}

const fxDefs = <AudioFx, FxDef>{
  AudioFx.volume: FxDef(AudioFx.volume, 'Głośność', 'Volume', [FxParamDef('gain', 'Wzmocnienie', 'Gain', -40, 24, 0, 'dB')]),
  AudioFx.equalizer: FxDef(AudioFx.equalizer, 'Korektor 10-pasmowy', '10-band equalizer', [
    FxParamDef('b31', '31 Hz', '31 Hz', -18, 18, 0, 'dB'),
    FxParamDef('b62', '62 Hz', '62 Hz', -18, 18, 0, 'dB'),
    FxParamDef('b125', '125 Hz', '125 Hz', -18, 18, 0, 'dB'),
    FxParamDef('b250', '250 Hz', '250 Hz', -18, 18, 0, 'dB'),
    FxParamDef('b500', '500 Hz', '500 Hz', -18, 18, 0, 'dB'),
    FxParamDef('b1k', '1 kHz', '1 kHz', -18, 18, 0, 'dB'),
    FxParamDef('b2k', '2 kHz', '2 kHz', -18, 18, 0, 'dB'),
    FxParamDef('b4k', '4 kHz', '4 kHz', -18, 18, 0, 'dB'),
    FxParamDef('b8k', '8 kHz', '8 kHz', -18, 18, 0, 'dB'),
    FxParamDef('b16k', '16 kHz', '16 kHz', -18, 18, 0, 'dB'),
  ]),
  AudioFx.bassBoost: FxDef(AudioFx.bassBoost, 'Wzmocnienie basu', 'Bass boost', [
    FxParamDef('gain', 'Wzmocnienie', 'Gain', -20, 20, 6, 'dB'),
    FxParamDef('freq', 'Częstotliwość', 'Frequency', 40, 250, 100, 'Hz'),
  ]),
  AudioFx.trebleBoost: FxDef(AudioFx.trebleBoost, 'Wzmocnienie sopranów', 'Treble boost', [
    FxParamDef('gain', 'Wzmocnienie', 'Gain', -20, 20, 5, 'dB'),
    FxParamDef('freq', 'Częstotliwość', 'Frequency', 1500, 12000, 4000, 'Hz'),
  ]),
  AudioFx.highpass: FxDef(AudioFx.highpass, 'Filtr górnoprzepustowy', 'High-pass', [FxParamDef('freq', 'Częstotliwość', 'Frequency', 20, 2000, 80, 'Hz')]),
  AudioFx.lowpass: FxDef(AudioFx.lowpass, 'Filtr dolnoprzepustowy', 'Low-pass', [FxParamDef('freq', 'Częstotliwość', 'Frequency', 500, 20000, 8000, 'Hz')]),
  AudioFx.compressor: FxDef(AudioFx.compressor, 'Kompresor', 'Compressor', [
    FxParamDef('threshold', 'Próg', 'Threshold', -60, 0, -18, 'dB'),
    FxParamDef('ratio', 'Stosunek', 'Ratio', 1, 20, 4, ':1'),
    FxParamDef('attack', 'Atak', 'Attack', 0.1, 200, 20, 'ms'),
    FxParamDef('release', 'Zwolnienie', 'Release', 10, 2000, 250, 'ms'),
    FxParamDef('makeup', 'Wzmocnienie', 'Make-up', 0, 24, 2, 'dB'),
  ]),
  AudioFx.limiter: FxDef(AudioFx.limiter, 'Limiter', 'Limiter', [FxParamDef('ceiling', 'Pułap', 'Ceiling', -12, 0, -1, 'dB')]),
  AudioFx.gate: FxDef(AudioFx.gate, 'Bramka szumów', 'Noise gate', [FxParamDef('threshold', 'Próg', 'Threshold', -80, -10, -45, 'dB')]),
  AudioFx.loudnorm: FxDef(AudioFx.loudnorm, 'Normalizacja LUFS', 'LUFS normalisation', [
    FxParamDef('lufs', 'Głośność docelowa', 'Target loudness', -30, -5, -14, 'LUFS'),
    FxParamDef('tp', 'True peak', 'True peak', -9, 0, -1, 'dBTP'),
  ]),
  AudioFx.dynamicNormalize: FxDef(AudioFx.dynamicNormalize, 'Normalizacja dynamiczna', 'Dynamic normalisation', [FxParamDef('strength', 'Siła', 'Strength', 1, 30, 10)]),
  AudioFx.noiseReduction: FxDef(AudioFx.noiseReduction, 'Redukcja szumów', 'Noise reduction', [
    FxParamDef('amount', 'Redukcja', 'Reduction', 1, 60, 15, 'dB'),
    FxParamDef('floor', 'Poziom szumu', 'Noise floor', -80, -20, -50, 'dB'),
  ]),
  AudioFx.deesser: FxDef(AudioFx.deesser, 'De-esser', 'De-esser', [FxParamDef('intensity', 'Intensywność', 'Intensity', 0, 1, 0.5)]),
  AudioFx.echo: FxDef(AudioFx.echo, 'Echo', 'Echo', [
    FxParamDef('delay', 'Opóźnienie', 'Delay', 20, 2000, 400, 'ms'),
    FxParamDef('decay', 'Wygasanie', 'Decay', 0.05, 0.95, 0.4),
  ]),
  AudioFx.delay: FxDef(AudioFx.delay, 'Delay (wielokrotny)', 'Multi-tap delay', [
    FxParamDef('delay', 'Opóźnienie', 'Delay', 20, 2000, 300, 'ms'),
    FxParamDef('feedback', 'Sprzężenie', 'Feedback', 0.05, 0.9, 0.45),
    FxParamDef('mix', 'Miks', 'Mix', 0, 1, 0.4),
  ]),
  AudioFx.reverb: FxDef(AudioFx.reverb, 'Pogłos', 'Reverb', [
    FxParamDef('room', 'Wielkość pomieszczenia', 'Room size', 0.05, 1, 0.5),
    FxParamDef('wet', 'Poziom pogłosu', 'Wet', 0, 1, 0.3),
    FxParamDef('damp', 'Tłumienie', 'Damping', 0, 1, 0.4),
  ]),
  AudioFx.chorus: FxDef(AudioFx.chorus, 'Chorus', 'Chorus', [FxParamDef('depth', 'Głębokość', 'Depth', 0.5, 10, 2)]),
  AudioFx.flanger: FxDef(AudioFx.flanger, 'Flanger', 'Flanger', [FxParamDef('depth', 'Głębokość', 'Depth', 0, 10, 2), FxParamDef('speed', 'Prędkość', 'Speed', 0.1, 10, 0.5, 'Hz')]),
  AudioFx.phaser: FxDef(AudioFx.phaser, 'Phaser', 'Phaser', [FxParamDef('speed', 'Prędkość', 'Speed', 0.1, 2, 0.5, 'Hz')]),
  AudioFx.tremolo: FxDef(AudioFx.tremolo, 'Tremolo', 'Tremolo', [FxParamDef('freq', 'Częstotliwość', 'Frequency', 0.5, 20, 5, 'Hz'), FxParamDef('depth', 'Głębokość', 'Depth', 0, 1, 0.5)]),
  AudioFx.vibrato: FxDef(AudioFx.vibrato, 'Vibrato', 'Vibrato', [FxParamDef('freq', 'Częstotliwość', 'Frequency', 0.5, 20, 5, 'Hz'), FxParamDef('depth', 'Głębokość', 'Depth', 0, 1, 0.5)]),
  AudioFx.balance: FxDef(AudioFx.balance, 'Balans stereo', 'Stereo balance', [FxParamDef('balance', 'Balans (L–P)', 'Balance (L–R)', -1, 1, 0)]),
  AudioFx.stereoWidth: FxDef(AudioFx.stereoWidth, 'Szerokość stereo', 'Stereo width', [FxParamDef('width', 'Szerokość', 'Width', 0, 3, 1.5)]),
  AudioFx.mono: FxDef(AudioFx.mono, 'Konwersja do mono', 'Convert to mono', []),
  AudioFx.swapChannels: FxDef(AudioFx.swapChannels, 'Zamiana kanałów L/P', 'Swap L/R', []),
  AudioFx.tempo: FxDef(AudioFx.tempo, 'Tempo (bez zmiany tonu)', 'Tempo (keep pitch)', [FxParamDef('factor', 'Mnożnik', 'Factor', 0.25, 4, 1, '×')]),
  AudioFx.pitch: FxDef(AudioFx.pitch, 'Wysokość tonu (bez zmiany tempa)', 'Pitch (keep tempo)', [FxParamDef('semitones', 'Półtony', 'Semitones', -12, 12, 0, 'st')]),
  AudioFx.speed: FxDef(AudioFx.speed, 'Prędkość (ton + tempo)', 'Speed (pitch + tempo)', [FxParamDef('factor', 'Mnożnik', 'Factor', 0.25, 4, 1, '×')]),
  AudioFx.reverse: FxDef(AudioFx.reverse, 'Odwrócenie', 'Reverse', []),
  AudioFx.silenceRemove: FxDef(AudioFx.silenceRemove, 'Usuwanie ciszy', 'Remove silence', [
    FxParamDef('threshold', 'Próg', 'Threshold', -80, -20, -45, 'dB'),
    FxParamDef('minDur', 'Min. długość ciszy', 'Min silence', 0.1, 5, 0.6, 's'),
  ]),
  AudioFx.vocalRemove: FxDef(AudioFx.vocalRemove, 'Usuwanie wokalu (DSP, przybliżone)', 'Vocal removal (DSP approx.)', [FxParamDef('bassKeep', 'Zachowaj bas do', 'Keep bass below', 50, 400, 180, 'Hz')]),
  AudioFx.vocalIsolate: FxDef(AudioFx.vocalIsolate, 'Wydzielenie środka/wokalu (DSP, przybliżone)', 'Centre/vocal isolate (DSP approx.)', []),
  AudioFx.telephone: FxDef(AudioFx.telephone, 'Efekt telefonu/radia', 'Telephone/radio', []),
  AudioFx.bitcrush: FxDef(AudioFx.bitcrush, 'Lo-fi (bitcrusher)', 'Lo-fi (bitcrusher)', [FxParamDef('bits', 'Bity', 'Bits', 2, 16, 8)]),
};

/// A configured effect instance.
class AudioEffect {
  final AudioFx type;
  final Map<String, double> params;
  bool enabled;
  AudioEffect(this.type, [Map<String, double>? params, this.enabled = true])
      : params = {
          for (final p in fxDefs[type]!.params) p.key: p.def,
          ...?params,
        };

  double p(String k) {
    final d = fxDefs[type]!.params.firstWhere((e) => e.key == k);
    return clampD(params[k] ?? d.def, d.min, d.max);
  }

  AudioEffect copy() => AudioEffect(type, Map.of(params), enabled);

  Map<String, dynamic> toJson() => {'type': type.name, 'params': params, 'enabled': enabled};
  factory AudioEffect.fromJson(Map<String, dynamic> j) {
    final t = AudioFx.values.firstWhere((e) => e.name == j['type'], orElse: () => AudioFx.volume);
    return AudioEffect(t, jm(j['params']).map((k, v) => MapEntry(k, jd(v))), jb(j['enabled'], true));
  }
}

String dbToLin(double db) => FfEscape.num(math.pow(10, db / 20).toDouble());

/// atempo accepts 0.5..2 (100 in newer builds); chain for wider ranges.
List<String> atempoChain(double f) {
  final out = <String>[];
  var r = f;
  while (r > 2.0) {
    out.add('atempo=2.0');
    r /= 2.0;
  }
  while (r < 0.5) {
    out.add('atempo=0.5');
    r /= 0.5;
  }
  if ((r - 1).abs() > 1e-4) out.add('atempo=${FfEscape.num(r)}');
  return out;
}

/// Context needed by a few effects (reverb impulse response inputs).
class FxContext {
  final int sampleRate;
  /// Callback registering an auxiliary input file and returning its stream
  /// label (e.g. `[5:a]`). Used by convolution reverb.
  final String Function(String path) addAuxInput;
  /// Generates (or reuses) an impulse response WAV for the parameters.
  final String Function(double room, double damp) impulseResponse;
  int _uid = 0;
  FxContext({required this.sampleRate, required this.addAuxInput, required this.impulseResponse});
  String uid(String p) => '${p}_${_uid++}';
}

/// Compiles one effect into a filter chain fragment operating on [inLabel]
/// and producing [outLabel]. Returns graph text (may contain several chains).
String compileEffect(AudioEffect fx, String inLabel, String outLabel, FxContext ctx) {
  String simple(List<String> f) => f.isEmpty ? '[$inLabel]anull[$outLabel]' : '[$inLabel]${f.join(',')}[$outLabel]';
  final sr = ctx.sampleRate;
  switch (fx.type) {
    case AudioFx.volume:
      return simple(['volume=${FfEscape.num(fx.p('gain'))}dB']);
    case AudioFx.equalizer:
      const freqs = {'b31': 31, 'b62': 62, 'b125': 125, 'b250': 250, 'b500': 500, 'b1k': 1000, 'b2k': 2000, 'b4k': 4000, 'b8k': 8000, 'b16k': 16000};
      final f = <String>[];
      freqs.forEach((k, hz) {
        final g = fx.p(k);
        if (g.abs() > 0.05) f.add('equalizer=f=$hz:t=o:w=1:g=${FfEscape.num(g)}');
      });
      return simple(f);
    case AudioFx.bassBoost:
      return simple(['bass=g=${FfEscape.num(fx.p('gain'))}:f=${FfEscape.num(fx.p('freq'))}:w=0.6']);
    case AudioFx.trebleBoost:
      return simple(['treble=g=${FfEscape.num(fx.p('gain'))}:f=${FfEscape.num(fx.p('freq'))}:w=0.6']);
    case AudioFx.highpass:
      return simple(['highpass=f=${FfEscape.num(fx.p('freq'))}']);
    case AudioFx.lowpass:
      return simple(['lowpass=f=${FfEscape.num(fx.p('freq'))}']);
    case AudioFx.compressor:
      return simple([
        'acompressor=threshold=${dbToLin(fx.p('threshold'))}:ratio=${FfEscape.num(fx.p('ratio'))}:attack=${FfEscape.num(fx.p('attack'))}:release=${FfEscape.num(fx.p('release'))}:makeup=${dbToLin(fx.p('makeup'))}'
      ]);
    case AudioFx.limiter:
      return simple(['alimiter=limit=${dbToLin(fx.p('ceiling'))}:level=disabled']);
    case AudioFx.gate:
      return simple(['agate=threshold=${dbToLin(fx.p('threshold'))}:ratio=4']);
    case AudioFx.loudnorm:
      return simple(['loudnorm=I=${FfEscape.num(fx.p('lufs'))}:TP=${FfEscape.num(fx.p('tp'))}:LRA=11', 'aresample=$sr']);
    case AudioFx.dynamicNormalize:
      return simple(['dynaudnorm=f=250:g=${(fx.p('strength') * 2 + 1).round() | 1}']);
    case AudioFx.noiseReduction:
      return simple(['afftdn=nr=${FfEscape.num(fx.p('amount'))}:nf=${FfEscape.num(fx.p('floor'))}']);
    case AudioFx.deesser:
      return simple(['deesser=i=${FfEscape.num(fx.p('intensity'))}']);
    case AudioFx.echo:
      return simple(['aecho=0.8:0.9:${FfEscape.num(fx.p('delay'))}:${FfEscape.num(fx.p('decay'))}']);
    case AudioFx.delay:
      final d = fx.p('delay'), fb = fx.p('feedback'), mix = fx.p('mix');
      final taps = <String>[], decays = <String>[];
      var g = mix;
      for (var i = 1; i <= 5 && g > 0.01; i++) {
        taps.add(FfEscape.num(d * i));
        decays.add(FfEscape.num(g));
        g *= fb;
      }
      return simple(['aecho=1:1:${taps.join('|')}:${decays.join('|')}']);
    case AudioFx.reverb:
      final ir = ctx.impulseResponse(fx.p('room'), fx.p('damp'));
      final irLabel = ctx.addAuxInput(ir);
      final a = ctx.uid('rvd'), b = ctx.uid('rvw'), c = ctx.uid('rvo'), ir2 = ctx.uid('rvir');
      final wet = fx.p('wet');
      return '[$inLabel]asplit=2[$a][$b];'
          '${irLabel}aformat=sample_fmts=fltp:sample_rates=$sr:channel_layouts=stereo[$ir2];'
          '[$b][$ir2]afir=dry=10:wet=10[$c];'
          '[$a][$c]amix=inputs=2:weights=${FfEscape.num(1 - wet * 0.5)} ${FfEscape.num(wet)}:normalize=0[$outLabel]';
    case AudioFx.chorus:
      final dp = fx.p('depth');
      return simple(['chorus=0.6:0.9:50|60:0.4|0.32:0.25|0.4:${FfEscape.num(dp)}|${FfEscape.num(dp * 1.3)}']);
    case AudioFx.flanger:
      return simple(['flanger=depth=${FfEscape.num(fx.p('depth'))}:speed=${FfEscape.num(fx.p('speed'))}']);
    case AudioFx.phaser:
      return simple(['aphaser=speed=${FfEscape.num(fx.p('speed'))}']);
    case AudioFx.tremolo:
      return simple(['tremolo=f=${FfEscape.num(fx.p('freq'))}:d=${FfEscape.num(fx.p('depth'), min: 0.01, max: 1)}']);
    case AudioFx.vibrato:
      return simple(['vibrato=f=${FfEscape.num(fx.p('freq'))}:d=${FfEscape.num(fx.p('depth'), min: 0.01, max: 1)}']);
    case AudioFx.balance:
      final b = fx.p('balance');
      final l = b > 0 ? 1 - b : 1.0, r = b < 0 ? 1 + b : 1.0;
      return simple(['pan=stereo|c0=${FfEscape.num(l)}*c0|c1=${FfEscape.num(r)}*c1']);
    case AudioFx.stereoWidth:
      return simple(['extrastereo=m=${FfEscape.num(fx.p('width'))}']);
    case AudioFx.mono:
      return simple(['pan=mono|c0=0.5*c0+0.5*c1', 'aformat=channel_layouts=stereo']);
    case AudioFx.swapChannels:
      return simple(['pan=stereo|c0=c1|c1=c0']);
    case AudioFx.tempo:
      return simple(atempoChain(fx.p('factor')));
    case AudioFx.pitch:
      final r = math.pow(2, fx.p('semitones') / 12).toDouble();
      if ((r - 1).abs() < 1e-4) return simple([]);
      return simple(['asetrate=${(sr * r).round()}', 'aresample=$sr', ...atempoChain(1 / r)]);
    case AudioFx.speed:
      final f = fx.p('factor');
      if ((f - 1).abs() < 1e-4) return simple([]);
      return simple(['asetrate=${(sr * f).round()}', 'aresample=$sr']);
    case AudioFx.reverse:
      return simple(['areverse']);
    case AudioFx.silenceRemove:
      return simple([
        'silenceremove=start_periods=1:start_threshold=${FfEscape.num(fx.p('threshold'))}dB:stop_periods=-1:stop_duration=${FfEscape.num(fx.p('minDur'))}:stop_threshold=${FfEscape.num(fx.p('threshold'))}dB'
      ]);
    case AudioFx.vocalRemove:
      final a = ctx.uid('vra'), b = ctx.uid('vrb'), lo = ctx.uid('vrl'), side = ctx.uid('vrs');
      final keep = FfEscape.num(fx.p('bassKeep'));
      return '[$inLabel]asplit=2[$a][$b];'
          '[$a]lowpass=f=$keep,pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1[$lo];'
          '[$b]pan=stereo|c0=c0-c1|c1=c1-c0,highpass=f=$keep[$side];'
          '[$lo][$side]amix=inputs=2:normalize=0[$outLabel]';
    case AudioFx.vocalIsolate:
      return simple(['pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1', 'highpass=f=150', 'lowpass=f=7000']);
    case AudioFx.telephone:
      return simple(['highpass=f=400', 'lowpass=f=3200', 'acompressor=threshold=0.1:ratio=6', 'volume=3dB']);
    case AudioFx.bitcrush:
      return simple(['acrusher=bits=${FfEscape.num(fx.p('bits'))}:mode=log:aa=1']);
  }
}

/// Factory presets (editable copies are created when applied).
class FxPreset {
  final String id, namePl, nameEn;
  final List<AudioEffect> Function() build;
  const FxPreset(this.id, this.namePl, this.nameEn, this.build);
}

final factoryFxPresets = <FxPreset>[
  FxPreset('podcast', 'Podcast / mowa', 'Podcast / speech', () => [
        AudioEffect(AudioFx.highpass, {'freq': 80}),
        AudioEffect(AudioFx.noiseReduction, {'amount': 12}),
        AudioEffect(AudioFx.compressor, {'threshold': -20, 'ratio': 3}),
        AudioEffect(AudioFx.deesser),
        AudioEffect(AudioFx.loudnorm, {'lufs': -16}),
      ]),
  FxPreset('bass_heavy', 'Mocny bas', 'Bass heavy', () => [AudioEffect(AudioFx.bassBoost, {'gain': 9}), AudioEffect(AudioFx.limiter)]),
  FxPreset('bright', 'Jasne brzmienie', 'Bright', () => [AudioEffect(AudioFx.trebleBoost, {'gain': 6}), AudioEffect(AudioFx.limiter)]),
  FxPreset('hall', 'Duża sala', 'Concert hall', () => [AudioEffect(AudioFx.reverb, {'room': 0.85, 'wet': 0.35})]),
  FxPreset('room', 'Mały pokój', 'Small room', () => [AudioEffect(AudioFx.reverb, {'room': 0.25, 'wet': 0.2})]),
  FxPreset('radio', 'Stare radio', 'Old radio', () => [AudioEffect(AudioFx.telephone), AudioEffect(AudioFx.bitcrush, {'bits': 10})]),
  FxPreset('karaoke', 'Karaoke (bez wokalu)', 'Karaoke (no vocals)', () => [AudioEffect(AudioFx.vocalRemove)]),
  FxPreset('master_stream', 'Mastering: streaming -14 LUFS', 'Mastering: streaming -14 LUFS', () => [
        AudioEffect(AudioFx.highpass, {'freq': 30}),
        AudioEffect(AudioFx.compressor, {'threshold': -16, 'ratio': 2.5, 'attack': 25, 'release': 200, 'makeup': 1}),
        AudioEffect(AudioFx.equalizer, {'b62': 1.5, 'b8k': 1.5, 'b16k': 1}),
        AudioEffect(AudioFx.loudnorm, {'lufs': -14, 'tp': -1}),
        AudioEffect(AudioFx.limiter, {'ceiling': -1}),
      ]),
  FxPreset('master_loud', 'Mastering: głośny klub -9 LUFS', 'Mastering: loud club -9 LUFS', () => [
        AudioEffect(AudioFx.compressor, {'threshold': -14, 'ratio': 4, 'makeup': 3}),
        AudioEffect(AudioFx.bassBoost, {'gain': 3}),
        AudioEffect(AudioFx.loudnorm, {'lufs': -9, 'tp': -0.5}),
        AudioEffect(AudioFx.limiter, {'ceiling': -0.5}),
      ]),
  FxPreset('nightcore', 'Nightcore', 'Nightcore', () => [AudioEffect(AudioFx.speed, {'factor': 1.25})]),
  FxPreset('slowed_reverb', 'Slowed + reverb', 'Slowed + reverb', () => [AudioEffect(AudioFx.speed, {'factor': 0.85}), AudioEffect(AudioFx.reverb, {'room': 0.7, 'wet': 0.35})]),
];
