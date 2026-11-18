# FEATURE_PARITY_MATRIX

Legenda statusów (§27):
* **PRZETESTOWANE** – działanie potwierdzone rzeczywistym testem automatycznym na prawdziwym FFmpeg (pliki wynikowe sprawdzone FFprobe/dekodowaniem PCM; patrz `reports/TEST_REPORT.md`).
* **WYKONANE** – kod zaimplementowany (silnik + UI), skompilowany; brak testu end-to-end na urządzeniu docelowym.
* **NIEZWERYFIKOWANE** – nie było możliwości wykonania wymaganego testu (brak urządzenia/emulatora/konta).
* **ZABLOKOWANE** – konkretny bloker (opisany).

Źródła: MS = Mstudio (selfcoder.mstudio.mp3editor), FP = FotoPlay (videoeditor.videomaker.slideshow.fotoplay), POL = wymaganie polecenia. Szczegóły źródeł – `RESEARCH_REPORT.md`.
Testy silnika uruchamiano na Linux x64 z FFmpeg 6.1 (aplikacje używają FFmpegKit 8.1.2 – te same filtry). „UI” = ekran Flutter (Windows/Android).

## Studio Audio

| Funkcja | Ref. | Źródło | Implementacja WoJan | Status | Test | Ograniczenia |
|---|---|---|---|---|---|---|
| Import MP3/WAV/FLAC/AAC/M4A/OGG/OPUS/WMA/AIFF/AMR + wideo | MS | opis Play | FFprobe + magazyn SHA-256 (`ProjectStore.importMedia`) | PRZETESTOWANE | audio_test, sync_test | – |
| Import wielu plików, biblioteka, metadane | MS | opis Play | Biblioteka materiałów, `MediaInfoView` | WYKONANE | – | UI nietestowane na urządzeniu |
| Przycinanie / Cutter (fade) | MS | opis Play | `AudioTools.cut`, `AudioProject.trimTo` | PRZETESTOWANE | audio_test | – |
| Wycinanie fragmentu / Omitter | MS | 4PDA | `deleteRange`, `AudioTools.omit` (crossfade) | PRZETESTOWANE | audio_test | – |
| Dzielenie / Splitter | MS | opis Play | `splitAt`, `AudioTools.split` | PRZETESTOWANE | audio_test (edit ops) | – |
| Kopiuj/wklej, powielanie, pętle, zmiana kolejności | POL | – | `copyRange/paste/duplicateRange/loops/reorder` | PRZETESTOWANE | audio_test | – |
| Łączenie / Merger (crossfade) | MS | opis Play | `AudioTools.merge`, `packSequential` | WYKONANE | silnik pośrednio (amix/concat) | – |
| Mikser / wielościeżkowość / nakładanie | MS | opis Play | `AudioProjectCompiler` (amix normalize=0) | PRZETESTOWANE | audio_test (3 ścieżki) | – |
| Wstawianie / usuwanie ciszy, wyciszanie | POL | – | `insertSilence`, `silenceremove`, `muteRange` | PRZETESTOWANE | audio_test | – |
| Waveform, zoom, znaczniki, kursor | POL | – | `WaveformView` (rzeczywisty render ścieżki) | WYKONANE | – | – |
| Cofnij/ponów, edycja niedestrukcyjna | POL | – | `UndoStack`, EDL na klipach | PRZETESTOWANE (model) | audio_test | – |
| Korektor 10-pasmowy, bas, soprany, HP/LP | POL | – | `equalizer/bass/treble/highpass/lowpass` | PRZETESTOWANE | audio_test (34 efekty) | – |
| Kompresor, limiter, bramka, de-esser | POL | – | `acompressor/alimiter/agate/deesser` | PRZETESTOWANE | audio_test | – |
| Normalizacja szczytowa i LUFS (EBU R128, 2 przebiegi) | POL | – | `AudioTools.normalizePeak/normalizeLufs` | WYKONANE | pomiar LUFS w UI | – |
| Głośność / wzmacniacz | MS | 4PDA | `volume`, Amplifier | PRZETESTOWANE | audio_test | – |
| Redukcja szumów | POL | – | `afftdn` | PRZETESTOWANE | audio_test | – |
| Echo, delay, pogłos (splot z generowaną odpowiedzią impulsową) | POL | – | `aecho`, `afir` + IR | PRZETESTOWANE | audio_test | – |
| Chorus, flanger, phaser, tremolo, vibrato, lo-fi, telefon | rozszerzenie | – | filtry FFmpeg | PRZETESTOWANE | audio_test | – |
| Fade in/out, crossfade | MS/POL | – | `afade`, `acrossfade` | PRZETESTOWANE | audio_test | – |
| Odwracanie | MS | 4PDA | `areverse` | PRZETESTOWANE | audio_test | – |
| Balans, mono/stereo, szerokość, zamiana kanałów | POL | – | `pan`, `extrastereo` | PRZETESTOWANE | audio_test | – |
| Tempo bez zmiany tonu / ton bez tempa / prędkość | MS | opis Play | `atempo`, `asetrate+aresample+atempo` | PRZETESTOWANE | audio_test | brak rubberband w FFmpegKit – jakość pitch-shift DSP standardowa |
| Automatyzacja głośności (klatki) | POL | – | `volume eval=frame` z wyrażeniem kluczowym | WYKONANE | – | – |
| Zmiana częstotliwości próbkowania, bitrate, kanałów | MS | opis Play | `AudioExportSettings` | PRZETESTOWANE | audio_test (9 formatów) | – |
| Analiza spektrum/częstotliwości, miernik poziomu, przesterowania | POL | – | FFT (Dart), `astats`-like, `loudnorm` pomiar | PRZETESTOWANE | analysis_test | – |
| BPM, bity, transjenty, zmiany dynamiki | POL | – | `AudioAnalyzer` (spectral flux, autokorelacja, DP beat-tracking) | PRZETESTOWANE | analysis_test (±0,02 BPM) | test na syntetycznym klik-tracku; muzyka o zmiennym tempie mniej dokładna |
| Automatyczne dopasowanie tempa | POL | – | cięcia/przejścia do siatki bitów, tap-tempo | WYKONANE | musicvideo_test | – |
| Mastering podstawowy, presety, własne presety | POL | – | `factoryFxPresets`, KV `fxPresets` | WYKONANE | – | – |
| Rozdzielanie wokalu (AI) | POL | – | zastąpione DSP: usuwanie/izolacja środka | WYKONANE (DSP) | audio_test | **AI (Demucs/Spleeter) nie zaimplementowano** – modele 100–300 MB, wymagania CPU/GPU; DSP działa tylko dla wokalu w centrum |
| Nagrywanie mikrofonu, dodatkowe ścieżki, dyktafon | MS | opis Play | pakiet `record` (WAV/AAC/FLAC/Opus) | WYKONANE | – | NIEZWERYFIKOWANE na urządzeniu |
| Ekstrakcja audio z wideo | MS | opis Play | `extractFromVideo` | WYKONANE | publisher test (Audio.mp3 z wideo) | – |
| Tagi ID3 (tytuł, wykonawca, album…), okładka | MS | Play/4PDA | `writeTags` (-c copy, attached_pic) | WYKONANE | audio_test (metadane title) | – |
| Dzwonki (+ ustawienie dzwonka Android) | MS | opis Play | `ringtone`, `RingtoneManager` | WYKONANE | – | wymaga zgody WRITE_SETTINGS |
| Eksport ścieżki/fragmentu/miksu, konwersja wsadowa | POL | – | `AudioRenderer` (range), `batchConvert` | PRZETESTOWANE | audio_test (range) | – |
| Szybkie narzędzia bez osi czasu (17) | MS | opis Play | `AudioToolsPanel` | WYKONANE | – | – |
| Odtwarzacz (utwory/albumy/foldery) | MS | opis Play | Biblioteka + odtwarzacz media_kit | WYKONANE (częściowo) | – | brak widoku albumów/wykonawców |

