; ==============================================================================
; LibrePianoRoll - Modern NSIS Windows Installer Script
; Copyright (C) 2026  gducpm <gducpm@gmail.com>
; Licensed under the GNU Affero General Public License v3.0
; ==============================================================================

Unicode True
!include "MUI2.nsh"
!include "x64.nsh"

; --- Application Metadata ---
!define PRODUCT_NAME "LibrePianoRoll"
!ifndef VERSION
    !define VERSION "1.0.0-beta"
!endif
!define PRODUCT_PUBLISHER "LibrePianoRoll Contributors"
!define PRODUCT_WEB_SITE "https://github.com/gducpm/LibrePianoRoll"
!define PRODUCT_DIR_REGKEY "Software\Microsoft\Windows\CurrentVersion\App Paths\LibrePianoRoll.exe"
!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"

; --- Output & Compression ---
Name "${PRODUCT_NAME} ${VERSION}"
OutFile "..\build\LibrePianoRoll-Setup-v${VERSION}-x64.exe"
InstallDir "$PROGRAMFILES64\LibrePianoRoll"
InstallDirRegKey HKLM "${PRODUCT_DIR_REGKEY}" ""
RequestExecutionLevel admin

SetCompressor /SOLID lzma

; --- Interface Settings ---
!define MUI_ABORTWARNING
!define MUI_ICON "..\icon.svg"
!define MUI_UNICON "..\icon.svg"

; --- Installer Pages ---
; 1. Welcome Page
!insertmacro MUI_PAGE_WELCOME

; 2. License Page (Displays AGPLv3 License)
!define MUI_LICENSEPAGE_CHECKBOX
!insertmacro MUI_PAGE_LICENSE "..\LICENSE"

; 3. Directory Selection Page (User can customize installation folder)
!insertmacro MUI_PAGE_DIRECTORY

; 4. Installation Progress Page
!insertmacro MUI_PAGE_INSTFILES

; 5. Finish Page
!define MUI_FINISHPAGE_RUN "$INSTDIR\LibrePianoRoll.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Launch LibrePianoRoll"
!insertmacro MUI_PAGE_FINISH

; --- Uninstaller Pages ---
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

; --- Language ---
!insertmacro MUI_LANGUAGE "English"

; --- Installation Section ---
Section "MainSection" SEC01
    SetOutPath "$INSTDIR"
    SetOverwrite on

    ; Application Core Executable and Resources
    File /r "..\build\windows\*.*"
    
    ; Ensure SoundFont and default files exist
    IfFileExists "$INSTDIR\default.sf3" +2 0
        File "..\default.sf3"
    IfFileExists "$INSTDIR\default.mid" +2 0
        File "..\default.mid"
    IfFileExists "$INSTDIR\LICENSE" +2 0
        File "..\LICENSE"

    ; Native FluidSynth GDExtension libraries
    SetOutPath "$INSTDIR\addons\fluidsynth\bin"
    File /r "..\addons\fluidsynth\bin\*.*"
    SetOutPath "$INSTDIR\addons\fluidsynth"
    File "..\addons\fluidsynth\fluidsynth.gdextension"

    ; Set output path back to root for shortcut working directory
    SetOutPath "$INSTDIR"

    ; Create Start Menu Shortcuts
    CreateDirectory "$SMPROGRAMS\LibrePianoRoll"
    CreateShortcut "$SMPROGRAMS\LibrePianoRoll\LibrePianoRoll.lnk" "$INSTDIR\LibrePianoRoll.exe" "" "$INSTDIR\LibrePianoRoll.exe" 0
    CreateShortcut "$SMPROGRAMS\LibrePianoRoll\Uninstall.lnk" "$INSTDIR\Uninstall.exe" "" "$INSTDIR\Uninstall.exe" 0

    ; Create Desktop Shortcut
    CreateShortcut "$DESKTOP\LibrePianoRoll.lnk" "$INSTDIR\LibrePianoRoll.exe" "" "$INSTDIR\LibrePianoRoll.exe" 0

    ; Write Uninstaller
    WriteUninstaller "$INSTDIR\Uninstall.exe"

    ; Windows Registry Keys for Add/Remove Programs
    WriteRegStr HKLM "${PRODUCT_DIR_REGKEY}" "" "$INSTDIR\LibrePianoRoll.exe"
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayName" "${PRODUCT_NAME}"
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "UninstallString" "$INSTDIR\Uninstall.exe"
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayIcon" "$INSTDIR\LibrePianoRoll.exe"
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayVersion" "${VERSION}"
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "URLInfoAbout" "${PRODUCT_WEB_SITE}"
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
    WriteRegDWORD HKLM "${PRODUCT_UNINST_KEY}" "NoModify" 1
    WriteRegDWORD HKLM "${PRODUCT_UNINST_KEY}" "NoRepair" 1
SectionEnd

; --- Uninstallation Section ---
Section "Uninstall"
    ; Remove Shortcuts
    Delete "$DESKTOP\LibrePianoRoll.lnk"
    Delete "$SMPROGRAMS\LibrePianoRoll\LibrePianoRoll.lnk"
    Delete "$SMPROGRAMS\LibrePianoRoll\Uninstall.lnk"
    RMDir "$SMPROGRAMS\LibrePianoRoll"

    ; Remove Installed Files and Folders
    RMDir /r "$INSTDIR\addons"
    Delete "$INSTDIR\LibrePianoRoll.exe"
    Delete "$INSTDIR\LibrePianoRoll.pck"
    Delete "$INSTDIR\default.sf3"
    Delete "$INSTDIR\default.mid"
    Delete "$INSTDIR\LICENSE"
    Delete "$INSTDIR\Uninstall.exe"
    RMDir "$INSTDIR"

    ; Remove Registry Keys
    DeleteRegKey HKLM "${PRODUCT_DIR_REGKEY}"
    DeleteRegKey HKLM "${PRODUCT_UNINST_KEY}"
SectionEnd
