# ARCHITECTURE – WoJan Media Studio

## Wybór technologii (zweryfikowany 2026-11-18)

| Warstwa | Wybór | Uzasadnienie / weryfikacja |
|---|---|---|
| UI | **Flutter 3.50.0 stable** (Dart 3.14), `material_ui` | jedna baza kodu Windows + Android; aktywny rozwój (release 2026-11-09) |
| Silnik multimediów | **FFmpeg 8.1.2 przez `ffmpeg_kit_flutter_new` 4.7.2** (Full GPL) | aktywnie utrzymywany fork (publikacja 2026-11-17) porzuconego FFmpegKit; prebuilt Android (Maven, MediaCodec) i Windows x64 (MSYS2); FFmpeg działa w procesie – brak serwera renderującego |
| Odtwarzanie podglądu | `media_kit` (libmpv) | sprzętowe dekodowanie, Windows/Android |
| DSP / analiza | czysty Dart (FFT radix-2, spectral flux, autokorelacja, DP beat-tracker Ellisa) | lokalnie, deterministycznie, testowalne |
| Tekst / karaoke | ASS + libass (wbudowany w FFmpegKit) | pełny Unicode, \kf, \t, \move |
| Baza | SQLite (`sqflite` Android, `sqflite_common_ffi` Windows) – tylko indeks | odtwarzalny z plików, nigdy nie synchronizowany |
| Tokeny | `flutter_secure_storage` (Android Keystore / Windows DPAPI) | §17 |
| Synchronizacja | Google Drive REST v3, `appDataFolder`, scope `drive.appdata` | minimalne uprawnienia, wspólne dla obu platform (ten sam projekt GCP) |
| Publikacja | YouTube Data API v3 (resumable), Android Sharesheet/FileProvider, Windows DataTransferManager (`share_plus`) | jedyne oficjalnie dostępne bez audytu partnerskiego |
| Aktualizacje | podpisany manifest Ed25519 (`cryptography`) + SHA-256 | §19 |
| Instalator | Inno Setup 6 | rejestracja .wojanmedia, deinstalator, zachowanie danych |

Odrzucone: `ffmpeg_kit_flutter` (oryginał – porzucony, binaria wycofane 2025), wywołanie `ffmpeg.exe` przez powłokę (ryzyko wstrzyknięć), chmurowe API renderujące (płatne, wbrew §4).

## Moduły (oddzielone zgodnie z §4)

```
lib/
  engine/            ← czysty Dart, bez Fluttera, testowany na prawdziwym FFmpeg
    ffmpeg/          runner (lista argumentów, bez powłoki), probe, escaping/walidacja
    dsp/             PCM, FFT, analiza (BPM, bity, transjenty, pasma, LUFS pomocniczo)
    audio/           model EDL wielościeżkowy, 34 efekty, kompilator grafu, szybkie narzędzia
    video/           model osi czasu, kompilator filter_complex, przejścia, VFX, wizualizatory, kolor
    lyrics/          LRC/SRT/VTT, generator ASS (animacje, karaoke, przewijanie)
    musicvideo/      generator one-click (11 trybów) + 20 stylów
    export/          profile audio/wideo, enkodery HW/SW, szacowanie rozmiaru
    project/         format .wojanmedia, migracje, magazyn (SHA-256), SQLite index, archiwa
    sync/            RemoteStore (Drive / folder), silnik synchronizacji, KV dokumenty
    publish/         profile platform, kontrola, pakiet, YouTube, historia
    render/ batch/ update/ util/
  platform/          FFmpegKit runner, OAuth, kanał natywny Android, miejsce na dysku (FFI)
  app/               composition root (Services), ustawienia, l10n, motyw
  ui/                powłoka nawigacji (16 pozycji menu) i ekrany
```

## Kluczowe decyzje silnika

* **Podgląd = ten sam kompilator co eksport** (niższa skala/FPS) → zgodność podglądu z wynikiem (§16).
* Każdy element (klip, nakładka, efekt) kompiluje się do fragmentu jednego `filter_complex`. Przejścia przez `xfade` (+ własne wyrażenia: spin, glitch, kostka, film-burn), cięcia przez `concat`; wspólna podstawa czasu `settb=AVTB`.
* Efekty reagujące na muzykę: lokalna analiza → pliki `sendcmd` z wartościami na klatkę, adresowane do **nazwanych instancji filtrów** (`scale@id`, `eq@id`, `colorchannelmixer@id`).
* Ruch kamery: `zoompan` na płótnie 1,25–1,6× (redukcja drgań), krzywe klatek kluczowych → wyrażenia FFmpeg (`keyframeExpr`).
* Pulsowanie do bitu: siatka bitów (BPM i faza z regresji) w wyrażeniu `exp(-k·mod(t-φ,P))`.
* Spektrum kołowe: `showfreqs` → `remap` z mapami biegunowymi generowanymi w Dart.
* Enkodery: kolejność HW (MediaCodec/NVENC/QSV/AMF/MF) → SW (libx264/x265/vpx); automatyczny fallback po błędzie.
* Bezpieczeństwo: argumenty jako lista (FFmpegKit `executeWithArguments`), dwupoziomowe escapowanie wartości filtrów, whitelist kolorów/identyfikatorów, walidacja liczb.

## Format projektu `.wojanmedia` (v2)

ZIP: `project.json` (+ `thumb.jpg`, `media/<sha256>.<ext>`, `history/<rev>.json`). `project.json`:
`format, version, id, name, type, created, modified, revision, parentRevision, ancestors[], deleted, deviceId, category, tags, favorite, archived, trashed, audio{…}, video{…}, assets[{id, name, kind, sha256, size, duration, width, height, hasAudio, relPath}], publish{…}, renderStatus, publishStatus, exportSettings, extra`.
Materiały identyfikowane przez SHA-256, ścieżki względne (`media/…`) – projekt przenośny Windows↔Android. Migracje: `migrateProjectJson` (v1→v2); nowsze wersje są odrzucane z czytelnym komunikatem.
