# TEST_REPORT

Data: 2026-11-18. Środowisko: Linux x64 (4 vCPU), Flutter 3.50.0, **prawdziwy FFmpeg 6.1** (aplikacje: FFmpegKit 8.1.2). Materiały testowe: wyłącznie syntetyczne (generowane FFmpeg: klik-tracki o znanym BPM, tony, testsrc, mandelbrot) – brak materiałów chronionych.

## 1. Testy silnika – `flutter test test/engine -j 1` → **30/30 PASSED** (12 min 21 s)
Log: `reports/test_run.log`.

| Plik | Testy | Co jest weryfikowane rzeczywiście |
|---|---|---|
| analysis_test | 4 | MP3 90/128/150 BPM → wykryto 90,02 / 128,02 / 150,02; liczba bitów ±12%, >85% bitów w ±50 ms od rzeczywistych uderzeń; wykrywanie przesterowań |
| audio_test | 5 | **Obowiązkowy test audio (§20)**: import MP3 → przycięcie 2–26 s → usunięcie 10–14 s → fade in/out → tempo 1,25× → głośność −3 dB → miks 3 ścieżek (FLAC + OGG z pogłosem, EQ, kompresorem, pitch) + limiter → eksport MP3; FFprobe: mp3, 44,1 kHz, stereo, czas 20,0 s ±0,1, tag tytułu; dekodowanie: RMS > −40 dBFS, szczyt ≤ 0 dBFS, fade-in potwierdzony energią. Wszystkie 34 efekty renderują; 9 formatów eksportu (czas ±0,15 s); operacje edycji (split, copy/paste, cisza, wyciszenie, duplikacja, kolejność, pętle 3× = 18 s, eksport fragmentu 5 s); uszkodzony plik → czytelny błąd |
| video_test | 3 | **Obowiązkowy test wideo (§20)**: prawdziwy utwór + 4 zdjęcia + klip wideo, projekt 9:16, animacje (Ken Burns, beat-pulse, pan, zoom-rotate, rozmyte tło), efekty reagujące na rytm (śnieg reaktywny, błysk na bit), przejścia (fade, slide, spin, glitch), polskie napisy („Zażółć gęślą jaźń – ŁÓDŹ”, karaoke), logo z maską, wizualizator → MP4 **1080×1920**, FFprobe: h264+aac, 30 fps, czas 16,0 s ±0,1, liczba klatek 480 ±2, różnica długości strumieni audio/wideo < 80 ms; arkusz klatek do kontroli wizualnej (`reports/screenshots/20_teledysk_test_klatki.png`) – sprawdzony wizualnie. Każde z 32 przejść; każdy z 28 efektów, 13 ruchów, 10 wizualizatorów, 13 animacji tekstu, 9 animacji wejścia, 6 masek, operacje wideo (odwrócenie, 2×, stop-klatka, obrót, odbicie, kadr) |
| musicvideo_test | 3 | cięcia teledysku dokładnie na wykrytych bitach (<1 µs); wszystkie 11 trybów one-click renderują pliki z dźwiękiem o poprawnej długości; wszystkie 20 stylów |
| sync_test | 6 | **Obowiązkowy test synchronizacji (§20)**, kroki 1–17 na backendzie folderowym: zapis „Windows” → pobranie na „Android” z weryfikacją SHA-256 → edycja → aktualizacja na „Windows”; offline → status „Oczekuje”, edycja offline → sync po powrocie; kontrolowany konflikt → obie wersje na obu urządzeniach, kolejne synchronizacje stabilne; przerwany transfer 11 MB → `.part`, wznowienie wysyła wyłącznie brakujące bajty; świeże urządzenie odzyskuje wszystkie projekty i materiały bez konfiguracji; szablony KV, usunięcie z tombstone, odłączenie urządzenia → wymaga logowania |
| services_test | 9 | SRT/VTT/LRC (enhanced) z polskimi znakami, tap-sync, korekta grupowa, przyciąganie do bitów; escapowanie filtrów, odrzucenie złośliwego archiwum (path traversal), migracja v1→v2, odmowa nowszego formatu; kontrola wymagań platform, hashtagi, aktualizacja profili, pakiet publikacyjny (8 plików + ZIP), zapobieganie duplikatom; protokół YouTube (resumable, 308/Range, odświeżenie po 401, trwała utrata tokenu, wymóg zgody, publishAt) i Drive (resumable, Range download, quota) na serwerze-atrapie; podpis Ed25519 manifestu (fałszywy odrzucony), SHA-256 pobrania (niezgodny usunięty); kolejka: postęp, anulowanie (plik częściowy usunięty), brak miejsca; planowanie wsadu |

