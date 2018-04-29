unit MainForms;
{**
*  This file is part of the "Creative Solutions PGTools http://www.cserp.org/"
 *
 * @license   mit(https://opensource.org/licenses/MIT)
 *
 * @author    Zaher Dirkey <zaher at parmaja dot com>
 *}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  IniFiles, registry, Contnrs,
  SynEdit, mncPostgre, ConsoleProcess;

type

  { TMainForm }

  TMainForm = class(TForm)
    BackupBtn1: TButton;
    BackupBtn2: TButton;
    CSProductsChk: TCheckBox;
    CleanBtn: TButton;
    BackupBtn: TButton;
    RestoreBtn: TButton;
    CleanBtn3: TButton;
    CleanBtn4: TButton;
    CleanBtn5: TButton;
    DatabasesCbo: TComboBox;
    InfoPanel: TPanel;
    Label3: TLabel;
    BackupDatabasesList: TListBox;
    RestoreBtn1: TButton;
    UserNameEdit: TEdit;
    PasswordEdit: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    LogEdit: TSynEdit;
    procedure BackupBtn1Click(Sender: TObject);
    procedure BackupBtn2Click(Sender: TObject);
    procedure BackupBtnClick(Sender: TObject);
    procedure CleanBtn3Click(Sender: TObject);
    procedure CleanBtn4Click(Sender: TObject);
    procedure CleanBtn5Click(Sender: TObject);
    procedure CleanBtnClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure RestoreBtn1Click(Sender: TObject);
    procedure RestoreBtnClick(Sender: TObject);
  private
    PoolThread: TObjectList;
    ConsoleThread: TmnConsoleThread;
    procedure BackupDatabase(DB: string);
    procedure RestoreDatabase(DB: string);
    procedure Log(S: String);
    procedure ConsoleTerminated(Sender: TObject);
  protected
    PGConn: TmncPGConnection;
    PGSession: TmncPGSession;
    Databases: TStringList;
    PGPathBin: String;
    procedure EnumDatabases(vOld: Boolean);
    procedure OpenPG(vDatabase: string = 'postgres');
    procedure ClosePG;
    procedure Launch(vMessage, vExecutable, vParameters, vPassword: String; vExecuteObject: TExecuteObject = nil);
    procedure Resume;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

{ TMainForm }

procedure TMainForm.CleanBtnClick(Sender: TObject);
var
  i: Integer;
begin
  OpenPG;
  EnumDatabases(True);
  for i := 0 to Databases.Count - 1 do
  begin
    InfoPanel.Caption := 'Dropping database ' + Databases[i];
    PGConn.Execute('drop database "' + Databases[i] + '"');
    //if PGConn.Execute('drop database "' + Databases[i]+'"') then
    Log('Database Dropped: "' + Databases[i] + '"');
    //else
    //  Log('Database Dropped: "' + Databases[i]+'"');
    LogEdit.CaretY := LogEdit.Lines.Count - 1;
    Application.ProcessMessages;
  end;
  ClosePG;
  Log('Clean Done');
  Databases.Clear;
end;

procedure TMainForm.BackupBtnClick(Sender: TObject);
var
  i: Integer;
begin
  for i := 0 to BackupDatabasesList.Items.Count - 1 do
  begin
    BackupDatabase(BackupDatabasesList.Items[i]);
  end;
end;

procedure TMainForm.BackupBtn1Click(Sender: TObject);
begin
  if BackupDatabasesList.ItemIndex >=0 then
    BackupDatabase(BackupDatabasesList.Items[BackupDatabasesList.ItemIndex]);
end;

procedure TMainForm.BackupBtn2Click(Sender: TObject);
var
  cmd: TmncPGCommand;
  DB: string;
begin
  if BackupDatabasesList.ItemIndex >= 0 then
  begin
    DB := BackupDatabasesList.Items[BackupDatabasesList.ItemIndex];
    OpenPG(DB);
    cmd := PGSession.CreateCommand as TmncPGCommand;
    try
      cmd.SQL.Text := 'select * from "System" where "SysSection" = ''Backup''';
      while cmd.Run do
         Log(cmd.Field['SysIdent'].AsString + ': ' + cmd.Field['SysValue'].AsString);
    finally
      cmd.Free;
      ClosePG;
    end;
  end;
end;

procedure TMainForm.CleanBtn3Click(Sender: TObject);
begin
  OpenPG;
  EnumDatabases(false);
  DatabasesCbo.Items.Assign(Databases);
  if DatabasesCbo.Items.Count > 0 then
    DatabasesCbo.ItemIndex := 0;
  Databases.Clear;
  ClosePG;
end;

procedure TMainForm.CleanBtn4Click(Sender: TObject);
begin
  if DatabasesCbo.ItemIndex >=0 then
    BackupDatabasesList.Items.Add(DatabasesCbo.Items[DatabasesCbo.ItemIndex]);
end;

procedure TMainForm.CleanBtn5Click(Sender: TObject);
begin
  if BackupDatabasesList.ItemIndex >=0 then
    BackupDatabasesList.Items.Delete(BackupDatabasesList.ItemIndex);
end;

type

  { TPGExecuteObject }

  TPGExecuteObject = class(TExecuteObject)
  public
    PGConn: TmncPGConnection;
    PGSession: TmncPGSession;
    UserName: string;
    Password: string;
    Database: string;
    Suffix: string;
    CSProducts: Boolean;
    procedure OpenPG(vDatabase: string = 'postgres');
    procedure ClosePG;
    constructor Create;
  end;

  { TBackupExecuteObject }

  TBackupExecuteObject = class(TPGExecuteObject)
  public
    procedure Prepare(ConsoleThread: TmnConsoleThread); override;
    procedure Execute(ConsoleThread: TmnConsoleThread); override;
  end;

  { TRestoreExecuteObject }

  TRestoreExecuteObject = class(TPGExecuteObject)
  public
    procedure Prepare(ConsoleThread: TmnConsoleThread); override;
    procedure Execute(ConsoleThread: TmnConsoleThread); override;
  end;

{ TBackupExecuteObject }

procedure TBackupExecuteObject.Prepare(ConsoleThread: TmnConsoleThread);
var
  cmd: TmncPGCommand;
  filename: string;
begin
  filename := Application.Location + Database + '.backup';
  if FileExists(filename) then
    RenameFile(filename, filename + '.' + Suffix);
  if CSProducts then
  begin
    OpenPG(Database);
    cmd := PGSession.CreateCommand as TmncPGCommand;
    try
      ConsoleThread.WriteString(' ' + Database);
      cmd.SQL.Text := 'insert into "System" ("SysSection", "SysIdent", "SysValue") values (''Backup'', ''LastBeforeBackupDate'', ?SysValue)';
      cmd.SQL.Add('ON CONFLICT ("SysSection", "SysIdent") do update set "SysValue" = ?SysValue');
      cmd.Param['SysValue'].AsString := FormatDateTime('YYYY-MM-DD:HH:MM:SS', Now);
      cmd.Execute;
    finally
      cmd.Free;
      ClosePG;
    end;
  end;
end;

procedure TBackupExecuteObject.Execute(ConsoleThread: TmnConsoleThread);
var
  cmd: TmncPGCommand;
begin
  if CSProducts then
  begin
    OpenPG(Database);
    cmd := PGSession.CreateCommand as TmncPGCommand;
    try
      ConsoleThread.WriteString(' ' + Database);
      cmd.SQL.Text := 'insert into "System" ("SysSection", "SysIdent", "SysValue") values (''Backup'', ''LastBackupDate'', ?SysValue)';
      cmd.SQL.Add('ON CONFLICT ("SysSection", "SysIdent") DO UPDATE SET "SysValue" = ?SysValue');
      cmd.Param['SysValue'].AsString := FormatDateTime('YYYY-MM-DD:HH:MM:SS', Now);
      cmd.Execute;
    finally
      cmd.Free;
      ClosePG;
    end;
  end;
end;

{ TPGExecuteObject }

procedure TPGExecuteObject.OpenPG(vDatabase: string);
begin
  if PGConn = nil then
    PGConn := TmncPGConnection.Create;
  PGConn.UserName := UserName;
  PGConn.Password := Password;
  PGConn.Resource := vDatabase;
  PGConn.Connect;
  PGSession := PGConn.CreateSession as TmncPGSession;
end;

procedure TPGExecuteObject.ClosePG;
begin
  FreeAndNil(PGSession);
  FreeAndNil(PGConn);
end;

constructor TPGExecuteObject.Create;
begin
  inherited;
  Suffix := FormatDateTime('yyyymmddhhnnss', Now);
end;

procedure TRestoreExecuteObject.Prepare(ConsoleThread: TmnConsoleThread);
var
  cmd: TmncPGCommand;
begin
  OpenPG;
  cmd := PGSession.CreateCommand as TmncPGCommand;
  try
    ConsoleThread.WriteString('Create new Database ' + Database);
    cmd.SQL.Text := 'create database ' + Database + '_temp_' + Suffix;
    cmd.Execute;
  finally
    cmd.Free;
    ClosePG;
  end;
end;

procedure TRestoreExecuteObject.Execute(ConsoleThread: TmnConsoleThread);
var
  cmd: TmncPGCommand;
begin
  OpenPG;
  cmd := PGSession.CreateCommand as TmncPGCommand;
  try
    ConsoleThread.WriteString('Renaming databases ' + Database);
    cmd.SQL.Text := 'SELECT datname as name FROM pg_database';
    cmd.SQL.Add('WHERE datistemplate = false and datname = ''' + Database + '''');
    if cmd.Execute then
    begin
      cmd.SQL.Text := 'alter database ' + Database + ' rename to "' + Database + '.old_' + Suffix + '"';
      cmd.Execute;
    end;
    ConsoleThread.WriteString('Rename new Database ' + Database);
    cmd.SQL.Text := 'alter database "' + Database + '_temp_' + Suffix + '" rename to ' + Database;
    ConsoleThread.WriteString('Renamed database ' + Database);
    cmd.Execute;
  finally
    cmd.Free;
    ClosePG;
  end;

  if CSProducts then
  begin
    OpenPG(Database);
    cmd := PGSession.CreateCommand as TmncPGCommand;
    try
      ConsoleThread.WriteString(' ' + Database);
      cmd.SQL.Text := 'insert into "System" ("SysSection", "SysIdent", "SysValue") values (''Backup'', ''LastRestoreDate'', ?SysValue)';
      cmd.SQL.Add('on conflict ("SysSection", "SysIdent") do update set "SysValue" = ?SysValue');
      cmd.Param['SysValue'].AsString := FormatDateTime('YYYY-MM-DD:HH:MM:SS', Now);
      cmd.Execute;
    finally
      cmd.Free;
      ClosePG;
    end;
  end;
end;

procedure TMainForm.RestoreDatabase(DB: string);
var
  o: TRestoreExecuteObject;
  filename, cmd: string;
begin
  o := TRestoreExecuteObject.Create;
  o.UserName := UserNameEdit.Text;
  o.Password := PasswordEdit.Text;
  o.CSProducts := CSProductsChk.Checked;
  o.Database := DB;
  filename := Application.Location + DB + '.backup';
  cmd := '--host localhost --port 5432 --username "' + UserNameEdit.Text + '" --dbname "' + DB + '"_temp_' + o.Suffix + ' --password --verbose "' + filename + '"';
  Launch('Restore: '+ DB, 'pg_restore.exe', cmd, PasswordEdit.Text, o);
end;

procedure TMainForm.BackupDatabase(DB: string);
var
  filename, cmd: String;
  o: TBackupExecuteObject;
begin
  o := TBackupExecuteObject.Create;
  o.UserName := UserNameEdit.Text;
  o.Password := PasswordEdit.Text;
  o.CSProducts := CSProductsChk.Checked;
  o.Database := DB;
  //"SET PGPASSWORD=<password>"
  filename := Application.Location + DB + '.backup';
  cmd := '';
  cmd := cmd + ' -v --host localhost --port 5432 --password --username "' + UserNameEdit.Text + '"';
  cmd := cmd + ' --format custom --compress=9 --blobs --file "' + filename + '" "' + DB + '"';
  //cmd := cmd + ' --format tar --blobs --file "' + filename + '" "' + DB + '"';
  Launch('Backup: ' + DB, 'pg_dump.exe', cmd, PasswordEdit.Text, o);
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
end;

procedure TMainForm.RestoreBtn1Click(Sender: TObject);
begin
  if BackupDatabasesList.ItemIndex >= 0 then
    RestoreDatabase(BackupDatabasesList.Items[BackupDatabasesList.ItemIndex]);
end;

procedure TMainForm.RestoreBtnClick(Sender: TObject);
var
  i: Integer;
begin
  for i := 0 to BackupDatabasesList.Items.Count - 1 do
  begin
    RestoreDatabase(BackupDatabasesList.Items[i]);
  end;
end;

procedure TMainForm.Log(S: String);
begin
  LogEdit.Lines.Add(S);
  LogEdit.CaretY := LogEdit.Lines.Count;
end;

procedure TMainForm.ConsoleTerminated(Sender: TObject);
begin
  if ConsoleThread.Status = 0 then
    Log(ConsoleThread.Message + ' Done')
  else
    Log('error');
  FreeAndNil(ConsoleThread);
  Resume;
end;

procedure TMainForm.EnumDatabases(vOld: Boolean);
var
  cmd: TmncPGCommand;
begin
  Databases.Clear;
  cmd := PGSession.CreateCommand as TmncPGCommand;
  try
    cmd.SQL.Text := 'SELECT datname as name FROM pg_database';
    cmd.SQL.Add('WHERE datistemplate = false');
    if vOld then
      cmd.SQL.Add('and ')
    else
      cmd.SQL.Add('and not ');
    cmd.SQL.Add('(datname like ''%_old%''');
    cmd.SQL.Add('or datname like ''%.old%''');
    cmd.SQL.Add('or datname like ''%.temp%''');
    cmd.SQL.Add('or datname like ''%_temp%'')');
    cmd.SQL.Add('order by datname');
    if cmd.Execute then
    begin
      while not cmd.Done do
      begin
        Databases.Add(cmd.Field['name'].AsString);
        //Log(cmd.Field['name'].AsString);
        cmd.Next;
      end;
    end;
  finally
    cmd.Free;
  end;
end;

procedure TMainForm.OpenPG(vDatabase: string);
begin
  if PGConn = nil then
    PGConn := TmncPGConnection.Create;
  PGConn.UserName := UserNameEdit.Text;
  PGConn.Password := PasswordEdit.Text;
  PGConn.Resource := vDatabase;
  PGConn.Connect;
  PGSession := PGConn.CreateSession as TmncPGSession;
end;

procedure TMainForm.ClosePG;
begin
  FreeAndNil(PGSession);
  FreeAndNil(PGConn);
end;

procedure TMainForm.Launch(vMessage, vExecutable, vParameters, vPassword: String; vExecuteObject: TExecuteObject);
var
  aConsoleThread: TmnConsoleThread;
begin
  aConsoleThread := TmnConsoleThread.Create(vExecutable, vParameters, @Log);
  aConsoleThread.OnTerminate := @ConsoleTerminated;
  aConsoleThread.Password := vPassword;
  aConsoleThread.Message := vMessage;
  aConsoleThread.ExecuteObject := vExecuteObject;
  PoolThread.Add(aConsoleThread);
  Resume;
end;

procedure TMainForm.Resume;
begin
  if (PoolThread.Count > 0) then
  begin
    if (ConsoleThread = nil) then
    begin
      ConsoleThread := PoolThread.Extract(PoolThread.Last) as TmnConsoleThread;
      Log(ConsoleThread.Message);
      InfoPanel.Caption := ConsoleThread.Message;
      Application.ProcessMessages;
      ConsoleThread.Start;
    end
  end
  else
  begin
    Log('All done');
    InfoPanel.Caption := '';
  end;
end;

constructor TMainForm.Create(TheOwner: TComponent);
var
  i: Integer;
  reg: TRegistry;
  ini: TIniFile;
  s: string;
begin
  inherited Create(TheOwner);
  PoolThread := TObjectList.Create;
  reg := TRegistry.Create(KEY_READ);
  reg.RootKey := HKEY_LOCAL_MACHINE;
  //if reg.OpenKey('SOFTWARE\PostgreSQL\', False)
  reg.Free;

  ini := TIniFile.Create(Application.Location + 'pgtools.ini');
  CSProductsChk.Checked := ini.ReadBool('options', 'CSProducts', True);
  UserNameEdit.Text := ini.ReadString('options', 'username', 'postgres');
  PasswordEdit.Text := ini.ReadString('options', 'password', '');
  i := 0;
  while true do
  begin
    s := ini.ReadString('data', 'data' + IntToStr(i), '');
    if s = '' then
      break;
    BackupDatabasesList.Items.Add(s);
    Inc(i);
  end;
  ini.Free;

  Databases := TStringList.Create;
end;

destructor TMainForm.Destroy;
var
  i: Integer;
  ini: TIniFile;
begin
  PoolThread.Clear;
  if ConsoleThread <> nil then
  begin
    ConsoleThread.Terminate;
    ConsoleThread.WaitFor;
    ConsoleThread.Free;
  end;
  ClosePG;
  FreeAndNil(Databases);

  ini := TIniFile.Create(Application.Location + 'pgtools.ini');
  ini.WriteBool('options', 'CSProducts', CSProductsChk.Checked);
  ini.WriteString('options', 'username', UserNameEdit.Text);
  ini.WriteString('options', 'password', PasswordEdit.Text);
  ini.EraseSection('data');
  for i := 0 to BackupDatabasesList.Items.Count -1 do
    ini.WriteString('data', 'data'+InttoStr(i), BackupDatabasesList.Items[i]);
  ini.Free;
  FreeAndNil(PoolThread);
  inherited;
end;

end.

