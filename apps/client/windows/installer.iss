#ifndef AppVersion
  #error AppVersion must be passed to the installer compiler.
#endif

[Setup]
AppId={{E8E5F8F6-7D54-47BB-99BF-45E2E8A54F1B}
AppName=Нона
AppVersion={#AppVersion}
AppPublisher=BasketRef
DefaultDirName={autopf}\Нона
DefaultGroupName=Нона
UninstallDisplayIcon={app}\nona_client.exe
OutputBaseFilename=nona-v{#AppVersion}-windows-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
AppMutex=Local\NonaVpnClient

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать значок на рабочем столе"; GroupDescription: "Дополнительные значки:"; Flags: unchecked

[Files]
Source: "{#SourcePath}\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Нона"; Filename: "{app}\nona_client.exe"; WorkingDir: "{app}"
Name: "{commondesktop}\Нона"; Filename: "{app}\nona_client.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\nona_client.exe"; Description: "Запустить Нону"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
    Exec(ExpandConstant('{sys}\schtasks.exe'),
      '/Delete /TN "Nona VPN" /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;