## 2. Test integracyjny UI – `flutter test integration_test -d linux` (Xvfb) → **PASSED**
Prawdziwa aplikacja (desktop Linux, ten sam kod Dart co Windows/Android): wszystkie 16 ekranów budują się bez wyjątków (zrzuty `reports/screenshots/01…16`), import prawdziwych plików, analiza (120 BPM), wygenerowanie teledysku beat-sync (12 ujęć), widok w Centrum projektów z miniaturą, otwarcie w Studiu Wideo, uruchomienie **rzeczywistego podglądu** przyciskiem „Podgląd” (plik podglądu powstał). Test wykrył i pozwolił naprawić: przepełnienie panelu podglądu (48 px) i osi czasu (6 px), angielskie przyciski kreatora, awarię braku keyringa (Linux).

## 3. Testy kompilacji
| Cel | Wynik |
|---|---|
| `flutter analyze lib` | 0 błędów (ostrzeżenia stylistyczne) |
| Android APK Release arm64+armv7 | **ZBUDOWANY** lokalnie (134,0 MB), `apksigner verify`: v2 OK, 1 podpisujący `CN=WoJan Media Studio`, `pl.wojan.mediastudio` 1.0.0 (1), minSdk 26, targetSdk 36 |
| Linux desktop (debug, do testów UI) | zbudowany |
| Windows EXE + instalator | **ZABLOKOWANY**: brak Windows/MSVC w środowisku; GitHub Actions (workflow gotowy) – zadania kończą się po 3 s bez przydzielenia runnera (`runner_id: 0`, brak logów) w 3 próbach → problem konta (rozliczenia/limit minut Actions dla repozytorium prywatnego) |

## 4. NIEZWERYFIKOWANE (brak urządzeń)
Instalacja i działanie APK na telefonie (brak KVM → brak emulatora), instalator na czystym Windows 11, enkodery sprzętowe, nagrywanie mikrofonu, Sharesheet/DataTransferManager, logowanie Google i Drive end-to-end (brak klientów OAuth), publikacja YouTube na koncie, aktualizacja z serwera, praca w tle Android.

## 5. Testy awaryjne (§20)
| Przypadek | Wynik |
|---|---|
| Uszkodzony plik | PRZETESTOWANE – `MediaEngineException` z czytelnym komunikatem |
| Brak miejsca (lokalnie) | PRZETESTOWANE – kolejka odmawia renderu z komunikatem |
| Brak internetu | PRZETESTOWANE – status „Oczekuje na połączenie”, praca lokalna |
| Wygaśnięcie tokenu | PRZETESTOWANE (mock) – odświeżenie / „zaloguj ponownie” |
| Przerwany transfer | PRZETESTOWANE – wznowienie od offsetu |
| Awaria renderowania | PRZETESTOWANE – fallback enkodera, ponawianie, usuwanie częściowego pliku |
| Nagłe zamknięcie | WYKONANE – autozapis + okno odzyskiwania (nietestowane automatycznie) |
| Migracja starszych projektów | PRZETESTOWANE |
| Przekroczenie limitu chmury | WYKONANE – kontrola `storageQuota` przed wysyłką (test na mocku quota) |
| Duże projekty | częściowo – plik 11 MB w sync; brak testu wielogodzinnego materiału |