## Studio Wideo

| Funkcja | Ref. | Implementacja | Status | Test | Ograniczenia |
|---|---|---|---|---|---|
| Import JPG/PNG/WEBP/GIF/BMP/HEIC, MP4/MOV/MKV/WEBM… | FP | FFprobe, `-loop 1` | PRZETESTOWANE (JPG/MP4) | video_test | HEIC zależny od dekodera w FFmpegKit – NIEZWERYFIKOWANE |
| Oś czasu: kolejność, przycinanie, dzielenie, duplikowanie, usuwanie | FP | `VideoProject` + UI | PRZETESTOWANE (render) | video_test | – |
| Wielościeżkowość: nakładki, teksty, efekty, audio | POL | warstwy kompilatora | PRZETESTOWANE | video_test | – |
| Grupowanie, blokowanie, ukrywanie, wyciszanie | POL | pola `group/locked/hidden/mute` | WYKONANE | – | blokada działa w UI |
| Przyciąganie do znaczników rytmu, zoom osi | POL | `_snap`, slider zoom | WYKONANE | – | – |
| Czas wyświetlania zdjęć (globalnie) | FP | `setAllImageDurations` | WYKONANE | – | – |
| Zoom, panorama, Ken Burns, obrót, skalowanie, kadrowanie, paralaksa (2.5D), drgania, pulsowanie do bitu | FP | `zoompan` + klatki kluczowe + `rotate` | PRZETESTOWANE | video_test (13 presetów) | paralaksa = przybliżenie 2.5D |
| Klatki kluczowe, krzywe (lin/in/out/in-out/hold) | POL | `keyframeExpr` | PRZETESTOWANE | video_test | – |
| Animacje wejścia/wyjścia (fade/zoom/slide/spin/pop) | FP | kompilator | PRZETESTOWANE | video_test | – |
| Prędkość, slow motion, przyspieszenie, odwracanie, stop-klatka, pętla | FP | `setpts/reverse/tpad/stream_loop` | PRZETESTOWANE | video_test (video_ops) | `reverse` wymaga RAM ~ długość klipu |
| PIP, chroma key, maski (koło/elipsa/zaokr./serce/gwiazda), ramka | FP/POL | overlay+chromakey+geq | PRZETESTOWANE | video_test | – |
| Przejścia: 32 (fade, crossfade, dissolve, slide, zoom, wipe, spin, blur, glitch, flash, kostka 3D, filmowe…) | FP | `xfade` + wyrażenia custom | PRZETESTOWANE | video_test (każde) | – |
| Regulacja czasu przejść, do wszystkich, na bit | FP | UI | WYKONANE | – | – |
| Efekty: ogień, dym, iskry, śnieg, deszcz, błyskawice, mgła, kurz, popiół, cząsteczki, światła, flary, neon, glitch, VHS, retro, kinowy, stary film, rozmycie, winieta, 3D tilt, ramka, lustro, kalejdoskop, RGB, pikselizacja (28) | FP/POL | proceduralne (FFmpeg) | PRZETESTOWANE | video_test (każdy) | wygląd proceduralny, nie fotorealistyczny |
| Efekty reagujące na muzykę | POL | sendcmd z rzeczywistej analizy (energia/bas/bity) | PRZETESTOWANE | video_test | – |
| Korekcja kolorów (11 parametrów), 16 filtrów, LUT .cube, presety własne | FP/POL | `eq/exposure/colortemperature/curves/lut3d…` | PRZETESTOWANE (filtr) | video_test | – |
| Teksty statyczne/animowane (13 animacji), tytuły, litery/słowa, przewijane, kontury, cienie, gradient, tło, własne czcionki, polskie znaki | FP/POL | ASS/libass | PRZETESTOWANE | video_test | gradient = 8 pasów |
| Naklejki, logo, nakładki PNG/GIF/WebM z przezroczystością | FP | overlay RGBA | WYKONANE | video_test (PNG/JPG) | GIF/WebM alfa NIEZWERYFIKOWANE |
| Strefy bezpieczne | POL | `SafeZonePainter` | WYKONANE | – | przybliżone strefy |
| Lektor (voice-over) | FP | `record` + ścieżka audio | WYKONANE | – | NIEZWERYFIKOWANE na urządzeniu |
| Rozmyte tło / dopasowanie proporcji | FP | `FitMode.blurBackground` | PRZETESTOWANE | video_test | – |

