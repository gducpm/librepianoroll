@echo off
setlocal enabledelayedexpansion

echo ========================================================
echo LibrePianoRoll - FluidSynth GDExtension Compiler
echo ========================================================

:: Detect MSVC vcvars64.bat
set "VCVARS="
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat" (
    set "VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" (
    set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
) else if exist "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat" (
    set "VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat"
)

if "%VCVARS%"=="" (
    echo [ERROR] MSVC vcvars64.bat not found. Please run from a Developer Command Prompt.
    pause
    exit /b 1
)

echo [INFO] Initializing MSVC x64 environment...
call "%VCVARS%"

:: Target directories
set "PROJECT_ROOT=%~dp0.."
cd /d "%PROJECT_ROOT%"

if not exist "addons\fluidsynth\bin" mkdir "addons\fluidsynth\bin"

echo [INFO] Compiling godot_fluidsynth.dll...
cl /LD /MD /O2 /EHsc /I. /Ibuild\fluidsynth\fluidsynth-v2.6.1-win10-x64-cpp11\include src\fluidsynth_bridge\fluidsynth_bridge.cpp /link /LIBPATH:build\fluidsynth\fluidsynth-v2.6.1-win10-x64-cpp11\lib libfluidsynth-3.lib /OUT:addons\fluidsynth\bin\godot_fluidsynth.dll

if %ERRORLEVEL% equ 0 (
    echo [SUCCESS] Built addons\fluidsynth\bin\godot_fluidsynth.dll successfully!
    del fluidsynth_bridge.obj fluidsynth_bridge.lib fluidsynth_bridge.exp 2>nul
) else (
    echo [ERROR] Compilation failed.
)

endlocal
