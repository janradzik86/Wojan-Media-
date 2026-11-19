part of 'video_studio.dart';

/// FotoPlay-style editing toolbar under the live preview. Every tool opens a
/// bottom sheet whose content rebuilds on each edit (it listens to the
/// preview controller, which is notified after every change), so the
/// preview above updates in real time while the user adjusts things.
extension _EditorTools on _VideoStudioScreenState {
  void _refresh([VoidCallback? f]) => _edit(f ?? () {});

  Widget _toolStrip() {
    Widget b(IconData icon, String label, VoidCallback onTap, {Key? key}) => InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 66,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 24),
                const SizedBox(height: 3),
                Text(label, style: const TextStyle(fontSize: 10.5), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
        );
    return SizedBox(
      height: 62,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        b(Icons.content_cut, 'Edytuj', _sheetEdit, key: const Key('tool_edit')),
        b(Icons.music_note, 'Muzyka', _sheetMusic, key: const Key('tool_music')),
        b(Icons.movie_filter, 'Wstęp', _sheetIntro, key: const Key('tool_intro')),
        b(Icons.auto_awesome, 'Efekt', () => _sheetEffects(), key: const Key('tool_fx')),
        b(Icons.crop_square, 'Rama', () => _sheetEffects(onlyCategory: 'Ramki'), key: const Key('tool_frame')),
        b(Icons.text_fields, 'Tekst', _sheetText, key: const Key('tool_text')),
        b(Icons.emoji_emotions, 'Naklejka', _sheetStickers, key: const Key('tool_sticker')),
        b(Icons.picture_in_picture, 'PIP', _addPip, key: const Key('tool_pip')),
        b(Icons.aspect_ratio, 'Proporcja', _sheetRatio, key: const Key('tool_ratio')),
        b(Icons.wallpaper, 'Tło', _sheetBackground, key: const Key('tool_bg')),
        b(Icons.filter_vintage, 'Filtr', _sheetFilter, key: const Key('tool_filter')),
        b(Icons.tune, 'Reguluj', _sheetAdjust, key: const Key('tool_adjust')),
        b(Icons.compare_arrows, 'Przejście', _sheetTransition, key: const Key('tool_transition')),
        b(Icons.equalizer, 'Spektrum', _sheetVisualizer, key: const Key('tool_vis')),
        b(Icons.subtitles, 'Napisy', _sheetSubtitles, key: const Key('tool_subs')),
        b(Icons.layers, 'Warstwa', _sheetLayers, key: const Key('tool_layers')),
      ]),
    );
  }

  double get _t => pc?.position ?? 0;

  /// Index of the clip under the playhead (or the selected one).
  int _clipAtPlayhead() {
    if (selKind == _SelKind.clip && sel >= 0 && sel < p.clips.length) return sel;
    final st = p.clipStarts();
    var i = 0;
    for (var k = 0; k < st.length; k++) {
      if (_t >= st[k]) i = k;
    }
    return p.clips.isEmpty ? -1 : i;
  }

  Future<void> _sheet(String title, Widget Function(BuildContext ctx) body, {double height = 0.5}) async {
    await pc?.pause();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      barrierColor: Colors.black26,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * height),
      builder: (ctx) => ListenableBuilder(
        listenable: pc!,
        builder: (ctx, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 6), child: Text(title, style: Theme.of(ctx).textTheme.titleMedium)),
          Flexible(child: body(ctx)),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- Edytuj
  void _sheetEdit() {
    _sheet('Edytuj klip', (ctx) {
      final i = _clipAtPlayhead();
      if (i < 0) return const Padding(padding: EdgeInsets.all(16), child: Text('Dodaj najpierw zdjęcia lub klipy wideo.'));
      final c = p.clips[i];
      final st = p.clipStarts()[i];
      Widget act(IconData ic, String l, VoidCallback f) => ActionChip(avatar: Icon(ic, size: 18), label: Text(l), onPressed: f);
      return ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        Text('Klip ${i + 1} z ${p.clips.length} • ${c.duration.toStringAsFixed(2)} s', style: const TextStyle(color: WmsColors.muted)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          act(Icons.content_cut, 'Podziel w miejscu głowicy', () {
            final rel = _t - st;
            if (rel <= 0.1 || rel >= c.duration - 0.1) {
              toast(context, 'Ustaw głowicę wewnątrz klipu (min. 0,1 s od krawędzi).');
              return;
            }
            _refresh(() => p.splitClip(i, rel)); // split keeps the total length
          }),
          act(Icons.copy, 'Duplikuj', () => _refresh(() {
                p.duplicateClip(i);
                _refitAudio();
              })),
          act(Icons.delete_outline, 'Usuń', () {
            _refresh(() {
              p.clips.removeAt(i);
              sel = -1;
              _refitAudio();
            });
            Navigator.pop(ctx);
          }),
          act(Icons.rotate_right, 'Obróć 90°', () => _refresh(() => c.rotate = (c.rotate + 90) % 360)),
          act(Icons.flip, 'Odbij poziomo', () => _refresh(() => c.flipH = !c.flipH)),
          act(Icons.flip, 'Odbij pionowo', () => _refresh(() => c.flipV = !c.flipV)),
          if (i > 0) act(Icons.arrow_back, 'Przesuń w lewo', () => _refresh(() => p.moveClip(i, i - 1))),
          if (i < p.clips.length - 1) act(Icons.arrow_forward, 'Przesuń w prawo', () => _refresh(() => p.moveClip(i, i + 1))),
        ]),
        const SizedBox(height: 8),
        if (c.kind != ClipKind.video) LabeledSlider(label: 'Czas trwania', value: c.imageDuration, min: 0.3, max: math.max(60.0, math.max(p.audioDuration, c.imageDuration)), unit: 's', decimals: 1, onChanged: (v) => _refresh(() => c.imageDuration = v)),
        if (c.kind == ClipKind.video) ...[
          LabeledSlider(label: 'Prędkość', value: c.speed, min: 0.25, max: 4, unit: '×', decimals: 2, onChanged: (v) => _refresh(() => c.speed = v)),
          Wrap(spacing: 6, children: [
            FilterChip(label: const Text('Wycisz'), selected: c.mute, onSelected: (v) => _refresh(() => c.mute = v)),
            FilterChip(label: const Text('Odwróć (rewers)'), selected: c.reverse, onSelected: (v) => _refresh(() => c.reverse = v)),
            FilterChip(label: const Text('Zapętl'), selected: c.loopVideo, onSelected: (v) => _refresh(() => c.loopVideo = v)),
          ]),
          LabeledSlider(label: 'Głośność klipu', value: c.volumeDb, min: -30, max: 12, unit: 'dB', onChanged: (v) => _refresh(() => c.volumeDb = v)),
        ],
        const Text('Dopasowanie kadru', style: TextStyle(fontWeight: FontWeight.w600)),
        Wrap(spacing: 6, children: [
          for (final f in FitMode.values)
            ChoiceChip(
              label: Text(const {FitMode.cover: 'Wypełnij', FitMode.contain: 'Dopasuj (pasy)', FitMode.blurBackground: 'Rozmyte tło', FitMode.stretch: 'Rozciągnij'}[f]!),
              selected: c.fit == f,
              onSelected: (_) => _refresh(() => c.fit = f),
            ),
        ]),
        const SizedBox(height: 6),
        const Text('Ruch kamery', style: TextStyle(fontWeight: FontWeight.w600)),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final m in MotionPreset.values) ChoiceChip(label: Text(motionNames[m]!, style: const TextStyle(fontSize: 11)), selected: c.motion.preset == m, onSelected: (_) => _refresh(() => c.motion = Motion(preset: m, intensity: c.motion.intensity))),
        ]),
        LabeledSlider(label: 'Siła ruchu', value: c.motion.intensity, min: 0, max: 1, decimals: 2, onChanged: (v) => _refresh(() => c.motion.intensity = v)),
        const Text('Animacja wejścia', style: TextStyle(fontWeight: FontWeight.w600)),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final e in inOutAnimNames.entries) ChoiceChip(label: Text(e.value, style: const TextStyle(fontSize: 11)), selected: c.animIn == e.key, onSelected: (_) => _refresh(() => c.animIn = e.key)),
        ]),
        const SizedBox(height: 16),
      ]);
    }, height: 0.6);
  }

  // ---------------------------------------------------------------- Muzyka
  AudioClip? get _musicClip => p.audio.tracks.isEmpty ? null : p.audio.tracks.expand((t) => t.clips).where((c) => c.assetId == p.musicAssetId).firstOrNull ?? p.audio.tracks.first.clips.firstOrNull;

  void _sheetMusic() {
    _sheet('Muzyka', (ctx) {
      final m = _musicClip;
      Widget big(IconData ic, String l, VoidCallback f, {Key? key}) => Expanded(
            child: InkWell(
              key: key,
              onTap: f,
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Column(children: [Icon(ic, size: 30, color: WmsColors.accent), const SizedBox(height: 4), Text(l, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))])),
            ),
          );
      return ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        Row(children: [
          big(Icons.library_music, 'Muzyka\nz projektu', () => _pickProjectMusic(ctx)),
          big(Icons.folder_open, 'Muzyka\nlokalna', () async {
            Navigator.pop(ctx);
            await _addMusic();
          }),
          big(Icons.movie, 'Wyodrębnij\nz wideo', () async {
            Navigator.pop(ctx);
            await _extractAudioFromVideo();
          }),
          big(recording ? Icons.stop_circle : Icons.mic, recording ? 'Zatrzymaj\nnagrywanie' : 'Nagrywanie\n(lektor)', () async {
            Navigator.pop(ctx);
            if (!recording) recordAt = _t;
            await _toggleVoiceover();
          }),
        ]),
        const Divider(),
        if (m == null) const Padding(padding: EdgeInsets.all(8), child: Text('Brak muzyki w projekcie.')),
        if (m != null) ...[
          Text(doc!.assets[m.assetId]?.name ?? 'Muzyka', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('Na osi: ${fmtTime(m.position)} – ${fmtTime(m.end)}', style: const TextStyle(color: WmsColors.muted, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ActionChip(avatar: const Icon(Icons.content_cut, size: 18), label: const Text('Rozdziel'), onPressed: () => _splitAudio(m)),
            ActionChip(avatar: const Icon(Icons.copy, size: 18), label: const Text('Duplikat'), onPressed: () => _refresh(() {
                  final t = p.audio.tracks.firstWhere((t) => t.clips.contains(m));
                  t.clips.add(m.copy()..position = m.end);
                })),
            ActionChip(avatar: const Icon(Icons.av_timer, size: 18), label: const Text('Beat-sync (cięcia w rytm)'), onPressed: _snapCutsToBeats),
            ActionChip(avatar: const Icon(Icons.straighten, size: 18), label: const Text('Dostosuj do długości audio'), onPressed: () {
              Navigator.pop(ctx);
              _fitToAudio();
            }),
            ActionChip(avatar: const Icon(Icons.swap_horiz, size: 18), label: const Text('Zastąp'), onPressed: () async {
              Navigator.pop(ctx);
              await _addMusic();
            }),
            ActionChip(avatar: const Icon(Icons.delete_outline, size: 18), label: const Text('Usuń'), onPressed: () {
              _refresh(() {
                for (final t in p.audio.tracks) {
                  t.clips.remove(m);
                }
                if (p.musicAssetId == m.assetId) p.musicAssetId = null;
              });
              music = null;
              pc?.music = null;
            }),
          ]),
          LabeledSlider(label: 'Głośność (Tom)', value: m.gainDb, min: -30, max: 12, unit: 'dB', onChanged: (v) => _refresh(() => m.gainDb = v)),
          LabeledSlider(label: 'Początek w utworze (przytnij)', value: m.srcIn.clamp(0, math.max(0.1, m.srcOut - 0.5)), min: 0, max: math.max(0.1, m.srcOut - 0.5), unit: 's', decimals: 1, onChanged: (v) => _refresh(() => m.srcIn = v)),
          LabeledSlider(label: 'Koniec w utworze', value: m.srcOut, min: math.min(m.srcIn + 0.5, doc!.assets[m.assetId]?.duration ?? m.srcOut), max: doc!.assets[m.assetId]?.duration ?? m.srcOut, unit: 's', decimals: 1, onChanged: (v) => _refresh(() => m.srcOut = v)),
          LabeledSlider(label: 'Pozycja na osi czasu', value: m.position, min: 0, max: math.max(1, p.visualDuration), unit: 's', decimals: 1, onChanged: (v) => _refresh(() => m.position = v)),
          LabeledSlider(label: 'Pojawianie (fade in)', value: m.fadeIn, min: 0, max: 10, unit: 's', decimals: 1, onChanged: (v) => _refresh(() => m.fadeIn = v)),
          LabeledSlider(label: 'Wyciszanie (fade out)', value: m.fadeOut, min: 0, max: 10, unit: 's', decimals: 1, onChanged: (v) => _refresh(() => m.fadeOut = v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Wycisz muzykę'), value: m.muted, onChanged: (v) => _refresh(() => m.muted = v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Dźwięk oryginalny z klipów wideo'), value: p.clipAudio, onChanged: (v) => _refresh(() => p.clipAudio = v)),
        ],
        const SizedBox(height: 16),
      ]);
    }, height: 0.7);
  }

  void _splitAudio(AudioClip m) {
    final rel = _t - m.position;
    final len = m.end - m.position;
    if (rel <= 0.1 || rel >= len - 0.1) {
      toast(context, 'Ustaw głowicę wewnątrz utworu.');
      return;
    }
    _refresh(() {
      final t = p.audio.tracks.firstWhere((t) => t.clips.contains(m));
      final right = m.copy();
      final srcCut = m.srcIn + rel * m.tempo;
      right
        ..srcIn = srcCut
        ..position = m.position + rel
        ..fadeIn = 0;
      m
        ..srcOut = srcCut
        ..fadeOut = 0;
      t.clips.insert(t.clips.indexOf(m) + 1, right);
    });
  }

  Future<void> _pickProjectMusic(BuildContext ctx) async {
    final audio = doc!.assets.values.where((a) => a.kind == MediaKind.audio).toList();
    if (audio.isEmpty) {
      toast(context, 'W projekcie nie ma jeszcze plików audio – użyj „Muzyka lokalna”.');
      return;
    }
    final a = await showDialog<MediaAsset>(context: ctx, builder: (c) => SimpleDialog(title: const Text('Muzyka z projektu'), children: [for (final x in audio) SimpleDialogOption(onPressed: () => Navigator.pop(c, x), child: Text('${x.name}  (${fmtTime(x.duration)})'))]));
    if (a == null) return;
    _refresh(() {
      p.audio.tracks.first.clips
        ..clear()
        ..add(AudioClip(assetId: a.id, srcIn: 0, srcOut: a.duration, fadeOut: 1.5));
      p.musicAssetId = a.id;
    });
    _loadMusic();
  }

  /// "Wyodrębnij" – takes the sound track of a video file as music.
  Future<void> _extractAudioFromVideo() async {
    final v = await importMedia(context, videoExt, multiple: false);
    if (v.isEmpty || !mounted) return;
    if (!v.first.hasAudio) {
      toast(context, 'Ten plik wideo nie ma ścieżki dźwiękowej.', error: true);
      return;
    }
    final out = '${Services.i.store.cacheDir.path}/extract_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await Services.i.runner.ffmpeg(['-i', resolver.pathOf(v.first.id), '-vn', '-c:a', 'aac', '-b:a', '192k', out]);
      final a = await Services.i.store.importMedia(out, displayName: '${v.first.name} (audio).m4a');
      _refresh(() {
        doc!.assets[a.id] = a;
        p.audio.tracks.first.clips
          ..clear()
          ..add(AudioClip(assetId: a.id, srcIn: 0, srcOut: a.duration, fadeOut: 1.5));
        p.musicAssetId = a.id;
      });
      _loadMusic();
      if (mounted) toast(context, 'Dźwięk wyodrębniony z wideo.');
    } catch (e) {
      if (mounted) toast(context, 'Nie udało się wyodrębnić dźwięku: $e', error: true);
    }
  }

  // ---------------------------------------------------------------- Wstęp
  void _sheetIntro() {
    final ctl = TextEditingController(text: doc!.name.startsWith('Film ') ? 'Mój film' : doc!.name);
    final sub = TextEditingController();
    _sheet('Wstęp (intro)', (ctx) {
      final hasIntro = p.clips.isNotEmpty && p.clips.first.label == introTag || p.texts.any((t) => t.layer == 90);
      return ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        TextField(controller: ctl, decoration: const InputDecoration(labelText: 'Tytuł')),
        TextField(controller: sub, decoration: const InputDecoration(labelText: 'Podtytuł (opcjonalnie – inaczej domyślny dla motywu)')),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: MediaQuery.sizeOf(ctx).width > 700 ? 6 : 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.72,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final ip in introPresets)
              InkWell(
                key: Key('intro_${ip.id}'),
                onTap: () {
                  _refresh(() => applyIntro(p, ip, ctl.text.trim().isEmpty ? 'Tytuł' : ctl.text.trim(), subtitle: sub.text.trim().isEmpty ? null : sub.text.trim()));
                  pc?.seek(0);
                  pc?.play();
                },
                child: Column(children: [
                  Expanded(child: _FxThumb(project: p, types: ip.vfx, background: ip.background.isEmpty ? null : ip.background, assets: resolver, title: ctl.text, titleFont: ip.font, titleColor: ip.color)),
                  const SizedBox(height: 3),
                  Text(ip.name, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
          ],
        ),
        if (hasIntro) TextButton.icon(onPressed: () => _refresh(() => removeIntro(p)), icon: const Icon(Icons.delete_outline), label: const Text('Usuń wstęp')),
        const SizedBox(height: 16),
      ]);
    }, height: 0.75);
  }

  // ---------------------------------------------------------------- Efekt / Rama
  void _sheetEffects({String? onlyCategory}) {
    var whole = onlyCategory == 'Ramki';
    var cat = onlyCategory ?? vfxCategories.keys.first;
    var intensity = 0.7;
    _sheet(onlyCategory == null ? 'Efekty' : 'Ramy', (ctx) {
      return StatefulBuilder(builder: (ctx, setS) {
        final items = vfxCategories[cat]!;
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (onlyCategory == null)
            SizedBox(
              height: 40,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                for (final k in vfxCategories.keys) Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(k), selected: k == cat, onSelected: (_) => setS(() => cat = k))),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
              FilterChip(label: const Text('Na cały film'), selected: whole, onSelected: (v) => setS(() => whole = v)),
              Text(whole ? 'efekt na całej długości' : 'od głowicy (${fmtTime(_t)}) przez 4 s', style: const TextStyle(fontSize: 12, color: WmsColors.muted)),
              SizedBox(width: 200, child: Slider(value: intensity, min: 0.1, max: 1, onChanged: (v) => setS(() => intensity = v))),
            ]),
          ),
          Flexible(
            child: GridView.extent(
              maxCrossAxisExtent: 110,
              padding: const EdgeInsets.all(12),
              childAspectRatio: 0.68,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final id in items)
                  InkWell(
                    key: Key('fx_$id'),
                    onTap: () {
                      final start = whole ? 0.0 : _t;
                      final dur = whole ? 0.0 : math.max(0.5, math.min(4.0, p.duration - start));
                      _refresh(() {
                        p.vfx.add(VfxItem(type: id, start: start, duration: dur, intensity: intensity, reactive: reactiveCapable.contains(id) && music != null));
                        selKind = _SelKind.vfx;
                        sel = p.vfx.length - 1;
                      });
                      toast(context, 'Dodano: ${allVfxNames[id]}');
                    },
                    child: Column(children: [
                      Expanded(child: _FxThumb(project: p, types: [id], assets: resolver, intensity: intensity)),
                      const SizedBox(height: 3),
                      Text(allVfxNames[id] ?? id, style: const TextStyle(fontSize: 10.5), maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
              ],
            ),
          ),
          if (p.vfx.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                const Text('W projekcie: ', style: TextStyle(color: WmsColors.muted)),
                for (var k = 0; k < p.vfx.length; k++)
                  InputChip(
                    label: Text('${allVfxNames[p.vfx[k].type] ?? p.vfx[k].type} ${p.vfx[k].duration > 0 ? '${fmtTime(p.vfx[k].start)}+${p.vfx[k].duration.toStringAsFixed(1)}s' : '(cały)'}', style: const TextStyle(fontSize: 11)),
                    onPressed: () => pc?.seek(p.vfx[k].start),
                    onDeleted: () => _refresh(() => p.vfx.removeAt(k)),
                  ),
              ]),
            ),
        ]);
      });
    }, height: 0.75);
  }

  // ---------------------------------------------------------------- Tekst
  void _sheetText() {
    final existing = selKind == _SelKind.text && sel >= 0 && sel < p.texts.length ? p.texts[sel] : null;
    final t = existing ?? TextItem(text: 'Twój tekst', start: _t, duration: math.max(1.5, math.min(4, p.duration - _t)), style: TextStyleSpec(align: 'center'));
    if (existing == null) {
      _refresh(() {
        p.texts.add(t);
        selKind = _SelKind.text;
        sel = p.texts.length - 1;
      });
    }
    final ctl = TextEditingController(text: t.text);
    _sheet('Tekst', (ctx) {
      return ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        TextField(key: const Key('text_field'), controller: ctl, maxLines: 3, minLines: 1, decoration: const InputDecoration(labelText: 'Treść (polskie znaki: ąćęłńóśźż)'), onChanged: (v) => _refresh(() => t.text = v)),
        const SizedBox(height: 8),
        const Text('Czcionka', style: TextStyle(fontWeight: FontWeight.w600)),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final f in [...fontFamilies, ...userFonts()])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text('Aa $f', style: TextStyle(fontFamily: PreviewFonts.has(f) ? f : null)), selected: t.style.font == f, onSelected: (_) => _refresh(() => t.style.font = f)),
              ),
          ]),
        ),
        const Text('Kolor', style: TextStyle(fontWeight: FontWeight.w600)),
        ColorDots(value: t.style.color, onChanged: (v) => _refresh(() => t.style.color = v)),
        const SizedBox(height: 6),
        const Text('Animacja', style: TextStyle(fontWeight: FontWeight.w600)),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final e in textAnimNames.entries)
            ChoiceChip(
              label: Text(e.value, style: const TextStyle(fontSize: 11)),
              selected: t.anim == e.key,
              onSelected: (_) {
                _refresh(() => t.anim = e.key);
                pc?.seek(t.start);
                pc?.play();
              },
            ),
        ]),
        Wrap(spacing: 6, children: [
          for (final a in const {'top': 'Góra', 'center': 'Środek', 'bottom': 'Dół'}.entries)
            ChoiceChip(label: Text(a.value), selected: t.x < 0 && t.style.align == a.key, onSelected: (_) => _refresh(() {
                  t.style.align = a.key;
                  t.x = -1;
                  t.y = -1;
                })),
          FilterChip(label: const Text('Tło pod tekstem'), selected: t.style.box, onSelected: (v) => _refresh(() => t.style.box = v)),
          FilterChip(label: const Text('Gradient'), selected: t.style.gradientTo != null, onSelected: (v) => _refresh(() => t.style.gradientTo = v ? '#FFD400' : null)),
        ]),
        LabeledSlider(label: 'Rozmiar', value: t.style.size, min: 16, max: 240, onChanged: (v) => _refresh(() => t.style.size = v)),
        LabeledSlider(label: 'Obrys', value: t.style.outline, min: 0, max: 12, decimals: 1, onChanged: (v) => _refresh(() => t.style.outline = v)),
        LabeledSlider(label: 'Cień', value: t.style.shadow, min: 0, max: 12, decimals: 1, onChanged: (v) => _refresh(() => t.style.shadow = v)),
        LabeledSlider(label: 'Start', value: t.start.clamp(0, math.max(0.1, p.duration)), min: 0, max: math.max(0.1, p.duration), unit: 's', decimals: 1, onChanged: (v) => _refresh(() => t.start = v)),
        LabeledSlider(label: 'Czas trwania', value: t.duration.clamp(0.3, 60), min: 0.3, max: 60, unit: 's', decimals: 1, onChanged: (v) => _refresh(() => t.duration = v)),
        TextButton.icon(onPressed: () {
          _refresh(() {
            p.texts.remove(t);
            sel = -1;
          });
          Navigator.pop(ctx);
        }, icon: const Icon(Icons.delete_outline), label: const Text('Usuń tekst')),
        const SizedBox(height: 16),
      ]);
    }, height: 0.7);
  }

  // ---------------------------------------------------------------- Naklejka
  static const _stickers = <String, List<String>>{
    'Miłość': ['❤️', '💖', '💕', '💘', '😍', '😘', '🥰', '💋', '🌹', '💍', '💐', '🫶'],
    'Emocje': ['😀', '😂', '🤣', '😎', '🤩', '😱', '😭', '😡', '🥳', '🤔', '😴', '👍', '👏', '🙌', '🔥', '💯'],
    'Uroczystość': ['🎉', '🎊', '🎂', '🎁', '🎈', '🥂', '🍾', '🏆', '🥇', '👑', '✨', '🌟'],
    'Natura': ['🌸', '🌼', '🌻', '🍀', '🍁', '🌈', '☀️', '🌙', '⭐', '❄️', '⚡', '🌊', '🦋', '🐶', '🐱'],
    'Podróże': ['✈️', '🚗', '🏖️', '⛰️', '🗺️', '📸', '🎒', '🏝️', '🇵🇱'],
    'Muzyka': ['🎵', '🎶', '🎤', '🎧', '🎸', '🥁', '🎹', '🎺', '📻'],
  };

  void _sheetStickers() {
    _sheet('Naklejki', (ctx) {
      return ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
        for (final g in _stickers.entries) ...[
          Padding(padding: const EdgeInsets.only(top: 6, bottom: 4), child: Text(g.key, style: const TextStyle(fontWeight: FontWeight.w600))),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final e in g.value)
              InkWell(
                onTap: () => _addSticker(e),
                child: SizedBox(width: 48, height: 48, child: Center(child: Text(e, style: const TextStyle(fontSize: 32)))),
              ),
          ]),
        ],
        const SizedBox(height: 16),
      ]);
    }, height: 0.6);
  }

  /// Rasterises an emoji with the system emoji font to a transparent PNG
  /// (so the export engine renders exactly what the user picked).
  Future<void> _addSticker(String emoji) async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final tp = TextPainter(text: TextSpan(text: emoji, style: const TextStyle(fontSize: 400)), textDirection: TextDirection.ltr)..layout();
    final w = tp.width.ceil().clamp(16, 1024), h = tp.height.ceil().clamp(16, 1024);
    tp.paint(canvas, Offset.zero);
    final img = await rec.endRecording().toImage(w, h);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return;
    final path = '${Services.i.store.cacheDir.path}/sticker_${emoji.runes.map((r) => r.toRadixString(16)).join('_')}.png';
    await File(path).writeAsBytes(png.buffer.asUint8List());
    final a = await Services.i.store.importMedia(path, displayName: 'Naklejka $emoji.png');
    _refresh(() {
      doc!.assets[a.id] = a;
      p.overlays.add(OverlayItem(assetId: a.id, name: 'Naklejka $emoji', start: _t, duration: math.max(1, math.min(3, p.duration - _t)), scale: 0.25, animIn: 'pop', animOut: 'fade', mute: true));
      selKind = _SelKind.overlay;
      sel = p.overlays.length - 1;
    });
    if (mounted) toast(context, 'Dodano naklejkę $emoji – przesuń ją w Inspektorze (X/Y) lub zmień rozmiar.');
  }

  Future<void> _addPip() async {
    final a = await importMedia(context, [...imageExt, ...videoExt], multiple: false);
    if (a.isEmpty) return;
    _refresh(() {
      doc!.assets[a.first.id] = a.first;
      final d = a.first.kind == MediaKind.video ? a.first.duration : 4.0;
      p.overlays.add(OverlayItem(assetId: a.first.id, name: 'PIP ${a.first.name}', start: _t, duration: math.max(1, math.min(d, math.max(1, p.duration - _t))), x: 0.72, y: 0.25, scale: 0.4, borderWidth: 4, borderColor: '#FFFFFF', animIn: 'pop', mute: true));
      selKind = _SelKind.overlay;
      sel = p.overlays.length - 1;
    });
  }

  // ---------------------------------------------------------------- Proporcja / Tło
  void _sheetRatio() {
    _sheet('Proporcja obrazu', (ctx) => ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in formatPresets.entries)
              ChoiceChip(
                label: Text('${e.key}\n${e.value.$1}×${e.value.$2}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                selected: p.width == e.value.$1 && p.height == e.value.$2,
                onSelected: (_) => _refresh(() {
                  p.width = e.value.$1;
                  p.height = e.value.$2;
                }),
              ),
          ]),
          const SizedBox(height: 16),
        ]));
  }

  void _sheetBackground() {
    _sheet('Tło', (ctx) => ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          const Text('Dopasowanie wszystkich zdjęć i klipów (bez zniekształcania obrazu):'),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            ActionChip(avatar: const Icon(Icons.blur_on, size: 18), label: const Text('Rozmyte tło'), onPressed: () => _refresh(() => [for (final c in p.clips) c.fit = FitMode.blurBackground])),
            ActionChip(avatar: const Icon(Icons.fit_screen, size: 18), label: const Text('Dopasuj (kolor tła)'), onPressed: () => _refresh(() => [for (final c in p.clips) c.fit = FitMode.contain])),
            ActionChip(avatar: const Icon(Icons.crop, size: 18), label: const Text('Wypełnij kadr'), onPressed: () => _refresh(() => [for (final c in p.clips) c.fit = FitMode.cover])),
          ]),
          const SizedBox(height: 10),
          const Text('Kolor tła'),
          ColorDots(value: p.background, onChanged: (v) => _refresh(() => p.background = v)),
          const SizedBox(height: 16),
        ]));
  }

  // ---------------------------------------------------------------- Filtr / Reguluj
  ColorGrade _gradeTarget(bool clipOnly) {
    final i = _clipAtPlayhead();
    return clipOnly && i >= 0 ? p.clips[i].grade : p.globalGrade;
  }

  void _sheetFilter() {
    var clipOnly = false;
    _sheet('Filtr', (ctx) => StatefulBuilder(builder: (ctx, setS) {
          final g = _gradeTarget(clipOnly);
          final i = _clipAtPlayhead();
          final c = i >= 0 ? p.clips[i] : null;
          Widget thumb(String look) {
            final m = gradeMatrix(ColorGrade(filter: look, filterStrength: 1));
            Widget img = c == null || c.kind == ClipKind.color || c.assetId == null ? Container(color: WmsColors.accent2) : ClipThumb(path: resolver.pathOf(c.assetId!), at: c.isVideo ? c.srcIn + 0.3 : 0, size: 96);
            if (m != null) img = ColorFiltered(colorFilter: ColorFilter.matrix(m), child: img);
            return ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 72, height: 96, child: img));
          }

          return ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('Cały film'), selected: !clipOnly, onSelected: (_) => setS(() => clipOnly = false)),
              ChoiceChip(label: Text('Tylko klip ${i + 1}'), selected: clipOnly, onSelected: i < 0 ? null : (_) => setS(() => clipOnly = true)),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 128,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final e in [const MapEntry('', 'Brak'), ...lookNames.entries])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => _refresh(() {
                        g.filter = e.key;
                        if (g.filterStrength <= 0) g.filterStrength = 1;
                      }),
                      child: Column(children: [
                        Container(decoration: BoxDecoration(border: Border.all(color: g.filter == e.key ? WmsColors.accent : Colors.transparent, width: 2), borderRadius: BorderRadius.circular(10)), child: thumb(e.key)),
                        Text(e.value, style: const TextStyle(fontSize: 10.5)),
                      ]),
                    ),
                  ),
              ]),
            ),
            if (g.filter.isNotEmpty) LabeledSlider(label: 'Siła filtra', value: g.filterStrength, min: 0, max: 1, decimals: 2, onChanged: (v) => _refresh(() => g.filterStrength = v)),
            const SizedBox(height: 16),
          ]);
        }), height: 0.5);
  }

  void _sheetAdjust() {
    var clipOnly = false;
    _sheet('Reguluj', (ctx) => StatefulBuilder(builder: (ctx, setS) {
          final g = _gradeTarget(clipOnly);
          final i = _clipAtPlayhead();
          return ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('Cały film'), selected: !clipOnly, onSelected: (_) => setS(() => clipOnly = false)),
              ChoiceChip(label: Text('Tylko klip ${i + 1}'), selected: clipOnly, onSelected: i < 0 ? null : (_) => setS(() => clipOnly = true)),
              TextButton(onPressed: () => _refresh(() {
                final n = ColorGrade();
                g
                  ..brightness = n.brightness
                  ..contrast = n.contrast
                  ..saturation = n.saturation
                  ..exposure = n.exposure
                  ..temperature = n.temperature
                  ..tint = n.tint
                  ..hue = n.hue
                  ..vignette = n.vignette
                  ..sharpness = n.sharpness
                  ..grain = n.grain;
              }), child: const Text('Resetuj')),
            ]),
            LabeledSlider(label: 'Jasność', value: g.brightness, min: -0.5, max: 0.5, decimals: 2, onChanged: (v) => _refresh(() => g.brightness = v)),
            LabeledSlider(label: 'Kontrast', value: g.contrast, min: 0.5, max: 2, decimals: 2, onChanged: (v) => _refresh(() => g.contrast = v)),
            LabeledSlider(label: 'Nasycenie', value: g.saturation, min: 0, max: 2.5, decimals: 2, onChanged: (v) => _refresh(() => g.saturation = v)),
            LabeledSlider(label: 'Ekspozycja', value: g.exposure, min: -2, max: 2, unit: 'EV', decimals: 2, onChanged: (v) => _refresh(() => g.exposure = v)),
            LabeledSlider(label: 'Temperatura', value: g.temperature, min: 2500, max: 11000, unit: 'K', onChanged: (v) => _refresh(() => g.temperature = v)),
            LabeledSlider(label: 'Odcień (tint)', value: g.tint, min: -1, max: 1, decimals: 2, onChanged: (v) => _refresh(() => g.tint = v)),
            LabeledSlider(label: 'Barwa (hue)', value: g.hue, min: -180, max: 180, unit: '°', onChanged: (v) => _refresh(() => g.hue = v)),
            LabeledSlider(label: 'Ostrość', value: g.sharpness, min: -2, max: 5, decimals: 1, onChanged: (v) => _refresh(() => g.sharpness = v)),
            LabeledSlider(label: 'Winieta', value: g.vignette, min: 0, max: 1, decimals: 2, onChanged: (v) => _refresh(() => g.vignette = v)),
            LabeledSlider(label: 'Ziarno', value: g.grain, min: 0, max: 1, decimals: 2, onChanged: (v) => _refresh(() => g.grain = v)),
            const SizedBox(height: 16),
          ]);
        }), height: 0.6);
  }

  // ---------------------------------------------------------------- Przejście
  void _sheetTransition() {
    _sheet('Przejścia', (ctx) {
      final i = _clipAtPlayhead();
      final c = i >= 0 && i < p.clips.length - 1 ? p.clips[i] : null;
      return ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        Text(c == null ? 'Wybierz klip (nie ostatni), aby ustawić przejście do następnego. Możesz też zastosować przejście do wszystkich.' : 'Przejście: klip ${i + 1} → ${i + 2}', style: const TextStyle(color: WmsColors.muted)),
        const SizedBox(height: 6),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final e in transitionNames.entries)
            ChoiceChip(
              label: Text(e.value, style: const TextStyle(fontSize: 11)),
              selected: c?.transition.type == e.key,
              onSelected: c == null
                  ? null
                  : (_) {
                      _refresh(() => c.transition.type = e.key);
                      final st = p.clipStarts();
                      pc?.seek(math.max(0, st[i + 1] - 0.6));
                      pc?.play();
                    },
            ),
        ]),
        if (c != null) LabeledSlider(label: 'Długość przejścia', value: c.transition.duration.clamp(0.1, 3), min: 0.1, max: 3, unit: 's', decimals: 2, onChanged: (v) => _refresh(() => c.transition.duration = v)),
        Wrap(spacing: 6, children: [
          if (c != null) ActionChip(label: const Text('Zastosuj do wszystkich'), onPressed: () => _refresh(() => p.applyTransitionToAll(c.transition.type, c.transition.duration))),
          ActionChip(label: const Text('Losowe przejścia'), onPressed: () => _refresh(() {
                final keys = transitionNames.keys.where((k) => k != 'cut').toList();
                final r = math.Random();
                for (var k = 0; k < p.clips.length - 1; k++) {
                  p.clips[k].transition.type = keys[r.nextInt(keys.length)];
                  if (p.clips[k].transition.duration < 0.2) p.clips[k].transition.duration = 0.6;
                }
              })),
          ActionChip(label: const Text('Bez przejść (cięcia)'), onPressed: () => _refresh(() => p.applyTransitionToAll('cut', 0))),
        ]),
        const SizedBox(height: 16),
      ]);
    }, height: 0.6);
  }

  // ---------------------------------------------------------------- Spektrum / Napisy / Warstwa
  void _sheetVisualizer() {
    _sheet('Spektrum audio / wizualizator', (ctx) => ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          if (music == null) const Text('Wskazówka: dodaj muzykę – wizualizator reaguje na prawdziwy sygnał audio.', style: TextStyle(color: WmsColors.warn)),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in visualizerNames.entries)
              ActionChip(
                label: Text(e.value),
                onPressed: () => _refresh(() {
                  final round = e.key == 'circle' || e.key == 'oscilloscope';
                  p.visualizers.add(VisualizerItem(style: e.key, x: round ? 0.15 : 0, y: round ? 0.3 : 0.7, width: round ? 0.7 : 1, height: round ? 0.4 : 0.25));
                  selKind = _SelKind.vis;
                  sel = p.visualizers.length - 1;
                }),
              ),
          ]),
          for (var k = 0; k < p.visualizers.length; k++)
            ListTile(
              dense: true,
              title: Text(visualizerNames[p.visualizers[k].style] ?? ''),
              subtitle: ColorDots(value: p.visualizers[k].color, onChanged: (v) => _refresh(() => p.visualizers[k].color = v)),
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _refresh(() => p.visualizers.removeAt(k))),
            ),
          const SizedBox(height: 16),
        ]));
  }

  void _sheetSubtitles() {
    _sheet('Napisy i tekst piosenki', (ctx) => ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          Wrap(spacing: 8, runSpacing: 6, children: [
            ActionChip(avatar: const Icon(Icons.file_open, size: 18), label: const Text('Importuj SRT / VTT / LRC'), onPressed: () async {
              final f = await pickFiles(extensions: subExt, multiple: false);
              if (f.isEmpty) return;
              final t = LyricsTrack.parse(await File(f.first).readAsString(), ext: extOf(f.first));
              _refresh(() => p.lyrics = t
                ..mode = t.mode == LyricsMode.karaoke ? LyricsMode.karaoke : LyricsMode.subtitles
                ..style = TextStyleSpec(size: 52).toJson());
            }),
            ActionChip(avatar: const Icon(Icons.edit_note, size: 18), label: const Text('Wpisz tekst i zsynchronizuj (Lyrics Studio)'), onPressed: () {
              Navigator.pop(ctx);
              _save().then((_) => Nav.go('m.lyric'));
            }),
          ]),
          if (p.lyrics != null) ...[
            const SizedBox(height: 8),
            Text('${p.lyrics!.lines.length} wersów', style: const TextStyle(color: WmsColors.muted)),
            Wrap(spacing: 6, children: [
              for (final m in LyricsMode.values)
                ChoiceChip(label: Text(const {LyricsMode.subtitles: 'Napisy', LyricsMode.lyric: 'Lyric video', LyricsMode.karaoke: 'Karaoke', LyricsMode.scroll: 'Przewijany'}[m]!), selected: p.lyrics!.mode == m, onSelected: (_) => _refresh(() => p.lyrics!.mode = m)),
            ]),
            TextButton.icon(onPressed: () => _refresh(() => p.lyrics = null), icon: const Icon(Icons.delete_outline), label: const Text('Usuń napisy')),
          ],
          const SizedBox(height: 16),
        ]));
  }

  void _sheetLayers() {
    _sheet('Warstwy', (ctx) {
      final rows = <Widget>[];
      for (var k = 0; k < p.overlays.length; k++) {
        final o = p.overlays[k];
        rows.add(ListTile(
          dense: true,
          leading: const Icon(Icons.image),
          title: Text(o.name.isEmpty ? 'Nakładka' : o.name),
          subtitle: Text('${fmtTime(o.start)} – ${fmtTime(o.end)} • warstwa ${o.layer}'),
          trailing: Wrap(children: [
            IconButton(tooltip: 'Wyżej', icon: const Icon(Icons.arrow_upward), onPressed: () => _refresh(() => o.layer++)),
            IconButton(tooltip: 'Niżej', icon: const Icon(Icons.arrow_downward), onPressed: () => _refresh(() => o.layer--)),
            IconButton(tooltip: o.hidden ? 'Pokaż' : 'Ukryj', icon: Icon(o.hidden ? Icons.visibility_off : Icons.visibility), onPressed: () => _refresh(() => o.hidden = !o.hidden)),
            IconButton(tooltip: 'Usuń', icon: const Icon(Icons.delete_outline), onPressed: () => _refresh(() => p.overlays.removeAt(k))),
          ]),
          onTap: () => _refresh(() {
            selKind = _SelKind.overlay;
            sel = k;
          }),
        ));
      }
      for (var k = 0; k < p.texts.length; k++) {
        final t = p.texts[k];
        rows.add(ListTile(
          dense: true,
          leading: const Icon(Icons.text_fields),
          title: Text(t.text, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${fmtTime(t.start)} – ${fmtTime(t.end)}'),
          trailing: Wrap(children: [
            IconButton(icon: Icon(t.hidden ? Icons.visibility_off : Icons.visibility), onPressed: () => _refresh(() => t.hidden = !t.hidden)),
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _refresh(() => p.texts.removeAt(k))),
          ]),
          onTap: () => _refresh(() {
            selKind = _SelKind.text;
            sel = k;
          }),
        ));
      }
      for (var k = 0; k < p.vfx.length; k++) {
        final v = p.vfx[k];
        rows.add(ListTile(
          dense: true,
          leading: const Icon(Icons.auto_awesome),
          title: Text(allVfxNames[v.type] ?? v.type),
          subtitle: Text(v.duration > 0 ? '${fmtTime(v.start)} – ${fmtTime(v.start + v.duration)}' : 'cały film'),
          trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _refresh(() => p.vfx.removeAt(k))),
          onTap: () => _refresh(() {
            selKind = _SelKind.vfx;
            sel = k;
          }),
        ));
      }
      if (rows.isEmpty) rows.add(const Padding(padding: EdgeInsets.all(16), child: Text('Brak warstw. Dodaj tekst, naklejkę, PIP lub efekt.')));
      return ListView(children: rows);
    }, height: 0.6);
  }
}

