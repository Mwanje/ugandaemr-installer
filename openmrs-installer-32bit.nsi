;--------------------------------
;Defines
!include "MUI2.nsh"
!include "Registry.nsh"
!include "Sections.nsh"

Name "Uganda EMR"
!define JavaRegKey 'HKLM "Software\JavaSoft\Java Runtime Environment" ""'
!define MUI_ICON "software/favicon.ico"
!define MUI_UNICON "software/favicon.ico"

Var SMDir ;Start menu folder
Var errorsrc
;!define MUI_STARTMENUPAGE_DEFAULTFOLDER "MY Program" ;Default, name is used if not defined
!define MUI_HEADERIMAGE_BITMAP "software\logo.bmp"
!define MUI_HEADERIMAGE_RIGHT
RequestExecutionLevel admin

;--------------------------------
;Interface Settings

  !define MUI_ABORTWARNING

;--------------------------------
;Pages
  !insertmacro MUI_PAGE_LICENSE "includes\license.txt"
  !insertmacro MUI_PAGE_COMPONENTS
  !insertmacro MUI_PAGE_DIRECTORY
  !insertmacro MUI_PAGE_STARTMENU 0 $SMDir
  !insertmacro MUI_PAGE_INSTFILES
  !insertmacro MUI_UNPAGE_CONFIRM
  !insertmacro MUI_UNPAGE_INSTFILES

;--------------------------------
;Languages
  !insertmacro MUI_LANGUAGE "English"
;--------------------------------

InstallDir "$PROGRAMFILES\UgandaEMR"	;This line creates a default location for the installation. Note that $PROGRAMFILES is a constant value provided by NSIS
DirText "OpenMrs will install in this directory"
!define instDirectory "$PROGRAMFILES\UgandaEMR"


OutFile "ugandaemr2-1-0-installer-32bit.exe"

;-------------------------Splash Screen For installer--------------------------------
  XPStyle on
Function .onInit

UserInfo::GetAccountType
pop $0
${If} $0 != "admin" ;Require admin rights on NT4+
    MessageBox mb_iconstop "Administrator rights required!"
    SetErrorLevel 740 ;ERROR_ELEVATION_REQUIRED
    Quit
${EndIf}
	# the plugins dir is automatically deleted when the installer exits
	InitPluginsDir
	File /oname=$PLUGINSDIR\splash.bmp "includes\splash.bmp"
     advsplash::show 5000 600 400 -1 $PLUGINSDIR\splash

	Pop $0 ; $0 has '1' if the user closed the splash screen early,
			; '0' if everything closed normally, and '-1' if some error occurred.
FunctionEnd
;===========================================Installer Sections============================================
;Installing Java
Section 'Java Runtime' SecJava
SectionIn RO
  SetOutPath '$TEMP'
  SetOverwrite on
  File 'software\jdk-8u131.exe'
  ExecWait '"$TEMP\jdk-8u131.exe"' $0
  DetailPrint '..Java Runtime Setup exit code = $0'
  Delete '$TEMP\jdk-8u131.exe'
  ; include for some of the windows messages defines
  !include "winmessages.nsh"
  ; HKLM (all users) vs HKCU (current user) defines
  !define env_hklm 'HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"'
  !define env_hkcu 'HKCU "Environment"'
  ; set variable
  WriteRegStr ${env_hklm} JAVA_HOME "$PROGRAMFILES\Java\jdk1.8.0_131"
  WriteRegStr ${env_hklm} JRE_HOME "$PROGRAMFILES\Java\jre1.8.0_131"
  ; make sure windows knows about the change
  WriteRegStr ${env_hkcu} JAVA_HOME "$PROGRAMFILES\Java\jdk1.8.0_131"
  WriteRegStr ${env_hkcu} JRE_HOME "$PROGRAMFILES\Java\jre1.8.0_131"
  WriteRegStr ${env_hkcu} Path "%JAVA_HOME%\bin;"
  WriteRegDWORD  HKCU "SOFTWARE\JavaSoft\Java Update\Policy" 'EnableJavaUpdate' 0
  SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000
SectionEnd


