# CHANGELOG

## 1.0.0 – 2026-11-18
Pierwsze wydanie: silnik multimedialny (FFmpeg 8.1 / FFmpegKit), Studio Audio (edycja wielościeżkowa, 34 efekty, 17 szybkich narzędzi, analiza), Studio Wideo (oś czasu, 32 przejścia, 13 ruchów kamery, klatki kluczowe, 28 efektów, kolor/LUT, nakładki/PIP/chroma/maski, 13 animacji tekstu), Szybki Teledysk (11 trybów, 20 stylów, cięcia na bitach), wizualizatory (10), Lyric/Karaoke (SRT/VTT/LRC, tap-sync), format .wojanmedia v2, biblioteka SQLite, synchronizacja (Drive appData / folder), Social Publisher (YouTube API, udostępnianie, pakiety), produkcja wsadowa, kolejka renderowania, podpisane aktualizacje, instalator Inno Setup, APK Release.

## 1.0.1 – 2026-11-18
* **Naprawa: „Brak dostępnego enkodera dla h264” na Androidzie.** Lista enkoderów z FFmpegKit była odczytywana z niekompletnego (asynchronicznego) logu, a filtr odrzucał wszystkie kandydaty. Teraz: pełny log sesji (`getAllLogsAsString`), odporne parsowanie, przy niepewnej liście próbowane są wszystkie enkodery (MediaCodec → libx264 → libopenh264 → wbudowany mpeg4), fallback nie zatrzymuje się po pierwszym błędzie; to samo w Konwerterze. Testy regresyjne `test/engine/encoder_test.dart`.
