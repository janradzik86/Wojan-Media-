import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../engine/audio/audio_project.dart';
import '../../engine/project/format.dart';
import '../../engine/project/store.dart';
import '../../engine/sync/engine.dart';
import '../../engine/util/json_util.dart';
import '../../engine/video/model.dart';
import '../shell.dart';
import '../widgets/common.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

enum _View { all, favorites, archive, trash }

class _ProjectsScreenState extends State<ProjectsScreen> {
  final _q = TextEditingController();
  _View view = _View.all;
  SortBy sort = SortBy.modified;
  String? tag;
  List<ProjectSummary> items = [];
  final store = Services.i.store;

  @override
  void initState() {
    super.initState();
    _load();
    Services.i.syncBusy.addListener(_onSync);
  }

  @override
  void dispose() {
    Services.i.syncBusy.removeListener(_onSync);
    super.dispose();
  }

  void _onSync() {
    if (!Services.i.syncBusy.value) _load();
  }

  Future<void> _load() async {
    final l = await store.list(query: _q.text, favorites: view == _View.favorites, archived: view == _View.archive, trash: view == _View.trash, sort: sort, desc: sort != SortBy.name, tag: tag);
    if (mounted) setState(() => items = l);
  }

  Future<void> _create(ProjectType t) async {
    final name = await promptText(context, tr('new_project'), initial: t == ProjectType.audio ? 'Nowy projekt audio' : 'Nowy film');
    if (name == null || name.isEmpty) return;
    final d = await store.create(name, t);
    if (t == ProjectType.audio) {
      d.audio = AudioProject();
    } else {
      d.video = VideoProject();
    }
    await store.save(d);
    Nav.openProject(d);
  }

  Future<void> _open(ProjectSummary p) async {
    final d = await store.load(p.id);
    final missing = store.missingMedia(d);
    if (missing.isNotEmpty && Services.i.sync != null && mounted) {
      await runBusy(context, 'Pobieranie ${missing.length} materiałów z chmury…', () => Services.i.sync!.fetchMedia(d));
    }
    Nav.openProject(d);
  }

