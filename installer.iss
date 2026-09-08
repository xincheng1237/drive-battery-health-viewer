#define MyAppName "硬盘与电池健康查看器"
#define MyAppNameEnglish "Drive & Battery Health Viewer"
#define MyAppVersion "1.0.6"
#define MyAppPublisher "程心 ChengXin"
#define MyAppURL "https://github.com/xincheng1237/drive-battery-health-viewer"
#define MyAppExeName "DriveBatteryHealthViewer.exe"

[Setup]
AppId={{E590FD43-C453-4BD0-992B-67D60436B61A}
AppName={#MyAppName}
AppVerName={#MyAppName} {#MyAppVersion}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={autopf}\Drive Battery Health Viewer
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
DisableWelcomePage=yes
DisableDirPage=no
DisableReadyPage=yes
ShowLanguageDialog=auto
OutputDir=dist
OutputBaseFilename=DriveBatteryHealthViewer_v1.0.6_Windows_x64_Setup
SetupIconFile=app.ico
UninstallDisplayIcon={app}\app.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
MinVersion=6.1
VersionInfoVersion=1.0.6.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppNameEnglish} installer
VersionInfoProductName={#MyAppNameEnglish}
VersionInfoProductVersion={#MyAppVersion}
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"

[Files]
Source: "dist\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\DriveBatteryHealthViewer.Legacy.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\modern\*"; DestDir: "{app}\modern"; Flags: ignoreversion recursesubdirs createallsubdirs; Check: IsModernWindows
Source: "dist\BUILD-MANIFEST.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "app.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\app.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\app.ico"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
const
  DotNetDesktopRuntimeURL = 'https://aka.ms/dotnet/8.0/windowsdesktop-runtime-win-x64.exe';
  WindowsAppRuntimeURL = 'https://aka.ms/windowsappsdk/1.8/1.8.260804001/windowsappruntimeinstall-x64.exe';

function IsModernWindows: Boolean;
var
  Version: TWindowsVersion;
begin
  GetWindowsVersionEx(Version);
  Result := (Version.Major > 10) or
    ((Version.Major = 10) and (Version.Build >= 17763));
end;

function HasVersionPrefix(const RootKey: Integer; const KeyName, Prefix: String): Boolean;
var
  Names: TArrayOfString;
  I: Integer;
begin
  Result := False;
  if RegGetSubkeyNames(RootKey, KeyName, Names) then
    for I := 0 to GetArrayLength(Names) - 1 do
      if Pos(Prefix, Names[I]) = 1 then
      begin
        Result := True;
        Exit;
      end;
end;

function HasDotNetDesktop8: Boolean;
begin
  Result := HasVersionPrefix(HKLM64,
    'SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App', '8.');
end;

function HasWindowsAppRuntime18: Boolean;
begin
  Result := HasVersionPrefix(HKCU,
    'Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages',
    'Microsoft.WindowsAppRuntime.1.8_');
end;

procedure InstallModernPrerequisites;
var
  RuntimePath: String;
  ResultCode: Integer;
begin
  if not IsModernWindows then
    Exit;

  try
    if not HasDotNetDesktop8 then
    begin
      DownloadTemporaryFile(DotNetDesktopRuntimeURL,
        'windowsdesktop-runtime-8-win-x64.exe', '', nil);
      RuntimePath := ExpandConstant('{tmp}\windowsdesktop-runtime-8-win-x64.exe');
      if not Exec(RuntimePath, '/install /quiet /norestart', '', SW_HIDE,
        ewWaitUntilTerminated, ResultCode) then
        Log('Unable to start .NET Desktop Runtime installer. The launcher will use the compatibility UI.');
    end;

    if not HasWindowsAppRuntime18 then
    begin
      DownloadTemporaryFile(WindowsAppRuntimeURL,
        'WindowsAppRuntimeInstall-x64.exe', '', nil);
      RuntimePath := ExpandConstant('{tmp}\WindowsAppRuntimeInstall-x64.exe');
      if not Exec(RuntimePath, '--quiet', '', SW_HIDE,
        ewWaitUntilTerminated, ResultCode) then
        Log('Unable to start Windows App Runtime installer. The launcher will use the compatibility UI.');
    end;
  except
    Log('Modern UI prerequisites could not be installed. The launcher will use the compatibility UI.');
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    InstallModernPrerequisites;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpSelectDir then
    WizardForm.NextButton.Caption := SetupMessage(msgButtonInstall)
  else if CurPageID = wpFinished then
    WizardForm.NextButton.Caption := SetupMessage(msgButtonFinish)
  else
    WizardForm.NextButton.Caption := SetupMessage(msgButtonNext);
end;
