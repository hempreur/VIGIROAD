; Installateur Windows de VIGIROAD ADMIN MANAGER (Inno Setup 6).
;   iscc /DAppVersion=1.0.0 /DBuildDir=..\build\windows\x64\runner\Release /DOutDir=..\..\..\dist vigiroad-admin-manager.iss
; Installation par utilisateur (sans droits administrateur) ou pour tous les
; utilisateurs ; raccourcis Bureau et menu Démarrer ; mise à jour silencieuse
; possible depuis l'application (/SILENT /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS).

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef BuildDir
  #define BuildDir "..\build\windows\x64\runner\Release"
#endif
#ifndef OutDir
  #define OutDir "."
#endif

[Setup]
AppId={{8C3F1A52-6E2B-4C1D-9A7E-5B0D2F4E9A11}
AppName=VIGIROAD ADMIN MANAGER
AppVersion={#AppVersion}
AppVerName=VIGIROAD ADMIN MANAGER {#AppVersion}
AppPublisher=VIGIROAD INC (CODEX HEMPREUR)
AppPublisherURL=https://github.com/hempreur/VIGIROAD
AppSupportURL=https://github.com/hempreur/VIGIROAD/issues
AppUpdatesURL=https://github.com/hempreur/VIGIROAD/releases
AppCopyright=Copyright (C) 2026 VIGIROAD INC (CODEX HEMPREUR)
VersionInfoCompany=VIGIROAD INC (CODEX HEMPREUR)
VersionInfoDescription=Installateur de VIGIROAD ADMIN MANAGER
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\VIGIROAD Admin Manager
DefaultGroupName=VIGIROAD
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutDir}
OutputBaseFilename=VIGIROAD-Admin-Manager-{#AppVersion}-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\vigiroad_admin_manager.exe
UninstallDisplayName=VIGIROAD ADMIN MANAGER
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=yes
MinVersion=10.0

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\VIGIROAD Admin Manager"; Filename: "{app}\vigiroad_admin_manager.exe"
Name: "{group}\Désinstaller VIGIROAD Admin Manager"; Filename: "{uninstallexe}"
Name: "{autodesktop}\VIGIROAD Admin Manager"; Filename: "{app}\vigiroad_admin_manager.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\vigiroad_admin_manager.exe"; Description: "{cm:LaunchProgram,VIGIROAD Admin Manager}"; Flags: nowait postinstall skipifsilent
; Mise à jour automatique (installation silencieuse) : l'application redémarre.
Filename: "{app}\vigiroad_admin_manager.exe"; Flags: nowait; Check: ShouldRelaunch

[Code]
// Relance après une mise à jour automatique (/RELAUNCH=1), jamais lors
// d'une installation silencieuse ordinaire (déploiement, tests).
function ShouldRelaunch: Boolean;
begin
  Result := WizardSilent and (ExpandConstant('{param:RELAUNCH|0}') = '1');
end;
