# SYNC_ARCHITECTURE

## Zasada
Local-first: wszystko działa offline. Synchronizacja to opcjonalna warstwa nad plikami projektu (`project.json`), magazynem materiałów (SHA-256) i dokumentami KV (szablony, presety, ustawienia, historia).

## Magazyn zdalny
* **Google Drive `appDataFolder`** (scope `https://www.googleapis.com/auth/drive.appdata`) – ukryty folder przypisany do projektu Google Cloud aplikacji, niewidoczny w UI Dysku, liczony do limitu konta użytkownika. Wersje Windows i Android muszą używać klientów OAuth z **tego samego projektu GCP** – wtedy widzą ten sam folder. `drive.file` odrzucono (wymaga, by plik był utworzony/otwarty przez daną instancję i nie daje wspólnej przestrzeni bez pickera).
* **Folder** (OneDrive/Dropbox/NAS/pendrive) – ten sam protokół, bez logowania.

## Układ
```
blobs/<sha256>.<ext>              niezmienne materiały (deduplikacja globalna)
revs/<projectId>/<revision>.json  niezmienne rewizje projektu
heads/<projectId>/<deviceId>.json wskaźnik – pisze go wyłącznie dane urządzenie
kv/<kolekcja>/<klucz>/<rev>.json + kvheads/…/<deviceId>.json
devices/<deviceId>.json           urządzenia (nazwa, platforma, lastSeen, revoked)
```
Ponieważ każde urządzenie zapisuje tylko własny head, a rewizje są niezmienne, nie jest potrzebne CAS po stronie serwera (Drive v3 go nie zapewnia). **Kolejność ustala pochodzenie rewizji (`ancestors[]`), nie zegar.**

## Algorytm (na projekt)
1. Odczyt wszystkich headów → zbiór rewizji (+ lokalna).
2. Usuń rewizje będące przodkami innych → zbiór maksymalny.
3. 1 element ≠ lokalna → fast-forward (zapis bez nowej rewizji, pobranie małych materiałów, weryfikacja SHA-256). 1 element = lokalna → push (bloby, rewizja, własny head).
4. Wiele elementów → **konflikt**: lokalna linia zostaje, każda konkurencyjna wersja zapisywana jako **kopia** „(konflikt – urządzenie, data)”; nowa rewizja główna obejmuje konkurencyjne w przodkach (konflikt nie powraca).
5. Usunięcie trwałe → rewizja-tombstone `deleted=true` propagowana do innych urządzeń.

## Transfery
Wznawialne uploady (Drive resumable sessions zapisywane w `upload_sessions.json`; folder: `.part` z offsetem), pobierania z `Range`, ponawianie z wykładniczym opóźnieniem i jitterem, kontrola wolnego miejsca w chmurze przed wysyłką (`about.storageQuota`), pobieranie dużych plików na żądanie (próg konfigurowalny), opcja „tylko Wi-Fi”. Aktywna baza SQLite **nie** jest synchronizowana (indeks odbudowywany z plików).

## Statusy
Zsynchronizowano, Zmiany lokalne, Oczekuje na połączenie, Wysyłanie, Pobieranie, Konflikt, Brak miejsca, Wymaga ponownego logowania, Błąd + czas ostatniej udanej synchronizacji.

## Praca w tle
Windows: synchronizacja co 5 min gdy aplikacja działa + opcjonalny autostart z instalatora. Android: przy starcie, wznowieniu i co 5 min podczas działania. **Brak gwarantowanej pracy w tle przy zamkniętej aplikacji** (WorkManager nie został zintegrowany – udokumentowane ograniczenie).

## Zero configuration – jednorazowa konfiguracja WŁAŚCICIELA (bloker)
Użytkownik końcowy tylko loguje się kontem Google. Właściciel musi raz:
1. Utworzyć projekt w Google Cloud Console, włączyć **Google Drive API** i **YouTube Data API v3**.
2. Ekran zgody OAuth: typ „External”, zakresy `drive.appdata`, `youtube.upload`, `youtube.readonly`, `email`; dodać testerów lub przejść weryfikację (zakres `youtube.upload` jest „sensitive” – weryfikacja Google; Drive appdata – nie‑wrażliwy).
3. Klienci OAuth: **Desktop app** (Windows) → `WMS_GOOGLE_DESKTOP_CLIENT_ID` / `WMS_GOOGLE_DESKTOP_CLIENT_SECRET`; **Android** (pakiet `pl.wojan.mediastudio`, SHA‑1 certyfikatu podpisującego z `signing/`); **Web** (serverClientId dla Credential Manager) → `WMS_GOOGLE_SERVER_CLIENT_ID`.
4. Zapisać wartości jako sekrety GitHub Actions (nazwy jak wyżej). Workflow wstrzykuje je `--dart-define` – nie trafiają do repozytorium.