;Installing Mysql
Section 'Mysql 5.5.28' SecMysql
  SectionIn RO
  SetOutPath '$TEMP'
  SetOverwrite on
  ;MySQL Server 5.5
  File 'software\mysql-5.5.28.msi'
  ExecWait '"msiexec" /i "$TEMP\mysql-5.5.28.msi" /promptrestart /passive' $0 ;
  DetailPrint '..Mysql 5.5.28 Setup exit code = $0'
  Delete '$TEMP\mysql-5.5.28.msi'
  ExecWait '$PROGRAMFILES\MYSQL\MySQL Server 5.5\bin\mysqlinstanceconfig.exe' $0
SectionEnd

;Changing mysql max allowed packet
Section "MYSQLCONFFILE" SecMYSQLCONFFILE
DetailPrint 'Stopping mysql'
nsExec::Exec 'net stop MySQL' $0
DetailPrint 'MYSQL Stopped  $0'
SectionIn RO
SetOutPath "C:\Program Files\MySQL\MySQL Server 5.5"
File   "includes\databases\default\my.ini"
DetailPrint 'starting mysql'
nsExec::Exec 'net start MySQL' $0
DetailPrint 'MYSQL Started  $0'
SectionEnd

;Creating openmrs user
Section  -createOpenmrsUser
nsExec::Exec 'C:\Program Files\MySQL\MySQL Server 5.5\bin\mysql  -uroot -e "CREATE USER $\'openmrs$\'@$\'localhost$\' IDENTIFIED BY $\'openmrs$\'"'
nsExec::Exec 'C:\Program Files\MySQL\MySQL Server 5.5\bin\mysql  -uroot -e "GRANT ALL ON *.* TO $\'openmrs$\'@$\'localhost$\'"'
nsExec::Exec 'C:\Program Files\MySQL\MySQL Server 5.5\bin\mysql  -uroot -e "SET PASSWORD FOR  $\'root$\'@$\'localhost$\' = PASSWORD($\'openmrs$\')"'
nsExec::Exec 'C:\Program Files\MySQL\MySQL Server 5.5\bin\mysql  -uroot -e "FLUSH PRIVILEGES"'
SectionEnd



;Generating  openmrs 1.11.6 database
Section -defaultDatabase
    DetailPrint "Running import"

StrCmp $createdb 1 importdbs
nsExec::Exec 'C:\Program Files\MySQL\MySQL Server 5.5\bin\mysql  -uopenmrs -popenmrs -e "CREATE database openmrs"'
nsExec::Exec 'C:\Program Files\MySQL\MySQL Server 5.5\bin\mysql  -uopenmrs -popenmrs -e "CREATE database openmrs_backup"'
;nsExec::Exec 'C:\Program Files\MySQL\MySQL Server 5.5\bin\mysql  -uroot -e "SET PASSWORD FOR $\'root$\'@$\'localhost$\' =$\'openMRS$\'"'
 SetOutPath "$DESKTOP\"
 File 'includes\databases\default\new-install.sql'
  DetailPrint '..Add default database exit code = $0'
   importdbs:
      DetailPrint "SQL file import"
      ExecWait '"C:\Program Files\MySQL\MySQL Server 5.5\bin\mysql" --user=openmrs --password=openmrs --execute="source $DESKTOP\new-install.sql" openmrs' $2
      StrCmp $2 1 0 endinst
      StrCpy $errorsrc "File import error"
      Goto abortinst

      abortinst:
          DetailPrint "                         "
          DetailPrint "$\n An error occured ! $\n"
          DetailPrint "  $errorsrc              "
          DetailPrint "                         "

   endinst:
   Delete '$DESKTOP\new-install.sql'
   
   SetOverwrite on
   SetOutPath "C:\Application Data"
   File /r "includes\Configurations\OpenMRS"
SectionEnd

Section -runTimeProperties
;Copying OpenMRS Application Data directory to system32 directory
	!define MB_OK 0x00000000
	!define MB_ICONINFORMATION 0x00000040
	FileOpen $4 "$DESKTOP\configuemr.bat" w
	FileWrite $4 'xcopy /s /e /y "C:\Application Data\OpenMRS" "C:\Windows\System32\config\systemprofile\Application Data\OpenMRS"'
	FileClose $4
	DetailPrint 'Starting to backup openmrs database'
	ExpandEnvStrings $0 %COMSPEC%
	ExecWait '"$0" /C "$DESKTOP\configuemr.bat"'
	Delete '$DESKTOP\cconfiguemr.bat'
