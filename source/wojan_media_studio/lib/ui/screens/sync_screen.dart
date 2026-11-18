import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../engine/sync/engine.dart';
import '../../engine/util/json_util.dart';
import '../../platform/auth.dart';
import '../widgets/common.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  List<DeviceInfo> devices = [];
  String? quota;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = Services.i.sync;
    if (s == null) return;
    try {
      final d = await s.devices();
      final q = await s.remote.quota();
      setState(() {
        devices = d;
        quota = q.limit == null ? null : '${fmtBytes(q.usage)} z ${fmtBytes(q.limit!)} (wolne ${fmtBytes(q.free!)})';
      });
    } catch (_) {}
  }

  Future<void> _login() async {
    try {
      await Services.i.auth.signIn([scopeDriveAppData]);
      Services.i.settings.set('syncFolder', '');
      await Services.i.reconfigureSync();
      await Services.i.syncNow();
      _refresh();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.i;
    final st = s.settings;
    final folder = st.get<String>('syncFolder');
    return ListView(padding: const EdgeInsets.all(12), children: [
      Section(title: 'Konto Google (Dysk Google – ukryty folder aplikacji)', children: [
        if (s.auth.signedIn) ...[
          ListTile(leading: const Icon(Icons.account_circle), title: Text(s.auth.email ?? ''), subtitle: Text(quota == null ? 'Uprawnienia: tylko dane tej aplikacji (drive.appdata)' : 'Dysk: $quota')),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: () async {
              await s.auth.signOut(revoke: false);
              await s.reconfigureSync();
              setState(() {});
            }, icon: const Icon(Icons.logout), label: const Text('Wyloguj')),
            OutlinedButton.icon(onPressed: () async {
              if (!await confirm(context, 'Odłączyć konto?', 'Dostęp aplikacji do konta Google zostanie cofnięty. Dane w chmurze pozostaną (możesz je usunąć w ustawieniach Dysku Google → Zarządzaj aplikacjami).')) return;
              await s.auth.signOut(revoke: true);
              await s.reconfigureSync();
              setState(() {});
            }, icon: const Icon(Icons.link_off), label: const Text('Cofnij dostęp')),
          ]),
        ] else ...[
          const Text('Zaloguj się tym samym kontem Google na telefonie i komputerze. Projekty, materiały, szablony i ustawienia zsynchronizują się automatycznie – bez konfiguracji serwerów, portów ani kluczy.'),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _login, icon: const Icon(Icons.login), label: const Text('Zaloguj przez Google')),
          if (!OAuthConfig.configured) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Ta kompilacja nie zawiera identyfikatora klienta OAuth – logowanie Google będzie niedostępne do czasu jednorazowej konfiguracji przez właściciela (docs/SYNC_ARCHITECTURE.md). Możesz użyć synchronizacji przez folder.', style: TextStyle(color: WmsColors.warn, fontSize: 12))),
        ],
      ]),
      Section(title: 'Alternatywa: folder synchronizowany', children: [
        const Text('Wskaż folder OneDrive / Dropbox / Dysk Google dla komputerów / NAS / pendrive. Ten sam mechanizm (rewizje, SHA-256, konflikty) działa bez logowania.', style: TextStyle(fontSize: 12)),
        Row(children: [
          Expanded(child: Text(folder.isEmpty ? 'Nie wybrano' : folder)),
          TextButton(onPressed: () async {
            final d = await FilePicker.getDirectoryPath(dialogTitle: 'Folder synchronizacji');
            if (d == null) return;
            st.set('syncFolder', '$d/WoJanMediaStudioSync');
            await s.reconfigureSync();
            setState(() {});
          }, child: const Text('Wybierz')),
          if (folder.isNotEmpty) TextButton(onPressed: () async {
            st.set('syncFolder', '');
            await s.reconfigureSync();
            setState(() {});
          }, child: const Text('Wyłącz')),
        ]),
      ]),
      Section(title: 'Status', children: [
        ValueListenableBuilder<String>(valueListenable: s.syncStatus, builder: (c, v, _) => Text(v.isEmpty ? (s.sync == null ? 'Synchronizacja wyłączona – praca lokalna' : 'Gotowe') : v)),
        Text('Ostatnia udana synchronizacja: ${s.sync?.lastSuccess?.toLocal().toString().substring(0, 19) ?? '—'}'),
        const SizedBox(height: 6),
        ValueListenableBuilder<bool>(
          valueListenable: s.syncBusy,
          builder: (c, busy, _) => FilledButton.icon(onPressed: s.sync == null || busy ? null : () async {
            final r = await s.syncNow();
            if (context.mounted && r != null) toast(context, '${syncStateNames[r.overall]}: $r${r.errors.isEmpty ? '' : '\n${r.errors.join('\n')}'}', error: r.errors.isNotEmpty);
            _refresh();
          }, icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync), label: const Text('Synchronizuj teraz')),
        ),
        const SizedBox(height: 6),
        const Text('Uwaga: pliki, które nie zostały w pełni przesłane do chmury przed utratą urządzenia, nie mogą zostać odzyskane.', style: TextStyle(color: WmsColors.muted, fontSize: 12)),
      ]),
      Section(title: 'Opcje', children: [
        SwitchListTile(value: st.get<bool>('autoSync'), onChanged: (v) async => {st.set('autoSync', v), await s.reconfigureSync(), setState(() {})}, title: const Text('Automatyczna synchronizacja (co 5 min i przy starcie)')),
        SwitchListTile(value: st.get<bool>('wifiOnly'), onChanged: (v) => setState(() => st.set('wifiOnly', v)), title: const Text('Tylko przez Wi-Fi / sieć bez limitu')),
        LabeledSlider(label: 'Pobieraj automatycznie pliki do', value: st.get<num>('eagerDownloadMB').toDouble(), min: 0, max: 2048, unit: 'MB', decimals: 0, onChanged: (v) => setState(() => st.set('eagerDownloadMB', v.round()))),
        const Text('Większe pliki są pobierane na żądanie przy otwarciu projektu.', style: TextStyle(fontSize: 12, color: WmsColors.muted)),
      ]),
      Section(title: 'Autoryzowane urządzenia', trailing: IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)), children: [
        for (final d in devices)
          ListTile(
            leading: Icon(d.platform == 'android' ? Icons.phone_android : Icons.computer),
            title: Text('${d.name}${d.id == s.deviceId ? ' (to urządzenie)' : ''}'),
            subtitle: Text('${d.revoked ? 'ODŁĄCZONE • ' : ''}ostatnio: ${d.lastSeen.toLocal().toString().substring(0, 16)}'),
            trailing: d.id == s.deviceId || d.revoked ? null : TextButton(onPressed: () async {
              if (!await confirm(context, 'Odłączyć urządzenie?', '${d.name} przestanie synchronizować dane.')) return;
              await s.sync!.revokeDevice(d.id);
              _refresh();
            }, child: const Text('Odłącz')),
          ),
      ]),
    ]);
  }
}
