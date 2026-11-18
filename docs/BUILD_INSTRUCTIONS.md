# BUILD_INSTRUCTIONS

## Wymagania
* Flutter **3.50.0 stable** (Dart 3.14), Android SDK (platform 36 i 37, build-tools 36), JDK 17–21, NDK 28.
* Windows: Windows 10/11 x64, Visual Studio 2022 Build Tools („Desktop development with C++”), Inno Setup 6.
* Do testów silnika: FFmpeg w PATH (Linux: `apt install ffmpeg`).

## Testy silnika (prawdziwy FFmpeg)
```bash
cd source/wojan_media_studio
flutter pub get
flutter test test/engine            # ~10 min: audio, wideo, teledyski, sync, publisher, updater
WMS_TEST_OUT=../../reports/test_output flutter test test/engine/video_test.dart --plain-name mandatory
```

## Android APK (Release, podpisany)
1. Klucz: `signing/wojan-release.jks` (NIE w repozytorium). Utwórz `android/key.properties`:
   ```
   storeFile=/ścieżka/do/wojan-release.jks
   storePassword=…
   keyAlias=wojan
   keyPassword=…
   ```
   (alternatywnie zmienne `WMS_KEYSTORE_PATH`, `WMS_KEYSTORE_PASSWORD`, `WMS_KEY_ALIAS`, `WMS_KEY_PASSWORD`).
2. Budowanie:
   ```bash
   flutter build apk --release --target-platform android-arm64,android-arm \
     --dart-define=WMS_VERSION=1.0.0 \
     --dart-define=WMS_GOOGLE_SERVER_CLIENT_ID=<web-client-id> \
     --dart-define=WMS_UPDATE_MANIFEST_URL=<https://…/update-manifest.json> \
     --dart-define=WMS_UPDATE_PUBKEY=<base64 Ed25519>
   apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
   ```
3. Każde wydanie MUSI używać tego samego `applicationId` (`pl.wojan.mediastudio`) i tego samego klucza – inaczej aktualizacja nie zainstaluje się na istniejącej.

## Windows (EXE)
```powershell
flutter build windows --release --dart-define=WMS_VERSION=1.0.0 --dart-define=WMS_GOOGLE_DESKTOP_CLIENT_ID=… --dart-define=WMS_GOOGLE_DESKTOP_CLIENT_SECRET=…
# app-local VC++ runtime (msvcp140*.dll, vcruntime140*.dll) do build\windows\x64\runner\Release
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DAppVersion=1.0.0 scripts\installer\wojan.iss
# wynik: builds\windows\WoJan-Media-Studio-Setup.exe
```
FFmpegKit pobiera paczkę Windows (`full-gpl`) podczas CMake z GitHub Releases projektu sk3llo/ffmpeg_kit_flutter (lub `FFMPEGKIT_LOCAL_DIR`).

## CI/CD (GitHub Actions) – `.github/workflows/build.yml`
Jobs: `test` (analiza + testy silnika na Ubuntu z FFmpeg) → `android` (APK, apksigner verify, SHA-256) i `windows` (build, VC++ runtime, smoke test uruchomienia, Inno Setup, cicha instalacja + uruchomienie zainstalowanej aplikacji, SHA-256, portable ZIP) → `release` (tylko tagi `v*`, **szkic** wydania).
Sekrety repozytorium: `WMS_KEYSTORE_B64` (base64 pliku .jks), `WMS_KEYSTORE_PASSWORD`, `WMS_KEY_PASSWORD`, `WMS_KEY_ALIAS`, `WMS_GOOGLE_DESKTOP_CLIENT_ID`, `WMS_GOOGLE_DESKTOP_CLIENT_SECRET`, `WMS_GOOGLE_SERVER_CLIENT_ID`; zmienne: `WMS_UPDATE_MANIFEST_URL`, `WMS_UPDATE_PUBKEY`.

## Wersjonowanie
`pubspec.yaml: version: X.Y.Z+N`; CI ustawia `--build-number=${{ github.run_number }}`.

## Publikowanie aktualizacji
1. Wygeneruj manifest: `dart run tool/sign_manifest.dart <klucz_prywatny_base64> manifest.json > update-manifest.json` (klucz prywatny Ed25519 – poza repozytorium).
2. Umieść instalatory i `update-manifest.json` pod publicznym adresem HTTPS (np. GitHub Releases publicznego repo dystrybucyjnego, GitHub Pages) – **prywatne repozytorium nie nadaje się** (pobieranie wymaga uwierzytelnienia).
