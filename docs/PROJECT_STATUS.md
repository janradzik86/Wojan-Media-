# PROJECT_STATUS – WoJan Media Studio

**Wersja:** 1.0.0 (build 1) • **Aktualizacja:** 2026-11-18 • **Gałąź:** `ccr-752ca9db-2bv10n`

## Aktualny etap
Etapy 1–17 wykonane; etap 18 (produkcyjne kompilacje) – **Android ukończony, Windows zablokowany**; etap 19 (test instalatorów na urządzeniach) – niewykonalny w tym środowisku; etap 20 – ten raport.

## Ukończone
* Research (`docs/RESEARCH_REPORT.md`), matryca (`docs/FEATURE_PARITY_MATRIX.md`).
* Silnik: FFmpeg runner, DSP/analiza, audio (EDL, 34 efekty, 17 narzędzi), wideo (oś czasu, 32 przejścia, 13 ruchów, klatki kluczowe, 28 VFX, kolor/LUT, nakładki, chroma, maski, tekst ASS), teledysk one-click (11 trybów, 20 stylów), wizualizatory (10), lyric/karaoke, eksport, projekt .wojanmedia v2, biblioteka SQLite, synchronizacja (Drive appData + folder), publisher (YouTube API + udostępnianie + pakiety), kolejka, wsad, aktualizacje Ed25519.
* UI: 16 modułów menu + ekran wyniku renderowania; PL/EN, motywy, tryb prosty/pro.
* Android: manifest, FileProvider, MediaStore, Sharesheet do konkretnej aplikacji, odbiór udostępnień, instalacja APK, dzwonek, podpis release.
* Windows: branding, instalator Inno Setup (skojarzenie .wojanmedia, menu Start, pulpit, deinstalator, ochrona danych), skrypt `scripts/build_windows.ps1`, CI.

## Ostatni rzeczywisty test
2026-11-18: `flutter test test/engine -j 1` → **30/30 PASSED**; test integracyjny UI (16 ekranów + generowanie i podgląd teledysku) → **PASSED**. Szczegóły: `docs/TEST_REPORT.md`.

## Wyniki kompilacji
| Produkt | Status | Lokalizacja | Rozmiar | SHA-256 |
|---|---|---|---|---|
| WoJan-Media-Studio-Release.apk | ✅ zbudowany, podpisany (v2), zweryfikowany apksigner | `builds/android/` (nie w git – artefakt) | 133 956 716 B | `c5e8bf0316ea0bc247befb013303a5d508105bd341b503949ef374f892f8168e` |
| WoJan-Media-Studio-Source.zip | ✅ | `builds/` | 13 233 041 B | `f85bd99db21e2d46d6f3a539a517a1f8373fc4214719385dd02066c4c823a6ad` |
| WoJan-Media-Studio-Setup.exe | ❌ ZABLOKOWANY | – | – | – |
| WoJan-Media-Studio-Portable.zip | ❌ ZABLOKOWANY (j.w.) | – | – | – |

Certyfikat APK: `CN=WoJan Media Studio, O=WoJan, C=PL`, SHA-256 `a30fe37ea882f821dc830e8da2302a92515dd1c801e0b36ca2692d9b3292a489`.

## Blokery (wymagają działania właściciela)
1. **GitHub Actions nie uruchamia zadań** (3 próby, 3 s, brak runnera i logów) → sprawdź *Settings → Billing → Actions* (minuty/limit wydatków dla repo prywatnego, metoda płatności) lub *Settings → Actions → General* (włączone Actions). Po odblokowaniu każdy push zbuduje EXE (instalator + test cichej instalacji) i APK. Alternatywa: `scripts/build_windows.ps1` na komputerze z Windows.
2. **OAuth Google** (synchronizacja przez Dysk, YouTube): utwórz projekt GCP + klientów Desktop/Android/Web i dodaj sekrety CI (`docs/SYNC_ARCHITECTURE.md`). Do tego czasu działa praca lokalna i synchronizacja przez folder.
3. **Klucz podpisu Android** (`signing/` – przekazany właścicielowi, NIE w repozytorium): zachowaj kopię; dodaj `WMS_KEYSTORE_B64` i hasła jako sekrety CI. Utrata klucza = brak możliwości aktualizacji zainstalowanej aplikacji.
4. **Kanał aktualizacji**: publiczny URL HTTPS dla `update-manifest.json` (prywatne repo się nie nadaje) + klucz prywatny Ed25519 (`signing/update-signing-key.txt`).
5. Certyfikat Authenticode (opcjonalnie, płatny – nie kupiono).
6. Publikacja API TikTok/Meta/X – wymagają audytów/płatnych planów platform.

## Znane ograniczenia
Brak AI do separacji wokalu i transkrypcji (DSP + ręczna synchronizacja); praca w tle Android tylko przy uruchomionej aplikacji; EN tłumaczenie częściowe; UI nietestowane na fizycznym telefonie/Windows; HW enkodery niezweryfikowane.

## Następny krok
Odblokować Actions → zweryfikować artefakt Windows (instalacja na czystym Windows 11) → zainstalować APK na telefonie ARM64 → skonfigurować OAuth i przejść test synchronizacji na żywo → tag `v1.0.0` (szkic wydania).
