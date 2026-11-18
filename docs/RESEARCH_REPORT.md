# RESEARCH_REPORT – aplikacje referencyjne

Data analizy: **2026-11-18**. Wykonawca: agent (Claude Code, sesja w chmurze).

## Ograniczenia środowiska researchu (uczciwie)

* `play.google.com`, `apkcombo.com`, `apkpure.com` były **zablokowane** przez politykę sieciową sesji (HTTP 403 / brak DNS) – nie można było pobrać stron sklepu, zrzutów ekranu ani APK.
* Nie było emulatora z Google Play – **nie przetestowano** aplikacji referencyjnych na urządzeniu (zakaz obchodzenia licencji wyklucza też instalację APK z mirrorów).
* Research oparto na wyszukiwarce (wyniki i streszczenia stron Google Play, APKMirror, Softonic, 4PDA, AppGrooves, AppGoblin, App Store, mwm.ai, soft112) oraz na publicznie znanej funkcjonalności tej klasy aplikacji. Każdą informację oznaczono poziomem pewności.

## 1. Mstudio : Audio & Music Editor

| Pole | Wartość | Źródło |
|---|---|---|
| Nazwa | Mstudio : Audio & Music Editor | Google Play (wynik wyszukiwania) |
| Pakiet | `selfcoder.mstudio.mp3editor` | play.google.com/store/apps/details?id=selfcoder.mstudio.mp3editor |
| Producent | Galaxy Studio Apps (galaxystudioapps.me) | wynik wyszukiwania, galaxystudioapps.me/audiomusiceditor |
| Wersja | 5.0.4 (219), 2025-12-06 – wg APKCombo (pewność średnia) | apkcombo.com (streszczenie wyszukiwarki) |
| Instalacje | > 1 000 000 | Google Play (streszczenie) |
| Model | darmowa z reklamami + IAP (Premium) | AppGoblin (≈2/3 monetyzacji z reklam), apk4free „Premium” |
| Ocena | ok. 4,77 / 38,1 tys. ocen | AppGoblin |

Funkcje potwierdzone w opisach (pewność wysoka): Music Cutter (przycinanie, dzwonki/powiadomienia), Audio Splitter (podział na 2 części), Mp3 Merger (łączenie), Music Mixer (miks/mashup), Speed Changer (tempo i ton z podglądem), Video to Audio (wybór formatu, częstotliwość, kanały, bitrate), Mp3 Player (utwory/albumy/wykonawcy/foldery), Audio Recorder (różne częstotliwości i kodowania), Audio Converter.
Funkcje z historii wersji (4PDA, pewność średnia): Audio Omitter (usuwanie fragmentu ze środka), Audio Reverse, Audio Amplifier (wzmacniacz głośności), Tag Editor (dodany w 2.0.2, wg 4PDA usunięty w 2.0.7 – w aktualnym opisie Play nadal wymieniany „tag editor”).
Funkcje niepotwierdzone dla Mstudio (opisy innych aplikacji): 5/18-pasmowy korektor, redukcja szumów – mimo to WoJan je implementuje (wymagane poleceniem).
Problemy/ograniczenia zgłaszane: brak konkretnych źródeł recenzji (wyszukiwarka zwróciła inne aplikacje); typowe dla kategorii: reklamy, funkcje Premium, brak wielościeżkowej osi czasu.

## 2. FotoPlay – Video Maker / Photo Video Maker

| Pole | Wartość | Źródło |
|---|---|---|
| Nazwa | „Video Maker & Editor: FotoPlay” (wcześniej „Video Maker & Photo Music”, „Photo Video Maker & Music”) | Google Play, APKMirror |
| Pakiet | `videoeditor.videomaker.slideshow.fotoplay` | APKPure, APKMirror, Google Play |
| Producent | FotoPlay Video Maker (Android); PixelBox Ltd. (iOS, id6473601533) | APKMirror, App Store |
| Wersja | 8.9.1.3 (soft112, 2025-12-05); APKMirror 8.6.1 / 8.3.2.2 | wyniki wyszukiwania |
| Model | darmowa z reklamami, VIP/Pro (m.in. dożywotnio 29,99 USD w App Store), „bez znaku wodnego” przy oglądaniu reklam | App Store, Google Play (streszczenie) |

Funkcje (pewność wysoka): łączenie zdjęć i filmów w pokaz slajdów z muzyką, szablony (także tekstowe i okolicznościowe), przejścia (ruchy kamery, 3D, maski), efekty specjalne i naklejki/emoji, dodawanie muzyki z fade in/out i biblioteką stylów (Rock, Country, Love, Beat…), ekstrakcja audio z wideo, nagrywanie lektora, zmiana proporcji (YouTube/TikTok/Instagram), prędkość, przycinanie, przejścia zsynchronizowane z muzyką („music beat tools”), eksport bez znaku wodnego.
Funkcje (pewność średnia – mirror soft112): AI Voiceover, AI Text Polish (chmurowe AI – w WoJan **nie** zaimplementowano, bo wymagałyby płatnego/zewnętrznego API i wysyłania danych; zgodnie z §17 brak wysyłki do zewnętrznego AI).
Ograniczenia zgłaszane: brak konkretnych recenzji w wynikach; z opisu wynika presja reklam/VIP i znak wodny w wersji darmowej (WoJan: brak reklam, brak znaków wodnych, brak limitów).

## 3. Funkcje dodatkowo wykryte i dodane do zakresu

Odtwarzacz/biblioteka multimediów (Mstudio „Mp3 Player”) → Biblioteka materiałów z odtwarzaczem; Audio Omitter; Splitter; Amplifier; Ringtone/notification maker z ustawieniem dzwonka (Android); szablony okolicznościowe (Walentynki, święta – FotoPlay) → style Romantyczny/Świąteczny/Urodzinowy; naklejki/emoji → nakładki PNG/GIF/WebM; ramki/tła – animowana ramka i rozmyte tło; ruchy kamery i przejścia 3D/maskowe → przejścia „kostka”, „spin”, maski kształtów.

## Źródła (zweryfikowane wyszukiwarką 2026-11-18)

- https://play.google.com/store/apps/details?id=selfcoder.mstudio.mp3editor (zablokowane w sesji; treść ze streszczenia wyszukiwarki)
- https://galaxystudioapps.me/audiomusiceditor/
- https://apkcombo.com/mstudio-audio-music-editor/selfcoder.mstudio.mp3editor/
- https://4pda.to/forum/index.php?showtopic=899377
- https://appgoblin.info/apps/selfcoder.mstudio.mp3editor
- https://www.similarweb.com/app/google/selfcoder.mstudio.mp3editor/
- https://play.google.com/store/apps/details?id=videoeditor.videomaker.slideshow.fotoplay
- https://apkpure.com/video-maker-editor-fotoplay/videoeditor.videomaker.slideshow.fotoplay
- https://www.apkmirror.com/apk/fotoplay-video-maker/video-maker-photo-music/
- https://apps.apple.com/us/app/fotoplay-video-maker-editor/id6473601533
- https://video-maker-photo-slideshow-music-fotoplay.en.softonic.com/android
- https://video-maker-photo-slideshow-music-fotoplay.soft112.com/
- https://shotkit.com/best-slideshow-apps/
- https://justuseapp.com/en/app/6473601533/fotoplay-video-foto-editor/reviews

Nie skopiowano żadnego kodu, grafik, efektów, szablonów ani identyfikacji wizualnej aplikacji referencyjnych. Wszystkie efekty WoJan są generowane proceduralnie (FFmpeg), czcionki na licencji OFL, logo autorskie.
