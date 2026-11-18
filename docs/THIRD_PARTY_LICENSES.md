# THIRD_PARTY_LICENSES

**Licencja dystrybucji WoJan Media Studio: GPL-3.0-or-later** – aplikacja linkuje FFmpegKit „Full GPL” (x264, x265, xvidcore, vid.stab). Obowiązki: udostępnienie kodu źródłowego (archiwum `WoJan-Media-Studio-Source.zip` + repozytorium), dołączenie tekstu licencji (`licenses/GPL-3.0.txt`, instalowany w `{app}\licenses`), informacja o zmianach.

| Komponent | Wersja | Licencja | Uwagi |
|---|---|---|---|
| Flutter / Dart SDK | 3.50.0 / 3.14.0 | BSD-3-Clause | |
| ffmpeg_kit_flutter_new | 4.7.2 | GPL-3.0 (LGPL-3.0 FFmpeg + GPL lib) | FFmpeg 8.1.2; Windows bundle zawiera `LICENSES/NOTICE.txt` z listą DLL |
| FFmpeg | 8.1.2 | LGPL-2.1+/GPL (konfiguracja GPL) | |
| x264, x265, xvidcore, vid.stab | – | GPL-2.0+ | |
| libass, freetype, fontconfig, fribidi, harfbuzz | – | ISC / FTL / MIT / LGPL | |
| lame, opus, vorbis, vpx, dav1d, webp, soxr, speex, twolame, kvazaar, zimg | – | LGPL/BSD | |
| media_kit (+ libmpv) | 1.2.6 | MIT (libmpv LGPL) | |
| sqflite / sqflite_common_ffi / SQLite | 2.4.x | BSD-2 / public domain | |
| file_picker, share_plus, path_provider, url_launcher, shared_preferences | – | MIT / BSD-3 | |
| flutter_secure_storage | 11.2.0 | BSD-3 | |
| record | 7.2.0 | BSD-3 | |
| google_sign_in | 7.2.0 | BSD-3 | |
| http, crypto, archive, uuid, path, ffi | – | BSD-3 / MIT | |
| cryptography | 2.9.0 | Apache-2.0 | |
| desktop_drop | 0.9.x | MIT | |
| permission_handler | 13.x | MIT | |
| Czcionki: Noto Sans, Anton, Bebas Neue, Oswald, Playfair Display, Lobster, Pacifico, Caveat, Monoton, Press Start 2P, Rubik Glitch, Nosifer | Google Fonts | **SIL OFL 1.1** (`licenses/OFL-1.1-fonts.txt`) | sprawdzone pokrycie polskich znaków |
| Inno Setup | 6 | Inno Setup License (darmowa, także komercyjnie) | tylko narzędzie budowania |

Grafiki, efekty, przejścia, szablony i logo: **autorskie** (generowane proceduralnie lub narysowane skryptem `scripts/make_icons.py`).

### Patenty i kodeki
Licencje open source nie zwalniają z ewentualnych opłat patentowych za kodeki (H.264/AVC i H.265/HEVC – pule MPEG LA/Via LA/Access Advance, AAC). Dystrybucja oprogramowania z enkoderem x264/x265 może w niektórych jurysdykcjach podlegać licencjonowaniu patentowemu. Na Androidzie preferowany jest systemowy enkoder MediaCodec (licencja producenta urządzenia). Bezpatentowe alternatywy dostępne w aplikacji: VP9/WebM, Opus, FLAC, Vorbis. Decyzja o dystrybucji komercyjnej należy do właściciela.
