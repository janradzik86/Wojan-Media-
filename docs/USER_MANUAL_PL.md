# Instrukcja użytkownika – WoJan Media Studio

## Nawigacja
Menu (lewa kolumna na komputerze / szuflada na telefonie): Centrum projektów, Studio Audio, Studio Wideo, Szybki Teledysk, Lyric Video, Karaoke, Wizualizator, Konwerter, Biblioteka materiałów, Szablony, Produkcja wsadowa (tryb pro), Kolejka renderowania, Social Publisher, Historia publikacji, Synchronizacja, Ustawienia. Skróty Windows: `Ctrl+1…9` sekcje, `Ctrl+S` zapisz, `Ctrl+Z/Y` cofnij/ponów, `Del` usuń, `Ctrl+D` duplikuj, `Spacja` – tap-sync tekstu. Pliki można przeciągać do okna. Na Androidzie można udostępnić pliki z galerii/innych aplikacji do WoJan.

## Centrum projektów
Siatka projektów z miniaturą, czasem, rozmiarem, statusem synchronizacji/renderu/publikacji. Szukaj, filtruj (ulubione, archiwum, kosz, tagi), sortuj. Menu ⋮: zmiana nazwy, kategoria i tagi, ulubione, duplikuj, archiwizuj, historia wersji (przywracanie), eksport pakietu `.wojanmedia` (z materiałami), kosz → przywróć / usuń na zawsze. Po awarii aplikacja zaproponuje odzyskanie autozapisu.

## Studio Audio
**Edytor wielościeżkowy**: dodaj pliki (audio lub wideo), zaznacz zakres przeciągając po fali. Narzędzia: przytnij do zaznaczenia, wytnij, kopiuj/wklej (w kursorze), podziel, wycisz, wstaw ciszę, zapętl/powiel, fade in/out zaznaczenia, efekt na zaznaczeniu, znaczniki, wykrywanie BPM (linie bitów na fali), nagrywanie mikrofonu. Kliknij fragment na liście, aby ustawić początek/koniec, pozycję, głośność, fade, tempo (bez zmiany tonu), ton (bez zmiany tempa), pętle, odwrócenie, automatyzację głośności i efekty. Kolejność fragmentów zmienisz przeciąganiem. Efekty ścieżki i master (34 efekty, presety fabryczne, własne presety ★). *Podgląd* renderuje rzeczywisty miks. *Eksportuj*: MP3/WAV/FLAC/AAC/M4A/OGG/OPUS/WMA/AIFF, bitrate, próbkowanie, mono/stereo, tagi, tylko zaznaczenie, szacowany rozmiar.
**Szybkie narzędzia** (bez osi czasu): przycinanie, usuń fragment, podziel, połącz, mikser, konwerter, konwersja wsadowa, wideo→audio, tempo/ton, głośność i normalizacja (LUFS), efekty, usuwanie wokalu, usuwanie ciszy, odwrócenie, tagi i okładka, dzwonek (Android: ustaw jako dzwonek), dyktafon.
**Analiza**: BPM i pewność, bity, transjenty, LUFS, true peak, LRA, szczyt, RMS, przesterowane próbki, zmiany dynamiki, przebieg poziomu, średnie spektrum, spektrum w wybranym punkcie, tap-tempo.

## Studio Wideo
Pasek: cofnij/ponów, zapisz, dodaj zdjęcia/klipy, muzyka, lektor, nakładka (logo/PIP/PNG/GIF), tekst, efekt, wizualizator, napisy SRT/VTT/LRC, *cięcia do rytmu*, strefy bezpieczne, format (9:16, 16:9, 1:1, 4:5…), *Podgląd* (prawdziwy render w niskiej rozdzielczości), *Renderuj*.
Oś czasu: przeciągaj klipy, aby zmienić kolejność; zoom; ścieżki nakładek/tekstów/efektów/audio; kropki = bity muzyki.
Inspektor klipu: czas zdjęcia, zakres i prędkość wideo (slow-motion, przyspieszenie), odwrócenie, pętla, stop-klatka, dopasowanie (wypełnij/zmieść/rozmyte tło), obrót/odbicie, podział, kadrowanie, ruch kamery (Ken Burns, panoramy, zoom z obrotem, paralaksa, drgania, pulsowanie do bitu) i klatki kluczowe z krzywymi, animacje wejścia/wyjścia, przejście (32 rodzaje, czas, „= 1 bit”, do wszystkich), kolor (filtry, jasność, kontrast, nasycenie, ekspozycja, gamma, temperatura, odcień, cienie, światła, ostrość, winieta, ziarno, LUT .cube, własne presety).
Nakładki: czas, pozycja, skala, obrót, przezroczystość, klatki kluczowe, chroma key, maski, ramka, animacje, pętla, dźwięk, warstwa, grupa, ukryj/zablokuj. Teksty: 13 animacji, czcionki (także własne .ttf/.otf), kolory, kontur, cień, gradient, tło, pozycja. Efekty: 28 rodzajów z czasem, intensywnością, kolorem i opcją reakcji na muzykę.