/// Animated thumbnail of one or more effects drawn over the current first
/// clip (or a colour card) – the same painters as the live preview.
class _FxThumb extends StatefulWidget {
  final VideoProject project;
  final List<String> types;
  final String? background;
  final AssetResolver assets;
  final double intensity;
  final String? title, titleFont, titleColor;
  const _FxThumb({required this.project, required this.types, required this.assets, this.background, this.intensity = 0.7, this.title, this.titleFont, this.titleColor});
  @override
  State<_FxThumb> createState() => _FxThumbState();
}

class _FxThumbState extends State<_FxThumb> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _t = 0;
  late FxThumbSource _src;
  late List<VfxItem> _items;

  @override
  void initState() {
    super.initState();
    _build();
    _ticker = createTicker((e) {
      if (mounted) setState(() => _t = (e.inMicroseconds / 1e6) % 4);
    })
      ..start();
  }

  void _build() {
    final p = widget.project;
    // thumbnail canvas keeps the film's aspect but at 270 px width
    final w = 270, h = (270 * p.height / p.width).round();
    _src = FxThumbSource(VideoProject(width: w, height: h, fps: 30));
    _items = [for (final t in widget.types) VfxItem(type: t, intensity: widget.intensity)];
    _src.project.vfx.addAll(_items);
  }

  @override
  void didUpdateWidget(covariant _FxThumb old) {
    super.didUpdateWidget(old);
    if (old.types.join() != widget.types.join() || old.intensity != widget.intensity || old.project.width != widget.project.width || old.project.height != widget.project.height) _build();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final first = p.clips.where((c) => c.kind != ClipKind.color && c.assetId != null && c.label != introTag).firstOrNull;
    return AspectRatio(
      aspectRatio: p.width / p.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LayoutBuilder(builder: (ctx, box) {
          final size = box.biggest;
          Widget base = widget.background != null || first == null
              ? Container(color: hexColor(widget.background ?? '#22303A'))
              : ClipThumb(path: widget.assets.pathOf(first.assetId!), at: first.isVideo ? first.srcIn + 0.3 : 0, size: 160);
          base = SizedBox.expand(child: FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox(width: size.width, height: size.height, child: base)));
          base = wrapBaseVfx(base, _src.project, _t, _src, size);
          return Stack(fit: StackFit.expand, children: [
            base,
            for (final fx in _items) IgnorePointer(child: VfxLayer(fx: fx, t: _t, c: _src, size: size)),
            if (widget.title != null && widget.title!.isNotEmpty)
              Center(child: Padding(padding: const EdgeInsets.all(4), child: Text(widget.title!, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontFamily: PreviewFonts.has(widget.titleFont ?? '') ? widget.titleFont : null, color: hexColor(widget.titleColor ?? '#FFFFFF'), fontSize: 13, fontWeight: FontWeight.w700, shadows: const [Shadow(blurRadius: 3)])))),
          ]);
        }),
      ),
    );
  }
}
