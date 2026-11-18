# PERFORMANCE_REPORT

Pomiary wykonane 2026-11-18 w kontenerze testowym: **4 vCPU x86-64, 15 GB RAM, bez GPU**, FFmpeg 6.1 (programowy libx264), równolegle z innymi zadaniami (wartości zawyżone względem dedykowanej maszyny). Brak pomiarów na Windows 11 i telefonie (brak urządzeń – NIEZWERYFIKOWANE).

| Scenariusz | Wynik |
|---|---|
| Analiza muzyki (dekodowanie + FFT + BPM + bity) 20 s MP3 | < 1 s (analysis_test, 3 utwory w 2 s) |
| Miks 3 ścieżek, 34 efekty, eksport MP3 20 s | ~2 s (audio_test) |
| Teledysk 1080×1920 @30, 16 s: 5 klipów (Ken Burns, rozmyte tło, beat-pulse, rotacja), 4 przejścia (fade/slide/spin/glitch), śnieg reaktywny, błysk na bit, winieta, logo z maską, tekst wordPop, karaoke, wizualizator | 67–102 s (libx264 `veryfast`, CRF 23) ≈ 0,16–0,24× czasu rzeczywistego |
| Podgląd tego samego projektu w 1/3 rozdzielczości, 20 fps, `ultrafast` | ~4–6× szybciej niż eksport (rozdzielczość i preset) |
| Pojedyncze przejście 320×240 (32 rodzaje) | 0,5–1,5 s każde |
| Generowanie projektu one-click (planowanie) | < 50 ms |
| Synchronizacja 11 MB pliku (backend folderowy, chunk 64 KB) | < 1 s; wznowienie wysyła tylko brakujące bajty |

## Mechanizmy wydajności
* FFmpeg wielowątkowy (filtry/enkodery), jedno przejście `filter_complex` na cały projekt (bez plików pośrednich).
* Enkodery sprzętowe w kolejności: Android MediaCodec, NVIDIA NVENC, Intel QSV, AMD AMF, Media Foundation – automatyczny fallback na x264/x265 przy błędzie.
* Podgląd o obniżonej rozdzielczości (profil: 0,5 / 0,33 / 0,25) – ten sam graf co eksport.
* Cache: analiza muzyki (JSON wg SHA-256), miniatury, waveformy (wg skrótu konfiguracji ścieżki); czyszczenie cache nie usuwa materiałów źródłowych.
* Analiza w osobnym izolacie (`compute`) – UI nie jest blokowany; render w kolejce (jedno ciężkie zadanie naraz – mniejsze przegrzewanie).
* Profil oszczędzania baterii: niższy podgląd + enkoder sprzętowy. Kontrola wolnego miejsca przed renderem (Windows FFI GetDiskFreeSpaceEx, Android StatFs).

## Ograniczenia
* `reverse` klipu wideo buforuje klatki w RAM (zalecane krótkie fragmenty).
* Efekty `geq` (maski, ogień) są kosztowne w 4K.
* 4K na telefonie zależy od limitów enkodera MediaCodec (fallback programowy będzie wolny).
