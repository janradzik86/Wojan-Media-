import 'dart:io';

import 'package:wojan_media_studio/engine/ffmpeg/runner.dart';

/// Synthetic, license-free test media generated with FFmpeg sources.
class TestMedia {
  static final runner = ProcessRunner();
  static late Directory dir;

  static Future<Directory> init() async {
    dir = await Directory.systemTemp.createTemp('wms_test_');
    return dir;
  }

  /// Kick-drum-like click track at [bpm] mixed with a tone, [secs] long, mp3.
  static Future<String> clickTrack(double bpm, double secs, {String ext = 'mp3'}) async {
    final p = '${dir.path}/click_${bpm.round()}.$ext';
    final period = 60 / bpm;
    final expr = 'if(lt(mod(t,$period),0.06), sin(2*PI*60*t)*exp(-mod(t,$period)*40)*0.9, 0) + 0.15*sin(2*PI*440*t)';
    await runner.run(['-f', 'lavfi', '-i', "aevalsrc='$expr':s=44100:d=$secs", '-ac', '2', '-b:a', '192k', p]);
    return p;
  }

  static Future<String> tone(double freq, double secs, {String name = 'tone', String ext = 'wav', double vol = 0.5}) async {
    final p = '${dir.path}/${name}_${freq.round()}.$ext';
    await runner.run(['-f', 'lavfi', '-i', 'sine=frequency=$freq:sample_rate=44100:duration=$secs', '-af', 'volume=$vol', '-ac', '2', p]);
    return p;
  }

  static Future<String> image(String name, String color, {int w = 1600, int h = 1200}) async {
    final p = '${dir.path}/$name.jpg';
    await runner.run(['-f', 'lavfi', '-i', 'testsrc2=s=${w}x$h:d=1', '-vf', 'drawbox=x=0:y=0:w=iw/3:h=ih:color=$color@0.7:t=fill', '-frames:v', '1', p]);
    return p;
  }

  static Future<String> video(String name, double secs, {int w = 1280, int h = 720}) async {
    final p = '${dir.path}/$name.mp4';
    await runner.run(['-f', 'lavfi', '-i', 'testsrc=s=${w}x$h:r=30:d=$secs', '-f', 'lavfi', '-i', 'sine=frequency=330:duration=$secs',
      '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', p]);
    return p;
  }
}