  Future<void> _action(ProjectSummary p, String a) async {
    switch (a) {
      case 'open':
        await _open(p);
        break;
      case 'dup':
        await store.duplicate(p.id);
        break;
      case 'fav':
        final d = await store.load(p.id);
        d.favorite = !d.favorite;
        await store.save(d);
        break;
      case 'archive':
        final d = await store.load(p.id);
        d.archived = !d.archived;
        await store.save(d);
        break;
      case 'rename':
        final d = await store.load(p.id);
        final n = await promptText(context, 'Zmień nazwę', initial: d.name);
        if (n != null && n.isNotEmpty) {
          d.name = n;
          await store.save(d);
        }
        break;
      case 'tags':
        final d = await store.load(p.id);
        final n = await promptText(context, 'Kategoria | tagi (oddzielone przecinkami)', initial: '${d.category} | ${d.tags.join(', ')}');
        if (n != null) {
          final parts = n.split('|');
          d.category = parts.first.trim();
          d.tags = parts.length > 1 ? parts[1].split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() : [];
          await store.save(d);
        }
        break;
      case 'trash':
        await store.trash(p.id);
        break;
      case 'restore':
        await store.restore(p.id);
        break;
      case 'purge':
        if (!mounted || !await confirm(context, 'Usunąć na zawsze?', 'Projekt „${p.name}” zostanie trwale usunięty${Services.i.sync != null ? ' ze wszystkich urządzeń' : ''}. Pliki źródłowe w bibliotece materiałów nie zostaną usunięte.')) return;
        if (Services.i.sync != null) {
          await Services.i.sync!.deleteEverywhere(p.id);
        } else {
          await store.purge(p.id);
        }
        break;
      case 'export':
        final out = exportPath(p.name, 'wojanmedia');
        await runBusy(context, 'Pakowanie projektu z materiałami…', () => store.exportPackage(p.id, out));
        if (!mounted) return;
        if (isDesktop) {
          final dest = await FilePicker.platform.saveFile(dialogTitle: 'Zapisz pakiet projektu', fileName: out.split(RegExp(r'[\\/]')).last);
          if (dest != null) await File(out).copy(dest);
        } else {
          await SharePlus.instance.share(ShareParams(files: [XFile(out, mimeType: 'application/octet-stream')], subject: p.name));
        }
        break;
      case 'history':
        final revs = await store.history(p.id);
        if (!mounted) return;
        final r = await showDialog<String>(
          context: context,
          builder: (c) => SimpleDialog(title: const Text('Historia wersji'), children: [
            for (final rev in revs.take(30)) SimpleDialogOption(onPressed: () => Navigator.pop(c, rev), child: Text(rev.substring(0, 8))),
          ]),
        );
        if (r != null) {
          final old = await store.loadRevision(p.id, r);
          final cur = await store.load(p.id);
          old.id = cur.id;
          old.revision = cur.revision;
          old.ancestors = cur.ancestors;
          await store.save(old);
          if (mounted) toast(context, 'Przywrócono wersję ${r.substring(0, 8)} (jako nową rewizję)');
        }
        break;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 700;
    return Scaffold(
      floatingActionButton: view == _View.trash
          ? FloatingActionButton.extended(onPressed: () async {
              final n = await store.emptyTrash();
              if (context.mounted) toast(context, 'Usunięto $n projektów z kosza');
              _load();
            }, icon: const Icon(Icons.delete_sweep), label: const Text('Opróżnij kosz'))
          : FloatingActionButton.extended(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ListTile(leading: const Icon(Icons.graphic_eq), title: const Text('Projekt audio (wielościeżkowy)'), onTap: () => {Navigator.pop(c), _create(ProjectType.audio)}),
                  ListTile(leading: const Icon(Icons.movie), title: const Text('Projekt wideo / pokaz slajdów'), onTap: () => {Navigator.pop(c), _create(ProjectType.video)}),
                  ListTile(leading: const Icon(Icons.auto_awesome), title: const Text('Szybki teledysk (automatyczny)'), onTap: () => {Navigator.pop(c), Nav.go('m.quick')}),
                  ListTile(leading: const Icon(Icons.unarchive), title: const Text('Importuj projekt .wojanmedia'), onTap: () async {
                    Navigator.pop(c);
                    final f = await pickFiles(extensions: ['wojanmedia', 'zip'], multiple: false);
                    if (f.isEmpty || !mounted) return;
                    final d = await runBusy(context, 'Import projektu…', () => store.importPackage(f.first));
                    if (d != null) _load();
                  }),
                ])),
              ),
              icon: const Icon(Icons.add),
              label: Text(tr('new_project')),
            ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: wide ? 320 : double.infinity, child: TextField(controller: _q, decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('search')), onChanged: (_) => _load())),
            SegmentedButton<_View>(
              segments: const [
                ButtonSegment(value: _View.all, label: Text('Wszystkie')),
                ButtonSegment(value: _View.favorites, icon: Icon(Icons.star_border)),
                ButtonSegment(value: _View.archive, icon: Icon(Icons.archive_outlined)),
                ButtonSegment(value: _View.trash, icon: Icon(Icons.delete_outline)),
              ],
              selected: {view},
              onSelectionChanged: (s) {
                view = s.first;
                _load();
              },
            ),
            DropdownButton<SortBy>(
              value: sort,
              items: const [
                DropdownMenuItem(value: SortBy.modified, child: Text('Data modyfikacji')),
                DropdownMenuItem(value: SortBy.created, child: Text('Data utworzenia')),
                DropdownMenuItem(value: SortBy.name, child: Text('Nazwa')),
                DropdownMenuItem(value: SortBy.duration, child: Text('Czas trwania')),
                DropdownMenuItem(value: SortBy.size, child: Text('Rozmiar')),
              ],
              onChanged: (v) {
                sort = v!;
                _load();
              },
            ),
            if (tag != null) InputChip(label: Text('#$tag'), onDeleted: () => {tag = null, _load()}),
            ValueListenableBuilder<String>(valueListenable: Services.i.syncStatus, builder: (c, s, _) => s.isEmpty ? const SizedBox() : Text(s, style: const TextStyle(color: WmsColors.muted, fontSize: 12))),
          ]),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('Brak projektów. Utwórz nowy lub zaimportuj materiały.'))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 280, childAspectRatio: 0.82, crossAxisSpacing: 10, mainAxisSpacing: 10),
                  itemCount: items.length,
                  itemBuilder: (c, i) => _ProjectCard(p: items[i], onAction: (a) => _action(items[i], a), onTag: (t) => {tag = t, _load()}),
                ),
        ),
      ]),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final ProjectSummary p;
  final void Function(String) onAction;
  final void Function(String) onTag;
  const _ProjectCard({required this.p, required this.onAction, required this.onTag});

  IconData get _syncIcon => switch (SyncState.values.where((s) => s.name == p.syncState).firstOrNull) {
        SyncState.synced => Icons.cloud_done_outlined,
        SyncState.uploading => Icons.cloud_upload_outlined,
        SyncState.downloading => Icons.cloud_download_outlined,
        SyncState.conflict => Icons.call_split,
        SyncState.error || SyncState.noSpace || SyncState.reauth => Icons.cloud_off,
        SyncState.waiting => Icons.cloud_queue,
        _ => Icons.computer,
      };

  @override
  Widget build(BuildContext context) {
    final trash = p.trashed;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: trash ? null : () => onAction('open'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              p.thumb != null && File(p.thumb!).existsSync()
                  ? Image.file(File(p.thumb!), fit: BoxFit.cover, cacheWidth: 400)
                  : Container(color: WmsColors.panel2, child: Icon(p.type == 'audio' ? Icons.graphic_eq : Icons.movie, size: 48, color: WmsColors.muted)),
              Positioned(right: 6, top: 6, child: Tooltip(message: syncStateNames[SyncState.values.where((s) => s.name == p.syncState).firstOrNull] ?? 'Lokalnie', child: CircleAvatar(radius: 14, backgroundColor: Colors.black54, child: Icon(_syncIcon, size: 16)))),
              if (p.favorite) const Positioned(left: 6, top: 6, child: Icon(Icons.star, color: WmsColors.warn)),
              Positioned(left: 6, bottom: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), color: Colors.black54, child: Text(fmtTime(p.duration), style: const TextStyle(fontSize: 11)))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 0, 4),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${p.modified.toLocal().toString().substring(0, 16)} • ${fmtBytes(p.size)}', style: const TextStyle(fontSize: 11, color: WmsColors.muted)),
                  Text('Render: ${p.renderStatus} • Publikacja: ${p.publishStatus}', style: const TextStyle(fontSize: 10, color: WmsColors.muted), maxLines: 1),
                  if (p.tags.isNotEmpty || p.category.isNotEmpty)
                    Wrap(spacing: 4, children: [
                      if (p.category.isNotEmpty) Text(p.category, style: const TextStyle(fontSize: 11, color: WmsColors.accent2)),
                      for (final t in p.tags) InkWell(onTap: () => onTag(t), child: Text('#$t', style: const TextStyle(fontSize: 11, color: WmsColors.accent))),
                    ]),
                ]),
              ),
              PopupMenuButton<String>(
                onSelected: onAction,
                itemBuilder: (c) => trash
                    ? const [PopupMenuItem(value: 'restore', child: Text('Przywróć')), PopupMenuItem(value: 'purge', child: Text('Usuń na zawsze'))]
                    : [
                        const PopupMenuItem(value: 'open', child: Text('Otwórz')),
                        const PopupMenuItem(value: 'rename', child: Text('Zmień nazwę')),
                        const PopupMenuItem(value: 'tags', child: Text('Kategoria i tagi')),
                        PopupMenuItem(value: 'fav', child: Text(p.favorite ? 'Usuń z ulubionych' : 'Dodaj do ulubionych')),
                        const PopupMenuItem(value: 'dup', child: Text('Duplikuj')),
                        PopupMenuItem(value: 'archive', child: Text(p.archived ? 'Przywróć z archiwum' : 'Archiwizuj')),
                        const PopupMenuItem(value: 'history', child: Text('Historia wersji…')),
                        const PopupMenuItem(value: 'export', child: Text('Eksportuj pakiet .wojanmedia')),
                        const PopupMenuItem(value: 'trash', child: Text('Przenieś do kosza')),
                      ],
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