## Szybki Teledysk
Kroki: muzyka (automatyczna analiza rytmu) → zdjęcia/klipy (+logo) → tekst (opcjonalnie) → styl (20 + własne) → tryb (11) → format platformy → *Generuj teledysk* → podgląd → *Popraw w Studiu Wideo* lub *Zatwierdź i renderuj* → ekran wyniku (Odtwórz, Zapisz na urządzeniu, Udostępnij, Opublikuj, Zaplanuj, Kopiuj opis/hashtagi, Otwórz folder, Wróć do projektu, Utwórz kolejną wersję).

## Lyric Video i Karaoke
Wybierz utwór i tło, wklej tekst (automatyczny podział na wersy, znaczniki [Refren] są pomijane) lub importuj SRT/VTT/LRC. Synchronizacja: odtwórz i naciskaj przycisk/Spację na początku każdego wersu (lub każdego słowa w trybie słów); *Auto (wg taktów)* – przybliżenie do ręcznej korekty; *Przyciągnij do bitów*; korekta grupowa ±0,1/0,5 s dla zaznaczonych lub wszystkich. Podgląd na żywo, styl, tryb (lyric/karaoke/przewijanie/napisy), eksport SRT/VTT/LRC. Karaoke: opcja usunięcia wokalu z podkładu (DSP). Automatyczna transkrypcja śpiewu nie jest dostępna w tej wersji.

## Wizualizator
Muzyka + tło (zdjęcie/film) + logo; style: słupki, spektrum liniowe, punkty, kołowe, fala, oscyloskop, spektrogram, CQT, mierniki; kolory, intensywność, krycie, pulsowanie na basie, dodatkowe słupki, cząsteczki i jasność reagujące na muzykę.

## Konwerter
Wideo (MP4/WEBM/MOV/MKV/GIF), audio, obrazy (PNG/JPG/WEBP), klatka z filmu, rozdzielczość, FPS, jakość, kompresja do zadanego rozmiaru, fragment.

## Social Publisher
Wybierz plik lub projekt, tytuł/opis/hashtagi (normalizacja), widoczność, harmonogram, platformy. Dla każdej platformy: kontrola wymagań (proporcje, długość, rozmiar, opis…), *Opublikuj przez API* (YouTube), *Otwórz w aplikacji* / *Udostępnij*, *Oficjalny panel publikacji* (opis kopiowany do schowka). *Jeden projekt — wiele platform* renderuje wersje w odpowiednich formatach. Pakiet publikacyjny ZIP. Status „Przekazany do aplikacji docelowej” oznacza, że publikację kończysz w tamtej aplikacji.

## Produkcja wsadowa
Dodaj utwory i okładki (dopasowanie po nazwie pliku), wybierz szablon, tryb i platformy → kolejka renderowania utworzy komplet teledysków.

## Synchronizacja
Logowanie Google lub folder synchronizowany, *Synchronizuj teraz*, data ostatniej synchronizacji, opcje (automatycznie, tylko Wi-Fi, limit automatycznego pobierania), lista urządzeń z możliwością odłączenia. Konflikt edycji = obie wersje zachowane („(konflikt – …)”). Materiały nieprzesłane przed utratą urządzenia nie są odzyskiwalne.

## Ustawienia
Język PL/EN, motyw, tryb prosty/pro, profil wydajności / oszczędzania baterii, rozdzielczość podglądu, enkoder (sprzętowy/programowy), autozapis, czyszczenie cache (bez usuwania materiałów), eksport danych, usunięcie danych, aktualizacje, licencje.
