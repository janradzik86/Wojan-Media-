# SECURITY_REPORT

| Obszar | Zabezpieczenie | Weryfikacja |
|---|---|---|
| Wstrzykiwanie poleceń | FFmpeg wywoływany wyłącznie z listą argumentów (FFmpegKit `executeWithArguments`, `Process.start` bez powłoki) | przegląd kodu: brak `runInShell: true`, brak `cmd /c` z danymi użytkownika (wyjątek: `explorer.exe /select,<ścieżka>` jako argument) |
| Wstrzyknięcia do filtergraph | `FfEscape.escapeFilterValue/escapePath` (dwa poziomy), whitelist kolorów i identyfikatorów, klamrowanie liczb, teksty przez pliki ASS (escapowanie `{}`\\) | services_test „filter escaping” |
| Path traversal w archiwach | `SafeArchive.isSafeName` – whitelist nazw (`project.json`, `thumb`, `media/<sha256>.<ext>`, `history/…`), blokada `..`, ścieżek absolutnych, liter dysków, `\`; limit rozmiaru (zip bomb); weryfikacja SHA-256 materiałów | services_test (złośliwe archiwum odrzucone) |
| Integralność | SHA-256 materiałów (import, sync, archiwa), Ed25519 manifestu aktualizacji + SHA-256 instalatora, HTTPS wymagane | services_test, sync_test |
| Tokeny | `flutter_secure_storage` (Android Keystore/EncryptedSharedPreferences, Windows DPAPI), nigdy w plikach tekstowych, nie synchronizowane; `allowBackup=false`, reguły data-extraction wykluczają dane z kopii Google | przegląd |
| OAuth | przeglądarka systemowa + loopback 127.0.0.1 + PKCE S256 + `state`; Android Credential Manager; minimalne zakresy (`drive.appdata`, `youtube.upload` dopiero przy publikacji – autoryzacja przyrostowa) | przegląd |
| Sekrety | brak w repozytorium; keystore i hasła w `signing/` (git-ignored) oraz sekretach CI; `.gitignore` blokuje *.jks, key.properties | `git check-ignore` |
| Telemetria / reklamy | brak; brak SDK analitycznych | pubspec |
| Wysyłanie do AI | brak usług zewnętrznych AI | przegląd |
| Utrata danych | zapis atomowy (tmp+rename), historia 30 rewizji, autozapis, kosz, konflikty jako kopie, cache nigdy nie usuwa materiałów źródłowych, deinstalator nie usuwa danych | sync_test |
| Uprawnienia Android | media READ_MEDIA_* (13+), RECORD_AUDIO na żądanie, REQUEST_INSTALL_PACKAGES (aktualizacje przez instalator systemowy), WRITE_SETTINGS (tylko dzwonek, z ekranem zgody) | manifest |

Znane ryzyka: niepodpisany Authenticode instalator → ostrzeżenie SmartScreen; `client_secret` klienta Desktop Google z definicji nie jest poufny (wstrzykiwany z CI); FFmpeg dekoduje niezaufane pliki (ryzyko podatności w dekoderach – aktualizować FFmpegKit).
Prawa użytkownika: wylogowanie, cofnięcie dostępu, odłączenie urządzenia, eksport danych (JSON), usunięcie danych lokalnych, przywracanie wersji/kosza.
