# Builds WoJan-Media-Studio-Setup.exe on a Windows 10/11 x64 machine.
# Requirements: Flutter 3.50.0, Visual Studio 2022 Build Tools (C++ desktop), Inno Setup 6 (winget install JRSoftware.InnoSetup).
# Usage (PowerShell, repo root):  .\scripts\build_windows.ps1 [-ClientId <google-desktop-client-id>] [-ClientSecret <secret>]
param([string]$ClientId = "", [string]$ClientSecret = "", [string]$ManifestUrl = "")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location "$root\source\wojan_media_studio"
$version = (Select-String -Path pubspec.yaml -Pattern '^version:').Line -replace 'version: ','' -replace '\+.*',''
flutter pub get
flutter build windows --release --dart-define=WMS_VERSION=$version --dart-define=WMS_GOOGLE_DESKTOP_CLIENT_ID=$ClientId --dart-define=WMS_GOOGLE_DESKTOP_CLIENT_SECRET=$ClientSecret --dart-define=WMS_UPDATE_MANIFEST_URL=$ManifestUrl
$rel = "build\windows\x64\runner\Release"
foreach ($dll in 'msvcp140.dll','msvcp140_1.dll','msvcp140_2.dll','vcruntime140.dll','vcruntime140_1.dll','concrt140.dll') {
  if (Test-Path "$env:WINDIR\System32\$dll") { Copy-Item "$env:WINDIR\System32\$dll" $rel -Force }
}
Pop-Location
$iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw "Inno Setup 6 not found (winget install JRSoftware.InnoSetup)" }
& $iscc /DAppVersion=$version "$root\scripts\installer\wojan.iss"
Compress-Archive -Path "$root\source\wojan_media_studio\$rel\*" -DestinationPath "$root\builds\windows\WoJan-Media-Studio-Portable.zip" -Force
Get-FileHash -Algorithm SHA256 "$root\builds\windows\WoJan-Media-Studio-Setup.exe" | Format-List
