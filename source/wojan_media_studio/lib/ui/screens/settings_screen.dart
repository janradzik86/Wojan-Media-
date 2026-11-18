import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../engine/update/updater.dart';
import '../../engine/util/json_util.dart';
import '../../platform/native.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String updateStatus = '';

  Future<void> _checkUpdate() async {
    final url = Services.i.settings.get<String>('updateUrl');
    if (url.isEmpty || updatePublicKeyB64 == 'REPLACED_AT_BUILD') {
      setState(() => updateStatus = 'Kanał aktualizacji nie jest skonfigurowany w tej kompilacji (adres manifestu / klucz publiczny).');
      return;
    }
    final up = Updater(manifestUrl: url, publicKey: base64Decode(updatePublicKeyB64));
    try {
      final info = await up.check(appVersion);
      if (info == null) {
        setState(() => updateStatus = 'Masz najnowszą wersję ($appVersion).');
        return;
      }
      setState(() => updateStatus = 'Dostępna wersja ${info.version}: ${info.notes}');
      final asset = Platform.isWindows ? info.windows : Platform.isAndroid ? info.android : null;
      if (asset == null || !mounted) return;
      if (!await confirm(context, 'Aktualizacja ${info.version}', '${info.notes}\n\nPobrać i zainstalować? Projekty i ustawienia zostaną zachowane.')) return;
      final f = await runBusy(context, 'Pobieranie i weryfikacja SHA-256…', () => up.download(asset, '${Services.i.store.cacheDir.path}/update/${asset.url.split('/').last}'));
      if (f == null) return;
      if (Platform.isWindows) {
        await Process.start(f.path, ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'], mode: ProcessStartMode.detached);
        exit(0);
      } else if (Platform.isAndroid) {
        await NativeBridge.installApk(f.path);
      }
    } catch (e) {
      setState(() => updateStatus = 'Błąd aktualizacji: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = Services.i.settings;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Section(title: 'Wygląd i język', children: [
        Row(children: [
          const Text('Język: '),
          SegmentedButton<String>(segments: const [ButtonSegment(value: 'pl', label: Text('Polski')), ButtonSegment(value: 'en', label: Text('English'))], selected: {st.get<String>('lang')}, onSelectionChanged: (v) => st.set('lang', v.first)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Text('Motyw: '),
          SegmentedButton<String>(segments: const [ButtonSegment(value: 'dark', label: Text('Ciemny')), ButtonSegment(value: 'light', label: Text('Jasny'))], selected: {st.get<String>('theme')}, onSelectionChanged: (v) => st.set('theme', v.first)),
        ]),
        SwitchListTile(value: st.get<bool>('proMode'), onChanged: (v) => setState(() => st.set('proMode', v)), title: Text(st.get<bool>('proMode') ? tr('pro_mode') : tr('simple_mode')), subtitle: const Text('Tryb profesjonalny pokazuje produkcję wsadową i zaawansowane opcje')),
      ]),
      Section(title: 'Wydajność', children: [
        SegmentedButton<String>(segments: const [ButtonSegment(value: 'performance', label: Text('Wydajność')), ButtonSegment(value: 'balanced', label: Text('Zrównoważony')), ButtonSegment(value: 'battery', label: Text('Oszczędzanie baterii'))], selected: {st.get<String>('profile')}, onSelectionChanged: (v) {
          st.set('profile', v.first);
          st.set('previewScale', v.first == 'performance' ? 0.5 : v.first == 'battery' ? 0.25 : 0.33);
          st.set('encoder', v.first == 'battery' ? 'hardware' : 'auto');
        }),
        LabeledSlider(label: 'Rozdzielczość podglądu', value: st.get<num>('previewScale').toDouble(), min: 0.2, max: 1, decimals: 2, onChanged: (v) => setState(() => st.set('previewScale', v))),
        DropdownButtonFormField<String>(value: st.get<String>('encoder'), decoration: const InputDecoration(labelText: 'Enkoder wideo'), items: const [DropdownMenuItem(value: 'auto', child: Text('Automatyczny (GPU → programowy)')), DropdownMenuItem(value: 'hardware', child: Text('Sprzętowy')), DropdownMenuItem(value: 'software', child: Text('Programowy'))], onChanged: (v) => st.set('encoder', v)),
        LabeledSlider(label: 'Autozapis co', value: st.get<num>('autosaveSec').toDouble(), min: 5, max: 120, unit: 's', decimals: 0, onChanged: (v) => setState(() => st.set('autosaveSec', v.round()))),
        FutureBuilder<Set<String>>(future: Services.i.videoRenderer().availableEncoders(), builder: (c, s) {
          final hw = (s.data ?? {}).where((e) => e.contains('nvenc') || e.contains('qsv') || e.contains('amf') || e.contains('mediacodec') || e.endsWith('_mf')).toList();
          return Text('Dostępne enkodery sprzętowe: ${hw.isEmpty ? 'brak wykrytych' : hw.join(', ')}', style: const TextStyle(fontSize: 12, color: WmsColors.muted));
        }),
      ]),
      Section(title: 'Dane i pamięć', children: [
        Text('Folder danych: ${Services.i.root.path}', style: const TextStyle(fontSize: 12)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: () async {
            final d = Directory('${Services.i.store.cacheDir.path}');
            var n = 0;
            if (d.existsSync()) {
              for (final f in d.listSync(recursive: true).whereType<File>()) {
                if (!f.path.contains('analysis_')) {
                  n += f.lengthSync();
                  f.deleteSync();
                }
              }
            }
            if (context.mounted) toast(context, 'Wyczyszczono cache (${fmtBytes(n)}). Materiały źródłowe nie zostały usunięte.');
          }, icon: const Icon(Icons.cleaning_services), label: const Text('Wyczyść cache podglądu')),
          OutlinedButton.icon(onPressed: () async {
            final out = exportPath('WoJan_eksport_danych', 'json');
            final data = {'settings': st.v, 'kv': {for (final c in Services.i.kv.collections()) c: {for (final k in Services.i.kv.keys(c)) k: Services.i.kv.get(c, k)}}, 'projects': [for (final p in await Services.i.store.list()) (await Services.i.store.load(p.id)).toJson()], 'publishHistory': Services.i.publishHistory.records.map((e) => e.toJson()).toList()};
            await File(out).writeAsString(const JsonEncoder.withIndent(' ').convert(data));
            await SharePlus.instance.share(ShareParams(files: [XFile(out, mimeType: 'application/json')]));
          }, icon: const Icon(Icons.download), label: const Text('Eksport moich danych')),
          OutlinedButton.icon(onPressed: () async {
            if (!await confirm(context, 'Usunąć wszystkie dane?', 'Usunięte zostaną lokalne projekty, kopie materiałów, cache, ustawienia i tokeny. Pliki oryginalne poza aplikacją pozostaną nietknięte. Tej operacji nie można cofnąć.')) return;
            await Services.i.auth.signOut();
            await Services.i.store.close();
            await Services.i.root.delete(recursive: true);
            exit(0);
          }, icon: const Icon(Icons.delete_forever, color: WmsColors.error), label: const Text('Usuń dane użytkownika')),
        ]),
      ]),
      Section(title: 'Aktualizacje', children: [
        Text('Wersja: $appVersion'),
        FilledButton.tonalIcon(onPressed: _checkUpdate, icon: const Icon(Icons.system_update), label: const Text('Sprawdź aktualizacje')),
        if (updateStatus.isNotEmpty) Text(updateStatus),
      ]),
      Section(title: 'O aplikacji', children: [
        const Text('WoJan Media Studio – autonomiczne studio multimedialne. Bez reklam, bez telemetrii, bez znaków wodnych. Przetwarzanie lokalne (FFmpeg).'),
        TextButton(onPressed: () => showLicensePage(context: context, applicationName: 'WoJan Media Studio', applicationVersion: appVersion), child: const Text('Licencje open source')),
      ]),
    ]);
  }
}
