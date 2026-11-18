import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../engine/project/format.dart';
import '../platform/native.dart';
import 'screens/works_screen.dart';
import 'screens/audio_studio.dart';
import 'screens/batch_screen.dart';
import 'screens/converter.dart';
import 'screens/history_screen.dart';
import 'screens/library_screen.dart';
import 'screens/lyrics_screen.dart';
import 'screens/projects_screen.dart';
import 'screens/publisher_screen.dart';
import 'screens/queue_screen.dart';
import 'screens/quick_video.dart';
import 'screens/settings_screen.dart';
import 'screens/sync_screen.dart';
import 'screens/templates_screen.dart';
import 'screens/video_studio.dart';
import 'screens/visualizer_screen.dart';
import 'widgets/common.dart';

class _Dest {
  final String key;
  final IconData icon;
  final bool pro;
  const _Dest(this.key, this.icon, {this.pro = false});
}

const _dests = [
  _Dest('m.projects', Icons.dashboard_outlined),
  _Dest('m.audio', Icons.graphic_eq),
  _Dest('m.video', Icons.movie_edit),
  _Dest('m.quick', Icons.auto_awesome),
  _Dest('m.lyric', Icons.lyrics_outlined),
  _Dest('m.karaoke', Icons.mic_external_on),
  _Dest('m.visualizer', Icons.equalizer),
  _Dest('m.converter', Icons.swap_horiz),
  _Dest('m.library', Icons.perm_media_outlined),
  _Dest('m.templates', Icons.style_outlined),
  _Dest('m.batch', Icons.dynamic_feed, pro: true),
  _Dest('m.queue', Icons.queue_play_next),
  _Dest('m.publisher', Icons.share_outlined),
  _Dest('m.history', Icons.history),
  _Dest('m.works', Icons.folder_special_outlined),
  _Dest('m.sync', Icons.sync),
  _Dest('m.settings', Icons.settings_outlined),
];

/// Global navigation controller so screens can open each other.
class Nav {
  static final index = ValueNotifier<int>(0);
  static String? openProjectId;
  static void openProject(ProjectDoc d) {
    openProjectId = d.id;
    index.value = d.type == ProjectType.audio ? 1 : 2;
  }

  static void go(String key) => index.value = _dests.indexWhere((d) => d.key == key);
}