## Szybki teledysk, wizualizator, lyric/karaoke

| Funkcja | Implementacja | Status | Test | Ograniczenia |
|---|---|---|---|---|
| One-click: 11 trybów (statyczna/animowana okładka, dynamiczny, slajdy, lyric, karaoke, visualizer, promo, album, trailer, beat-sync) | `MusicVideoGenerator` | PRZETESTOWANE | musicvideo_test (wszystkie tryby) | – |
| 20 stylów edytowalnych + własne szablony | `factoryStyles`, KV templates | PRZETESTOWANE | musicvideo_test (20 stylów) | – |
| Cięcia dokładnie na wykrytych bitach | `cutPoints` | PRZETESTOWANE | musicvideo_test (<1 µs) | – |
| Wybór najlepszego fragmentu (promo) | `bestSection` | PRZETESTOWANE | musicvideo_test | heurystyka energii |
| Wizualizatory: liniowe, kołowe (remap polarny), fala, oscyloskop XY, słupki, spektrogram, CQT, mierniki | `visualizer.dart` | PRZETESTOWANE | video_test | – |
| Pulsowanie / animacje na bas, logo w centrum, na zdjęciu/filmie | sendcmd + scale@inst | PRZETESTOWANE | video_test | – |
| Wklejanie tekstu, podział na wersy, ręczne czasy, tap-sync wersów i słów | `LyricsTrack`, LyricsScreen | PRZETESTOWANE (model) | services_test | UI NIEZWERYFIKOWANE na urządzeniu |
| Karaoke (podświetlanie słów \kf), podgląd na żywo | ASS karaoke | PRZETESTOWANE | video_test | – |
| SRT/VTT/LRC (enhanced) import/eksport, korekta grupowa, polskie znaki | parsery | PRZETESTOWANE | services_test | – |
| Automatyczna transkrypcja / rozpoznawanie śpiewu PL | – | **ZABLOKOWANE** | – | brak dołączonego lokalnego modelu (Whisper ~75–1500 MB, licencja MIT – możliwe w przyszłości); auto-rozkład wersów na takty jako przybliżenie |

