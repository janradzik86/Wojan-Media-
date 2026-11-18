import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../engine/musicvideo/styles.dart';
import '../../engine/video/model.dart';
import '../../engine/video/vfx.dart';
import '../../engine/video/visualizer.dart';
import '../../engine/video/color.dart';
import '../widgets/common.dart';
import 'video_widgets.dart';

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});
  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  List<StyleTemplate> get user => Services.i.userStyles();

  void _save(StyleTemplate t) {
    Services.i.kv.put('templates', t.id, t.toJson());
    setState(() {});
  }

  Future<void> _edit(StyleTemplate t) async {
    final s = StyleTemplate.fromJson(t.toJson());
    await Navigator.push(context, MaterialPageRoute(builder: (_) => _TemplateEditor(s: s)));
    if (!s.builtIn) _save(s);
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          Text('Szablony teledysków', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          OutlinedButton.icon(onPressed: () async {
            final f = await pickFiles(extensions: ['json'], multiple: false);
            if (f.isEmpty) return;
            final j = jsonDecode(await File(f.first).readAsString());
            for (final m in (j is List ? j : [j])) {
              final t = StyleTemplate.fromJson(Map<String, dynamic>.from(m as Map));
              _save(t.copyAs(const Uuid().v4(), t.name));
            }
          }, icon: const Icon(Icons.file_download), label: const Text('Importuj')),
        ]),
        const Text('Szablony fabryczne (duplikuj, aby edytować) i własne – synchronizowane między urządzeniami.', style: TextStyle(color: WmsColors.muted)),
        const SizedBox(height: 8),
        for (final t in [...user, ...factoryStyles])
          Card(
            child: ListTile(
              leading: CircleAvatar(backgroundColor: Color(int.parse('FF${t.accentColor.substring(1)}', radix: 16)), child: Text(t.name.characters.first)),
              title: Text(t.name + (t.builtIn ? '' : '  ★')),
              subtitle: Text('${t.font} • cięcie co ${t.cutEveryBeats} bitów • ${t.transitions.map((x) => transitionNames[x] ?? x).join(', ')} • efekty: ${t.vfx.map((x) => vfxNames[x] ?? x).join(', ')}', maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'Duplikuj', icon: const Icon(Icons.copy), onPressed: () => _save(t.copyAs(const Uuid().v4(), '${t.name} (moja wersja)'))),
                if (!t.builtIn) IconButton(tooltip: 'Edytuj', icon: const Icon(Icons.edit), onPressed: () => _edit(t)),
                IconButton(tooltip: 'Eksportuj', icon: const Icon(Icons.ios_share), onPressed: () async {
                  final p = exportPath('szablon_${t.name}', 'json');
                  await File(p).writeAsString(const JsonEncoder.withIndent('  ').convert(t.toJson()));
                  await SharePlus.instance.share(ShareParams(files: [XFile(p, mimeType: 'application/json')]));
                }),
                if (!t.builtIn) IconButton(tooltip: 'Usuń', icon: const Icon(Icons.delete_outline), onPressed: () => {Services.i.kv.remove('templates', t.id), setState(() {})}),
              ]),
            ),
          ),
        const SizedBox(height: 12),
        Section(title: 'Presety efektów audio', children: [
          for (final k in Services.i.kv.keys('fxPresets')) ListTile(title: Text(k), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => {Services.i.kv.remove('fxPresets', k), setState(() {})})),
          if (Services.i.kv.keys('fxPresets').isEmpty) const Text('Zapisz preset w Studiu Audio (efekty master → ★).', style: TextStyle(color: WmsColors.muted)),
        ]),
        Section(title: 'Presety kolorów', children: [for (final k in Services.i.kv.keys('colorPresets')) ListTile(title: Text(k), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => {Services.i.kv.remove('colorPresets', k), setState(() {})}))]),
        Section(title: 'Presety eksportu', children: [for (final k in Services.i.kv.keys('exportPresets')) ListTile(title: Text(k), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => {Services.i.kv.remove('exportPresets', k), setState(() {})}))]),
      ]);
}

