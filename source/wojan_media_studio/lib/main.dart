import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

import 'app/services.dart';
import 'app/theme.dart';
import 'ui/shell.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final log = <String>[];
  FlutterError.onError = (d) {
    log.add('${d.exception}');
    FlutterError.presentError(d);
  };
  Services? services;
  Object? initError;
  try {
    services = await Services.init();
  } catch (e) {
    initError = e;
  }
  // File passed on the command line (Windows: double-clicked .wojanmedia).
  final openFile = args.where((a) => a.toLowerCase().endsWith('.wojanmedia') && File(a).existsSync()).firstOrNull;
  runApp(WojanApp(initError: initError, openFile: openFile, ready: services != null));
}

class WojanApp extends StatelessWidget {
  final Object? initError;
  final String? openFile;
  final bool ready;
  const WojanApp({super.key, this.initError, this.openFile, required this.ready});

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Nie udało się uruchomić WoJan Media Studio:\n$initError')))),
      );
    }
    final s = Services.i;
    return ListenableBuilder(
      listenable: Listenable.merge([s.settings, s.l10n]),
      builder: (c, _) => MaterialApp(
        title: 'WoJan Media Studio',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: s.settings.get<String>('theme') == 'light' ? ThemeMode.light : ThemeMode.dark,
        home: AppShell(openFile: openFile),
      ),
    );
  }
}