## Eksport, publikacja

| Funkcja | Status | Test | Ograniczenia |
|---|---|---|---|
| Profile: TikTok, Shorts, Reels (IG/FB), YouTube, Facebook, 1:1, 4:5, własne | WYKONANE | services_test (aktualizacja profili) | limity aktualizowalne z JSON |
| 360p–4K, 24/25/30/50/60 FPS | PRZETESTOWANE (1080×1920@30) | video_test | 4K – zależne od sprzętu |
| MP4 H.264, H.265, WEBM VP9, MOV, MKV, GIF, ProRes | WYKONANE | H.264 PRZETESTOWANE | H.265/VP9/GIF ścieżki zakodowane, NIEZWERYFIKOWANE w teście |
| Enkodery sprzętowe (MediaCodec/NVENC/QSV/AMF/MF) + fallback programowy | WYKONANE | fallback PRZETESTOWANY (libx264) | HW NIEZWERYFIKOWANE |
| Bitrate/jakość/rozdzielczość/FPS/próbkowanie, szacowanie rozmiaru, kompresja do rozmiaru, fragment, presety | WYKONANE | – | szacunek przybliżony |
| Eksport grafiki: PNG/JPG/WEBP, klatka, miniatura, okładka | WYKONANE | services_test (pakiet) | – |
| Bez znaków wodnych, bez limitów | WYKONANE | – | – |
| Udostępnianie Android (Sharesheet, ACTION_SEND, FileProvider, MediaStore, SAF, do konkretnej aplikacji) | WYKONANE | – | NIEZWERYFIKOWANE (brak urządzenia) |
| Udostępnianie Windows (DataTransferManager, folder, schowek, panele) | WYKONANE | – | NIEZWERYFIKOWANE (brak Windows) |
| Pakiet publikacyjny + ZIP | PRZETESTOWANE | services_test | – |
| Inteligentna kontrola wymagań platform | PRZETESTOWANE | services_test | – |
| Jeden projekt — wiele platform | WYKONANE | batch_test (planowanie) | – |
| YouTube Data API (OAuth, wznawialny upload, postęp, miniatura, publishAt, potwierdzenie statusu, duplikaty, tokeny) | PRZETESTOWANE (protokół, mock) | services_test | **ZABLOKOWANE** na koncie: wymaga klienta OAuth właściciela + audytu Google (bez audytu filmy są prywatne) |
| TikTok/Instagram/Facebook/X/Threads API | **ZABLOKOWANE** | – | audyt aplikacji (TikTok), konto firmowe + App Review (Meta), płatne API (X); alternatywa: udostępnianie systemowe/oficjalne panele |
| Historia, statusy (10), zapobieganie duplikatom | PRZETESTOWANE | services_test | – |

