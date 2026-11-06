; Inno Setup 6 script. Build: ISCC.exe /DAppVersion=0.2.0 /DSourceDir=<self-contained publish folder> RestoreNest.iss
#ifndef AppVersion
  #define AppVersion "0.2.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\publish"
#endif

[Setup]
AppId={{6F1D3B0E-52A4-4C7B-9E21-3A5D7C9B1E04}
AppName=RestoreNest
AppVersion={#AppVersion}
AppPublisher=RestoreNest
AppPublisherURL=https://github.com/atlasmarkz/RestoreNest
DefaultDirName={autopf}\RestoreNest
DefaultGroupName=RestoreNest
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputBaseFilename=RestoreNest-Setup-{#AppVersion}
OutputDir=Output
Compression=lzma2/max
SolidCompression=yes
UninstallDisplayName=RestoreNest
UninstallDisplayIcon={app}\SystemCare.exe
WizardStyle=modern
CloseApplicationsFilter=SystemCare.exe
SetupIconFile=..\src\SystemCare\app.ico
ShowLanguageDialog=auto

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinese"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Dirs]
; wimlib (GPLv3+) is not bundled; the user drops wimlib-imagex.exe and libwim-15.dll here.
Name: "{app}\tools\bin"

[Icons]
Name: "{group}\RestoreNest"; Filename: "{app}\SystemCare.exe"
Name: "{autodesktop}\RestoreNest"; Filename: "{app}\SystemCare.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\SystemCare.exe"; Description: "{cm:LaunchProgram,RestoreNest}"; Flags: nowait postinstall skipifsilent runascurrentuser

[Code]
procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then
    WizardForm.FinishedLabel.Caption := WizardForm.FinishedLabel.Caption + #13#10#13#10 +
      'wimlib is not included (GPLv3+). To create restore points, copy wimlib-imagex.exe and libwim-15.dll into:' + #13#10 +
      ExpandConstant('{app}\tools\bin');
end;