SectionEnd

;Installing Tomcat
Section 'Tomcat 7.0.65' SecTomcat
ClearErrors
ReadRegStr $0 HKLM SYSTEM\CurrentControlSet\Services\UgandaEMRTomcat "ImagePath"
${If} ${Errors}
  SetOutPath '$TEMP'
  SetOverwrite on
  File 'includes\software\apache-tomcat-7.0.68.exe'
  ExecWait '$TEMP\apache-tomcat-7.0.68.exe /S /D=C:\Program Files\UgandaEMR\UgandaEMRTomcat' $0
  DetailPrint '..Java Runtime Setup exit code = $0'
  ;SetOutPath "C:\Program Files\UgandaEMR\"
;File /r "software64\apache-tomcat"
nsExec::Exec '"C:\Program Files\UgandaEMR\UgandaEMRTomcat\bin\Tomcat7" //IS//UgandaEMRTomcat --DisplayName="UgandaEMRTomcat" --Description="This Service starts UgandaEMRTomcat" --Install="C:\Program Files\UgandaEMR\UgandaEMRTomcat\bin\UgandaEMRTomcat.exe" --Jvm="C:\Program Files\Java\jre1.8.0_131\bin\server\jvm.dll" --StartMode=jvm --StopMode=jvm --StartClass=org.apache.catalina.startup.Bootstrap --StartParams=start --StopClass=org.apache.catalina.startup.Bootstrap --StopParams=stop --Classpath="C:\Program Files\UgandaEMR\UgandaEMRTomcat\bin\bootstrap.jar;C:\Program Files\UgandaEMR\UgandaEMRTomcat\bin\tomcat-juli.jar" --StdError=auto --StdOutput=auto --LogPrefix=commons-daemon --LogLevel=Info --User=root --Password=openmrs --JvmMs=256 --JvmMx=1024 --StartPath="C:\Program Files\UgandaEMR\UgandaEMRTomcat" --StopPath="C:\Program Files\UgandaEMR\UgandaEMRTomcat" --LogPath="C:\Program Files\UgandaEMR\UgandaEMRTomcat\logs" --Startup=auto'
nsExec::Exec '"C:\Program Files\UgandaEMR\UgandaEMRTomcat\bin\UgandaEMRTomcat" //US//UgandaEMRTomcat ++JvmOptions="-XX:MaxPermSize=1024m" ++JvmOptions="-Xms256m" ++JvmOptions="-Xmx1024m" ++JvmOptions="-Dorg.apache.el.parse.SKIP_IDENTIFIER_CHECK=true"'
Rename "C:\Program Files\UgandaEMR\UgandaEMRTomcat\bin\Tomcat7.exe" "C:\Program Files\UgandaEMR\UgandaEMRTomcat\bin\UgandaEMRTomcat.exe"
Rename "C:\Program Files\UgandaEMR\UgandaEMRTomcat\bin\Tomcat7w.exe" "C:\Program Files\UgandaEMR\UgandaEMRTomcat\bin\UgandaEMRTomcatw.exe"
SetOutPath 'C:\Program Files\UgandaEMR\UgandaEMRTomcat\conf'
SetOverwrite on
File 'includes\scripts\server.xml'
Delete '$TEMP\apache-tomcat-7.0.68.exe'
${Else}  
	MESSAGEBOX MB_OK "UgandaEMRTomcat is installed at $0 It will be skipped"
${EndIf}
SectionEnd

;Installing war file
Section "UgandaEMR" SecUgandaEMR
SectionIn RO
SetOutPath "C:\Program Files\UgandaEMR\UgandaEMRTomcat\webapps"
File   "includes\warfile\openmrs.war"
SectionEnd

;Copying Scripts
Section -scripts
SetOutPath "C:\Program Files\UgandaEMR"
File /r "includes\scripts"
SectionEnd

