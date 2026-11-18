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
import 'package:wojan_media_studio/ui/preview/live_preview.dart';
import 'package:wojan_media_studio/ui/shell.dart';

/// Real end-to-end smoke test of the desktop app: every screen is built,
/// a music video project is generated from real media and opened, and the
/// real preview render is triggered from the UI.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final shots = Platform.environment['WMS_SHOTS'] ?? '/tmp/wms_shots';

  Future<void> shot(String name) async {
    // ignore: avoid_print
    print('STEP $name');
    await Directory(shots).create(recursive: true);
    await Process.run('import', ['-window', 'root', '$shots/$name.png']);
  }

  Future<void> closeSheet(WidgetTester t) async {
    // tap the dimmed area above the bottom sheet, like a user would
    await t.tapAt(const Offset(640, 30));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('all screens render; generated music video opens and previews', (t) async {
    // Clean, reproducible start: remove data left by earlier (interrupted)
    // runs on this machine – otherwise crash recovery would (rightly) ask
    // about their autosaves.
    final home = Platform.environment['HOME'];
    final data = Directory('$home/.local/share/pl.wojan.wojan_media_studio/WoJanMediaStudio');
    if (Platform.isLinux && data.existsSync()) data.deleteSync(recursive: true);
    await app.main([]);
    await t.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Nowy projekt'), findsOneWidget);
    final names = ['01_projekty', '02_studio_audio', '03_studio_wideo', '04_szybki_teledysk', '05_lyric_video', '06_karaoke', '07_wizualizator', '08_konwerter', '09_biblioteka', '10_szablony', '11_wsad', '12_kolejka', '13_publisher', '14_historia', '14b_moje_dzielo', '15_synchronizacja', '16_ustawienia'];
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
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('Teledysk z testu UI'), findsWidgets);
    expect(t.takeException(), isNull, reason: 'video studio layout');
    await shot('18_studio_wideo_projekt');
    // ---- real-time preview: Play advances the clock, frames are composed live
    expect(find.byType(LivePreview), findsOneWidget);
    final pcState = Services.i; // keep services alive
    expect(pcState, isNotNull);
    await t.tap(find.byTooltip('Odtwórz').hitTestable().first);
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
    await shot('19_podglad_na_zywo_play');
    final lp = t.widget<LivePreview>(find.byType(LivePreview));
    expect(lp.controller.playing, isTrue);
    expect(lp.controller.position, greaterThan(1.0), reason: 'clock advanced while playing');
    await shot('19b_przed_pauza');
    await t.tap(find.byTooltip('Pauza').hitTestable().first);
    await t.pump(const Duration(milliseconds: 300));
    expect(lp.controller.playing, isFalse);
    expect(t.takeException(), isNull, reason: 'live preview while playing');
    // ---- effect library sheet with animated thumbnails
    await t.tap(find.byKey(const Key('tool_fx')));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
    await shot('20_biblioteka_efektow');
    await t.tap(find.byKey(const Key('fx_tex_hearts_red')));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.widget<LivePreview>(find.byType(LivePreview)).controller.project.vfx.any((v) => v.type == 'tex_hearts_red'), isTrue);
    await t.tap(find.text('Uderzenie'));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
    await shot('21_efekty_uderzenie');
    await t.tap(find.byKey(const Key('fx_zoompunch')));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull, reason: 'effects sheet');
    await closeSheet(t);
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.byTooltip('Odtwórz').hitTestable().first);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
    await shot('22_podglad_serca_zoom');
    await t.tap(find.byTooltip('Pauza').hitTestable().first);
    await t.pump(const Duration(milliseconds: 300));
    // ---- intro
    await t.tap(find.byKey(const Key('tool_intro')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
    await shot('23_wstepy');
    await t.tap(find.byKey(const Key('intro_birthday')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
    expect(t.widget<LivePreview>(find.byType(LivePreview)).controller.project.clips.first.label, 'intro');
    await closeSheet(t);
    await t.pump(const Duration(milliseconds: 500));
    await shot('24_wstep_odtwarzany');
    await t.tap(find.byTooltip('Pauza').hitTestable().first);
    await t.pump(const Duration(milliseconds: 300));
    // ---- every toolbar tool opens without layout errors
    for (final k in ['tool_edit', 'tool_music', 'tool_frame', 'tool_text', 'tool_sticker', 'tool_ratio', 'tool_bg', 'tool_filter', 'tool_adjust', 'tool_transition', 'tool_vis', 'tool_subs', 'tool_layers']) {
      await t.ensureVisible(find.byKey(Key(k)));
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.byKey(Key(k)));
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 120));
      }
      expect(t.takeException(), isNull, reason: k);
      await shot('25_$k');
      await closeSheet(t);
      await t.pump(const Duration(milliseconds: 400));
    }
    // ---- exact (engine) preview still available
    await t.tap(find.text('Dokładny podgląd').first);
    for (var i = 0; i < 600; i++) {
      await t.pump(const Duration(milliseconds: 500));
      if (find.text('Zamknij').evaluate().isNotEmpty && find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
    }
    await t.pump(const Duration(seconds: 2));
    final previews = Directory(s.store.cacheDir.path).listSync().whereType<File>().where((f) => f.path.contains('preview_${d.id}')).toList();
    expect(previews, isNotEmpty, reason: 'exact preview rendered from UI');
    await shot('26_dokladny_podglad');
    await t.tap(find.text('Zamknij').first);
    await t.pump(const Duration(milliseconds: 500));
    expect(t.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 15)));
}
