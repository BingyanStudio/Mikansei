#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef AppBuild
  #error AppBuild is required
#endif
#ifndef AppSource
  #error AppSource is required
#endif
#ifndef DeliveryDirectory
  #error DeliveryDirectory is required
#endif

[Setup]
AppId=com.personal.mikanseta.windows
AppName=Mikanseta
AppVersion={#AppVersion}
AppVerName=Mikanseta {#AppVersion}
AppPublisher=Mikansei
VersionInfoVersion={#AppVersion}.{#AppBuild}
DefaultDirName={localappdata}\Programs\Mikanseta
DefaultGroupName=Mikanseta
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#DeliveryDirectory}
OutputBaseFilename=Mikanseta-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\Mikanseta.exe
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#AppSource}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Mikanseta"; Filename: "{app}\Mikanseta.exe"
Name: "{autodesktop}\Mikanseta"; Filename: "{app}\Mikanseta.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Mikanseta.exe"; Description: "Launch Mikanseta"; Flags: nowait postinstall skipifsilent
