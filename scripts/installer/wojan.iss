; Inno Setup script – WoJan Media Studio (Windows 11 x64)
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\source\wojan_media_studio\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{6E3B1C2A-9F4D-4E7B-8A51-57A0D3C0B0A1}
AppName=WoJan Media Studio
AppVersion={#AppVersion}
AppVerName=WoJan Media Studio {#AppVersion}
AppPublisher=WoJan
DefaultDirName={autopf}\WoJan Media Studio
DefaultGroupName=WoJan Media Studio
DisableProgramGroupPage=yes
OutputBaseFilename=WoJan-Media-Studio-Setup
OutputDir=..\..\builds\windows
SetupIconFile=..\..\source\wojan_media_studio\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\WoJanMediaStudio.exe
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
WizardStyle=modern
ChangesAssociations=yes
CloseApplications=yes
RestartApplications=no
PrivilegesRequiredOverridesAllowed=dialog
LicenseFile=..\..\licenses\LICENSE.txt

[Languages]
Name: "polish"; MessagesFile: "compiler:Languages\Polish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "assoc"; Description: "Skojarz pliki .wojanmedia z WoJan Media Studio"; GroupDescription: "Integracja:"
Name: "autostart"; Description: "Uruchamiaj synchronizację przy logowaniu do Windows"; GroupDescription: "Integracja:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\licenses\*"; DestDir: "{app}\licenses"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{autoprograms}\WoJan Media Studio"; Filename: "{app}\WoJanMediaStudio.exe"
Name: "{autodesktop}\WoJan Media Studio"; Filename: "{app}\WoJanMediaStudio.exe"; Tasks: desktopicon

[Registry]
Root: HKA; Subkey: "Software\Classes\.wojanmedia"; ValueType: string; ValueName: ""; ValueData: "WoJanMediaStudio.Project"; Flags: uninsdeletevalue; Tasks: assoc
Root: HKA; Subkey: "Software\Classes\WoJanMediaStudio.Project"; ValueType: string; ValueName: ""; ValueData: "Projekt WoJan Media Studio"; Flags: uninsdeletekey; Tasks: assoc
Root: HKA; Subkey: "Software\Classes\WoJanMediaStudio.Project\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\WoJanMediaStudio.exe,0"; Tasks: assoc
Root: HKA; Subkey: "Software\Classes\WoJanMediaStudio.Project\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\WoJanMediaStudio.exe"" ""%1"""; Tasks: assoc
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "WoJanMediaStudio"; ValueData: """{app}\WoJanMediaStudio.exe"" --background-sync"; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\WoJanMediaStudio.exe"; Description: "{cm:LaunchProgram,WoJan Media Studio}"; Flags: nowait postinstall skipifsilent

; User data (projects, media, settings) lives in %APPDATA%\pl.wojan\... and
; is NEVER removed by the uninstaller – protects against accidental loss.
