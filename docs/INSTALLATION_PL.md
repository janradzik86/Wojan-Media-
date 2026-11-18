# Instalacja – WoJan Media Studio

## Windows 11 (x64)
1. Pobierz `WoJan-Media-Studio-Setup.exe` (artefakt CI „WoJan-Media-Studio-Windows” lub wydanie).
2. Sprawdź sumę: `Get-FileHash WoJan-Media-Studio-Setup.exe -Algorithm SHA256` i porównaj z `SHA256SUMS.txt`.
3. Uruchom instalator. Instalator **nie jest podpisany certyfikatem Authenticode** (brak certyfikatu – zakup wymaga zgody właściciela), więc Windows SmartScreen może pokazać „System Windows ochronił komputer” → *Więcej informacji* → *Uruchom mimo to*.
4. Wybierz folder, skrót na pulpicie, skojarzenie plików `.wojanmedia`, opcjonalny autostart synchronizacji.
5. Dane użytkownika (`%APPDATA%\pl.wojan\…\WoJanMediaStudio`) **nie są usuwane** przy deinstalacji ani aktualizacji.

Wersja przenośna: `WoJan-Media-Studio-Portable.zip` – rozpakuj i uruchom `WoJanMediaStudio.exe` (to archiwum ZIP, nie instalator).

## Android 8.0+ (ARM64 / ARMv7)
1. Pobierz `WoJan-Media-Studio-Release.apk` i zweryfikuj SHA-256.
2. Zezwól na instalację z tego źródła (Ustawienia → Aplikacje → Specjalny dostęp → Instalowanie nieznanych aplikacji).
3. Zainstaluj. Przy pierwszym imporcie system zapyta o dostęp do zdjęć/filmów/audio; mikrofon – przy nagrywaniu.

## Aktualizacja
* Z aplikacji: Ustawienia → *Sprawdź aktualizacje* (podpisany manifest + SHA-256; Windows uruchamia instalator w trybie cichym, Android – systemowy instalator po Twoim zatwierdzeniu).
* Ręcznie: zainstaluj nowszy plik na istniejący – projekty pozostają (Android: ten sam klucz podpisu i `pl.wojan.mediastudio`).
* Powrót do poprzedniej wersji: Windows – zainstaluj starszy Setup (format projektu v2 jest zgodny wstecz w obrębie 1.x); Android – wymaga odinstalowania (system nie pozwala obniżyć `versionCode`), więc najpierw zsynchronizuj lub wyeksportuj projekty (`.wojanmedia`).

## Pierwsze uruchomienie i synchronizacja
Aplikacja działa od razu offline, bez konta. Aby synchronizować: *Synchronizacja → Zaloguj przez Google* na każdym urządzeniu tym samym kontem. (Wymaga, by właściciel jednorazowo skonfigurował klienta OAuth – patrz `SYNC_ARCHITECTURE.md`.) Alternatywnie: *Folder synchronizowany* (OneDrive/Dropbox/NAS).