## Synchronizacja, biblioteka, system

| Funkcja | Status | Test | Ograniczenia |
|---|---|---|---|
| Local-first, praca bez konta | WYKONANE | – | – |
| Silnik synchronizacji (rewizje+przodkowie, SHA-256, deduplikacja, konflikty → obie wersje, kosz/tombstone, urządzenia, odłączanie, wznawianie, ponawianie) | PRZETESTOWANE | sync_test (17 kroków, backend folderowy) | – |
| Google Drive appDataFolder (wznawialny upload, Range download, quota) | PRZETESTOWANE (protokół, mock) | services_test | **ZABLOKOWANE** end-to-end: brak identyfikatorów OAuth (jednorazowa konfiguracja właściciela) |
| Logowanie Google: Windows loopback+PKCE w przeglądarce, Android Credential Manager | WYKONANE | – | jw. |
| Bezpieczne tokeny (Keystore / DPAPI) | WYKONANE | – | flutter_secure_storage |
| Synchronizacja przez folder (OneDrive/Dropbox/NAS) | PRZETESTOWANE | sync_test | – |
| Praca w tle Android (WorkManager) | NIEZWERYFIKOWANE / częściowo | – | synchronizacja przy starcie, wznowieniu i co 5 min gdy aplikacja działa; bez WorkManager |
| Windows autostart synchronizacji | WYKONANE (instalator) | – | – |
| Biblioteka: miniatury, kategorie, tagi, daty, rozmiary, statusy, wyszukiwanie, filtry, sortowanie, ulubione, archiwum, kosz, duplikacja | WYKONANE | store w sync_test | – |
| Autozapis i odzyskiwanie po awarii, historia wersji | WYKONANE | – | – |
| Format .wojanmedia (JSON + ZIP z materiałami), migracje, bezpieczne archiwa | PRZETESTOWANE | services_test | – |
| Szablony/presety: import/eksport/synchronizacja | PRZETESTOWANE (KV sync) | sync_test | – |
| Produkcja wsadowa (dobór okładek, wiele platform) | PRZETESTOWANE (plan) | services_test | – |
| Kolejka renderowania, postęp, ETA, anulowanie, ponawianie, kontrola miejsca | PRZETESTOWANE | services_test | – |
| Aktualizacje (podpisany manifest Ed25519 + SHA-256, instalator systemowy) | PRZETESTOWANE (weryfikacja) | services_test | wymaga publicznego adresu manifestu |
| PL/EN, motyw ciemny/jasny, tryb prosty/pro, skróty, drag&drop, mysz/dotyk | WYKONANE | – | EN: menu i elementy wspólne; część etykiet tylko PL |
| Instalator EXE, APK Release | patrz `reports/BUILD_REPORT` w PROJECT_STATUS | | |
