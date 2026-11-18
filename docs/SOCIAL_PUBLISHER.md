# SOCIAL_PUBLISHER

## Stan oficjalnych API (analiza 2026-11)

| Platforma | Oficjalne API publikacji | Dostępność dla prywatnego narzędzia | Implementacja w WoJan |
|---|---|---|---|
| YouTube / Shorts | YouTube Data API v3 `videos.insert` (resumable), `thumbnails.set`, `status.publishAt` | Tak (OAuth `youtube.upload`); projekty bez audytu Google → filmy wymuszone jako **prywatne**; dzienny limit 10 000 jednostek (upload ≈ 1600) | **Zaimplementowane**: OAuth, wybór konta, tytuł/opis/hashtagi/tagi, widoczność, miniatura, harmonogram po stronie YouTube, kolejka i rzeczywisty postęp bajtowy, wznawianie, odświeżanie tokenu, duplikaty (SHA-256+konto), potwierdzanie statusu przez `videos.list` |
| TikTok | Content Posting API | Wymaga rejestracji aplikacji i audytu TikTok; bez audytu tylko prywatne szkice | Udostępnienie pliku do aplikacji TikTok (Android `ACTION_SEND` + `setPackage`) / strona przesyłania; status „Przekazany do aplikacji docelowej” |
| Instagram / Reels, Facebook / Reels, Threads | Graph API (Instagram Content Publishing, Pages, Threads API) | Konto firmowe/twórcy, App Review Meta, publiczny URL pliku (hosting) | Udostępnianie systemowe/do aplikacji, oficjalne panele, kopiowanie opisu |
| X | API v2 media upload | płatne plany API | udostępnianie systemowe / compose |
| WhatsApp, Messenger, Telegram, Discord, Drive, OneDrive, Dropbox, e-mail | brak (lub nie dotyczy) | – | Android Sharesheet / Windows Share UI (DataTransferManager) |

Nie deklarujemy publikacji, gdy plik jedynie przekazano – status `handedOff`. Nic nie jest publikowane bez jawnego potwierdzenia (`userApproved`, dialog z podsumowaniem).

## Harmonogram
YouTube: `publishAt` – realizowane przez platformę, urządzenie może być wyłączone. Pozostałe: tylko szkic z datą (przypomnienie w historii), **brak autonomicznej publikacji** – nie uruchamiamy płatnego serwera.

## Statusy
Szkic, Gotowy do przesłania, Oczekuje, Przesyłanie, Przekazany do aplikacji docelowej, Przesłany do platformy, Zaplanowany, Opublikowany, Błąd, Wymaga zatwierdzenia.

## Kontrola przed publikacją
Proporcje, rozdzielczość, kodek, długość (min/max), bitrate, rozmiar, długość tytułu/opisu, liczba hashtagów, dźwięk, miniatura. Limity są danymi (`PlatformProfiles.updateFromJson`) z wersjonowaniem – można je aktualizować bez nowej wersji aplikacji.

## Pakiet publikacyjny
`Teledysk.mp4, Audio.mp3, Okladka.png, Miniatura.jpg, Opis.txt, Hashtagi.txt, Napisy.srt, Metadane.json` (+ SHA-256 wideo) oraz ZIP.

## Testy
Protokół YouTube przetestowany na serwerze-atrapie (sesja resumable, 308/Range, odświeżenie tokenu po 401, trwała utrata tokenu → komunikat o ponownym logowaniu, wymóg zatwierdzenia, status zaplanowany). Test na prawdziwym koncie: **ZABLOKOWANY** (brak klienta OAuth właściciela; zgodnie z §20 nie publikowano materiałów testowych).