class AppShell extends StatefulWidget {
  final String? openFile;
  const AppShell({super.key, this.openFile});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.openFile != null) await _importPackage(widget.openFile!);
      await _takeShared();
      _checkRecovery();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _takeShared();
      if (Services.i.settings.get<bool>('autoSync')) Services.i.syncNow(silent: true);
    }
  }

  Future<void> _takeShared() async {
    final files = await NativeBridge.takeSharedFiles();
    if (files.isEmpty || !mounted) return;
    final pkgs = files.where((f) => f.toLowerCase().endsWith('.wojanmedia')).toList();
    for (final p in pkgs) {
      await _importPackage(p);
    }
    final media = files.where((f) => !pkgs.contains(f)).toList();
    if (media.isNotEmpty && mounted) {
      final a = await importPaths(context, media);
      if (mounted) toast(context, 'Dodano ${a.length} plików do biblioteki materiałów');
      Nav.go('m.library');
    }
  }

  Future<void> _importPackage(String path) async {
    final d = await runBusy(context, 'Import projektu…', () => Services.i.store.importPackage(path));
    if (d != null && mounted) {
      toast(context, 'Zaimportowano projekt „${d.name}”');
      Nav.openProject(d);
    }
  }

  Future<void> _checkRecovery() async {
    final s = Services.i.store;
    for (final p in await s.list()) {
      final r = await s.recoverable(p.id);
      if (r != null && mounted) {
        if (await confirm(context, 'Odzyskiwanie po awarii', 'Znaleziono niezapisane zmiany projektu „${p.name}”. Przywrócić je?')) {
          await s.save(r);
        } else {
          final f = s.autosaveFile(p.id);
          if (f.existsSync()) f.deleteSync();
        }
      }
    }
  }

  Widget _screen(int i) {
    switch (_dests[i].key) {
      case 'm.projects':
        return const ProjectsScreen();
      case 'm.audio':
        return AudioStudioScreen(key: ValueKey('audio_${Nav.openProjectId}'));
      case 'm.video':
        return VideoStudioScreen(key: ValueKey('video_${Nav.openProjectId}'));
      case 'm.quick':
        return const QuickVideoScreen();
      case 'm.lyric':
        return const LyricsScreen(karaoke: false);
      case 'm.karaoke':
        return const LyricsScreen(key: ValueKey('karaoke'), karaoke: true);
      case 'm.visualizer':
        return const VisualizerScreen();
      case 'm.converter':
        return const ConverterScreen();
      case 'm.library':
        return const LibraryScreen();
      case 'm.templates':
        return const TemplatesScreen();
      case 'm.batch':
        return const BatchScreen();
      case 'm.queue':
        return const QueueScreen();
      case 'm.publisher':
        return const PublisherScreen();
      case 'm.history':
        return const HistoryScreen();
      case 'm.works':
        return const WorksScreen();
      case 'm.sync':
        return const SyncScreen();
      default:
        return const SettingsScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pro = Services.i.settings.get<bool>('proMode');
    return ValueListenableBuilder<int>(
      valueListenable: Nav.index,
      builder: (c, idx, _) {
        final body = DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (d) async {
            setState(() => _dragging = false);
            final paths = d.files.map((f) => f.path).toList();
            final pk = paths.where((p) => p.toLowerCase().endsWith('.wojanmedia')).toList();
            for (final p in pk) {
              await _importPackage(p);
            }
            final rest = paths.where((p) => !pk.contains(p)).toList();
            if (rest.isNotEmpty && mounted) {
              final a = await importPaths(context, rest);
              if (mounted) toast(context, 'Zaimportowano ${a.length} plików');
            }
          },
          child: Stack(children: [
            Positioned.fill(child: _screen(idx)),
            if (_dragging) Positioned.fill(child: Container(color: WmsColors.accent.withValues(alpha: 0.15), alignment: Alignment.center, child: const Text('Upuść pliki, aby zaimportować', style: TextStyle(fontSize: 24)))),
          ]),
        );
        final shortcuts = <ShortcutActivator, VoidCallback>{
          for (var i = 0; i < 9; i++) SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i), control: true): () => Nav.index.value = i,
        };
        if (wide) {
          return CallbackShortcuts(
            bindings: shortcuts,
            child: Scaffold(
              body: Row(children: [
                SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height),
                    child: IntrinsicHeight(
                      child: NavigationRail(
                        extended: MediaQuery.sizeOf(context).width >= 1300,
                        selectedIndex: idx,
                        onDestinationSelected: (i) => Nav.index.value = i,
                        leading: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Image.asset('assets/branding/logo.png', width: 40, height: 40)),
                        destinations: [for (final d in _dests) NavigationRailDestination(icon: Icon(d.icon), label: Text(tr(d.key)))],
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ]),
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(tr(_dests[idx].key))),
          drawer: Drawer(
            child: ListView(children: [
              DrawerHeader(child: Row(children: [Image.asset('assets/branding/logo.png', width: 56), const SizedBox(width: 12), const Expanded(child: Text('WoJan Media Studio', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)))])),
              for (var i = 0; i < _dests.length; i++)
                if (pro || !_dests[i].pro)
                  ListTile(
                    leading: Icon(_dests[i].icon),
                    title: Text(tr(_dests[i].key)),
                    selected: i == idx,
                    onTap: () {
                      Navigator.pop(context);
                      Nav.index.value = i;
                    },
                  ),
            ]),
          ),
          body: body,
        );
      },
    );
  }
}

Future<void> openExternal(String path) async {
  if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', path]);
  }
}