;Installing Firefox
Section 'Firefox' SecBrowser
  SectionIn RO
  SetOutPath '$TEMP'
  SetOverwrite on
  File 'software64\firefox67.exe'
  ExecWait '"$TEMP\firefox67.exe"' $0
  DetailPrint '..Fire Fox Setup exit code = $0'
  Delete '$TEMP\firefox67.exe'
SectionEnd


;Installing HeidiSQL
Section 'HeidiSQL' SQLBrowser
   SectionIn RO
  SetOutPath '$TEMP'
  SetOverwrite on
  File 'includes\software\HeidiSQL9.3.0.exe'
  ExecWait '"$TEMP\HeidiSQL9.3.0.exe"' $0
  DetailPrint '..HeidiSQL Setup exit code = $0'
  Delete '$TEMP\HeidiSQL9.3.0.exe'
SectionEnd

;Create Desktop icons
Section "Desktop Shortcut" SecDesktopIcon
SectionIn RO
SetOutPath "$DESKTOP\"
File  "includes\shortcuts\Access UgandaEMR.url"
SectionIn RO
SetOutPath "$DESKTOP\"
File  "includes\shortcuts\Start FingerPrint Scanner.lnk"
SectionEnd

;Setting Start menu
Section -StartMenu
!insertmacro MUI_STARTMENU_WRITE_BEGIN 0 ;This macro sets $SMDir and skips to MUI_STARTMENU_WRITE_END if the "Don't create shortcuts" checkbox is checked...
CreateDirectory "$SMPrograms\$SMDir"
SetOutPath "$SMPrograms\$SMDir"
File  "includes\shortcuts\Start UgandaEMR.lnk"
File  "includes\shortcuts\Stop UgandaEMR.lnk"
File  "includes\shortcuts\Backup UgandaEMR Database.lnk"
File  "includes\shortcuts\Restore UgandaEMR Database.lnk"
File  "includes\shortcuts\Upgrade UgandaEMR War File.lnk"
File  "includes\shortcuts\Correct Database Path.lnk"
File  "includes\shortcuts\Launch Tomcat Manager.lnk"
File  "includes\shortcuts\uninstall.lnk"
File  "includes\shortcuts\Access UgandaEMR.url"
File  "includes\shortcuts\Start FingerPrint Scanner.lnk"
File  "includes\shortcuts\Excecute Mysql Script.lnk"
File  "includes\shortcuts\Clean UgandaEMR.lnk"
!insertmacro MUI_STARTMENU_WRITE_END
SectionEnd

Section -post

SetOutPath "C:\Program Files\UgandaEMR"

File  "uninstaller.exe"
  ; Write the installation path and uninstall keys into the registry
  WriteRegStr HKLM "Software\UgandaEMR" "C:\Program Files\UgandaEMR" $INSTDIR
  
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\UgandaEMR" \
			"DisplayName" "UgandaEMR (remove only)"

  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\UgandaEMR" \
			"DisplayIcon" '"C:\Program Files\UgandaEMR\scripts\access.ico"'
  
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\UgandaEMR" \
			"UninstallString" '"C:\Program Files\UgandaEMR\uninstaller.exe"'

  WriteUninstaller "C:\Program Files\UgandaEMR\uninstaller.exe"   ; build uninstall program
  
  SetOverwrite on
  File  "uninstaller.exe"
SectionEnd

;Restore UgandaEMR DataBase
Section /o 'Restore Existing UgandaEMR Database' RestoreDatabase
  ExecWait '"C:\Program Files\UgandaEMR\scripts\restore.exe"' $0
  DetailPrint '..Restored UgandaEMR Database exit code = $0'
SectionEnd

;Start Tomcat and Lauch UgandaEMR in Browser
Section -launch
DetailPrint 'Starting Tomcat $0'
nsExec::Exec 'net start UgandaEMRTomcat'
DetailPrint 'Tomcat Started $0'
strcpy $R0 "http://localhost:8081/openmrs"
Exec '"$PROGRAMFILES\Mozilla Firefox\firefox67.exe" "$R0"'
Quit
SectionEnd
;--------------------------------