class _TemplateEditor extends StatefulWidget {
  final StyleTemplate s;
  const _TemplateEditor({required this.s});
  @override
  State<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<_TemplateEditor> {
  StyleTemplate get s => widget.s;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Szablon: ${s.name}')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          TextField(controller: TextEditingController(text: s.name), decoration: const InputDecoration(labelText: 'Nazwa'), onChanged: (v) => s.name = v),
          Section(title: 'Napisy', children: [
            DropdownButtonFormField<String>(value: fontFamilies.contains(s.font) ? s.font : fontFamilies.first, items: [for (final f in fontFamilies) DropdownMenuItem(value: f, child: Text(f))], onChanged: (v) => setState(() => s.font = v!)),
            const Text('Kolor tekstu'),
            ColorDots(value: s.textColor, onChanged: (v) => setState(() => s.textColor = v)),
            const Text('Akcent'),
            ColorDots(value: s.accentColor, onChanged: (v) => setState(() => s.accentColor = v)),
            DropdownButton<String>(value: s.textAnim, items: [for (final e in textAnimNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => setState(() => s.textAnim = v!)),
          ]),
          Section(title: 'Montaż', children: [
            LabeledSlider(label: 'Cięcie co (bity)', value: s.cutEveryBeats.toDouble(), min: 1, max: 16, decimals: 0, onChanged: (v) => setState(() => s.cutEveryBeats = v.round())),
            LabeledSlider(label: 'Długość przejścia (bity)', value: s.transitionBeats, min: 0.25, max: 8, decimals: 2, onChanged: (v) => setState(() => s.transitionBeats = v)),
            LabeledSlider(label: 'Intensywność ruchu', value: s.motionIntensity, min: 0, max: 1, decimals: 2, onChanged: (v) => setState(() => s.motionIntensity = v)),
            Wrap(spacing: 4, runSpacing: 4, children: [for (final e in transitionNames.entries) FilterChip(label: Text(e.value, style: const TextStyle(fontSize: 11)), selected: s.transitions.contains(e.key), onSelected: (v) => setState(() => s.transitions = v ? [...s.transitions, e.key] : (s.transitions.length > 1 ? (List.of(s.transitions)..remove(e.key)) : s.transitions)))]),
            const Divider(),
            Wrap(spacing: 4, runSpacing: 4, children: [for (final m in MotionPreset.values.where((m) => m != MotionPreset.none)) FilterChip(label: Text(motionNames[m]!, style: const TextStyle(fontSize: 11)), selected: s.motions.contains(m.name), onSelected: (v) => setState(() => s.motions = v ? [...s.motions, m.name] : (s.motions.length > 1 ? (List.of(s.motions)..remove(m.name)) : s.motions)))]),
          ]),
          Section(title: 'Efekty i kolor', children: [
            Wrap(spacing: 4, runSpacing: 4, children: [for (final e in vfxNames.entries) FilterChip(label: Text(e.value, style: const TextStyle(fontSize: 11)), selected: s.vfx.contains(e.key), onSelected: (v) => setState(() => s.vfx = v ? [...s.vfx, e.key] : (List.of(s.vfx)..remove(e.key))))]),
            SwitchListTile(value: s.reactiveVfx, onChanged: (v) => setState(() => s.reactiveVfx = v), title: const Text('Efekty reagują na muzykę')),
            DropdownButton<String>(value: s.grade, items: [const DropdownMenuItem(value: '', child: Text('Bez filtra')), for (final e in lookNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => setState(() => s.grade = v!)),
            DropdownButton<String>(value: s.visualizer, items: [for (final e in visualizerNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => setState(() => s.visualizer = v!)),
          ]),
        ]),
      );
}
