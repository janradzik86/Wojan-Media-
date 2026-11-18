import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wojan_media_studio/app/services.dart';
import 'package:wojan_media_studio/engine/ffmpeg/runner.dart';
import 'package:wojan_media_studio/engine/musicvideo/auto.dart';
import 'package:wojan_media_studio/engine/musicvideo/styles.dart';
import 'package:wojan_media_studio/engine/project/format.dart';
import 'package:wojan_media_studio/main.dart' as app;
import 'package:wojan_media_studio/ui/shell.dart';

/// Real end-to-end smoke test of the desktop app: every screen is built,
/// a music video project is generated from real media and opened, and the
/// real preview render is triggered from the UI.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final shots = Platform.environment['WMS_SHOTS'] ?? '/tmp/wms_shots';

  Future<void> shot(String name) async {
    await Directory(shots).create(recursive: true);
    await Process.run('import', ['-window', 'root', '$shots/$name.png']);
  }

  testWidgets('all screens render; generated music video opens and previews', (t) async {
    await app.main([]);
    await t.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Nowy projekt'), findsOneWidget);
    final names = ['01_projekty', '02_studio_audio', '03_studio_wideo', '04_szybki_teledysk', '05_lyric_video', '06_karaoke', '07_wizualizator', '08_konwerter', '09_biblioteka', '10_szablony', '11_wsad', '12_kolejka', '13_publisher', '14_historia', '15_synchronizacja', '16_ustawienia'];
    for (var i = 0; i < names.length; i++) {
      Nav.index.value = i;
      await t.pumpAndSettle(const Duration(milliseconds: 600));
      expect(t.takeException(), isNull, reason: names[i]);
      await shot(names[i]);
    }
    // ---- real media → generated project
    final r = ProcessRunner();
    final dir = await Directory.systemTemp.createTemp('wms_it_');
    final song = '${dir.path}/piosenka.mp3', img1 = '${dir.path}/zdjecie1.jpg', img2 = '${dir.path}/zdjecie2.jpg';
    await r.run(['-f', 'lavfi', '-i', "aevalsrc='if(lt(mod(t,0.5),0.06),sin(2*PI*60*t)*0.9,0)+0.2*sin(2*PI*330*t)':s=44100:d=12", '-ac', '2', song]);
    await r.run(['-f', 'lavfi', '-i', 'testsrc2=s=1600x1200:d=1', '-frames:v', '1', img1]);
    await r.run(['-f', 'lavfi', '-i', 'mandelbrot=s=1200x1600', '-frames:v', '1', img2]);
    final s = Services.i;
    final m = await s.store.importMedia(song);
    final a1 = await s.store.importMedia(img1);
    final a2 = await s.store.importMedia(img2);
    final an = await s.analyze(s.store.mediaPath(m.relPath), m.sha256);
    expect(an.bpm, closeTo(120, 2));
    final v = MusicVideoGenerator().generate(MusicVideoRequest(music: m, visuals: [a1, a2], style: styleById('neon'), mode: MusicVideoMode.beatSync, title: 'Test UI', artist: 'WoJan', lyrics: 'Pierwszy wers\nDrugi wers – żółć'), an);
    final d = await s.store.create('Teledysk z testu UI', ProjectType.musicVideo);
    d.video = v;
    d.assets.addAll({m.id: m, a1.id: a1, a2.id: a2});
    await s.store.save(d);
    await s.store.makeThumbnail(d);
    Nav.index.value = 0;
    await t.pumpAndSettle(const Duration(seconds: 1));
    await shot('17_projekty_z_teledyskiem');
    Nav.openProject(d);
    await t.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Teledysk z testu UI'), findsWidgets);
    expect(t.takeException(), isNull, reason: 'video studio layout');
    await shot('18_studio_wideo_projekt');
    await t.tap(find.text('Podgląd').first);
    for (var i = 0; i < 240; i++) {
      await t.pump(const Duration(milliseconds: 500));
      final files = Directory(s.store.cacheDir.path).listSync().whereType<File>().where((f) => f.path.contains('preview_${d.id}') && f.lengthSync() > 1000);
      if (files.isNotEmpty && find.textContaining('Podgląd ').evaluate().isEmpty) break;
    }
    await t.pump(const Duration(seconds: 2));
    final previews = Directory(s.store.cacheDir.path).listSync().whereType<File>().where((f) => f.path.contains('preview_${d.id}')).toList();
    expect(previews, isNotEmpty, reason: 'real preview rendered from UI');
    expect(t.takeException(), isNull, reason: 'preview layout');
    await shot('19_podglad_wygenerowany');
    // select first clip → inspector
    await t.tap(find.byType(GestureDetector).at(0), warnIfMissed: false);
    await t.pumpAndSettle(const Duration(milliseconds: 500));
    expect(t.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 15)));
}
