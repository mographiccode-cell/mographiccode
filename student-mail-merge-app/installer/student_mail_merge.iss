#define MyAppName "Student Mail Merge"
#define MyAppVersion "1.5.0"
#define MyAppPublisher "M. Mahmoud Dghbas"
#define MyAppExeName "student_mail_merge.exe"

[Setup]
AppId={{9E9C0F7D-93E5-4E39-AB57-07D14E6F8D21}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\StudentMailMerge
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\installer-output
OutputBaseFilename=Student-Mail-Merge-Installer-v1.5.0
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: checkedonce

[InstallDelete]
Type: filesandordirs; Name: "{app}\*"
Type: files; Name: "{autodesktop}\student_mail_merge.exe"
Type: files; Name: "{autodesktop}\student_mail_merge-1.exe"
Type: files; Name: "{autodesktop}\student_mail_merge-1.2.1.exe"

[Files]
Source: "..\..\buildapp\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
