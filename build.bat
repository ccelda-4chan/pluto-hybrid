@echo off
REM Build script for VanguardSpoofer kernel driver
REM Requires: Windows Driver Kit (WDK) or Visual Studio with WDK

echo ==========================================
echo  VanguardSpoofer Kernel Driver Build
echo ==========================================
echo.

REM Check for Visual Studio with WDK
set VS_PATH=
set MSBUILD_PATH=

REM Try to find MSBuild from various locations
if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe" (
    set MSBUILD_PATH="%ProgramFiles%\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
    goto :found_msbuild
)

if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe" (
    set MSBUILD_PATH="%ProgramFiles%\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe"
    goto :found_msbuild
)

if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe" (
    set MSBUILD_PATH="%ProgramFiles(x86)%\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe"
    goto :found_msbuild
)

if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe" (
    set MSBUILD_PATH="%ProgramFiles(x86)%\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
    goto :found_msbuild
)

echo [ERROR] MSBuild not found!
echo.
echo Please install one of the following:
echo   1. Visual Studio 2022 with 'Desktop development with C++'
echo   2. Visual Studio 2019 with 'Desktop development with C++'
echo   3. Visual Studio Build Tools with WDK
echo.
echo Or run: VanguardKernel-AutoBuild.ps1 for automatic installation
echo.
pause
exit /b 1

:found_msbuild
echo [OK] Found MSBuild at: %MSBUILD_PATH%
echo.

REM Create output directory
if not exist "Build" mkdir "Build"
if not exist "Build\Release" mkdir "Build\Release"
if not exist "Build\Debug" mkdir "Build\Debug"

echo Building VanguardSpoofer driver...
echo Configuration: Release
echo Platform: x64
echo.

REM Build the driver
%MSBUILD_PATH% "Driver\VanguardSpoofer.vcxproj" /p:Configuration=Release /p:Platform=x64 /p:OutDir=..\Build\Release\

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Build failed!
    echo.
    echo Common issues:
    echo   - Windows Driver Kit (WDK) not installed
    echo   - WDK version mismatch with Visual Studio
    echo   - Missing KMDF 1.33 or higher
echo.
    pause
    exit /b 1
)

echo.
echo ==========================================
echo  Build Successful!
echo ==========================================
echo.
echo Output: Build\Release\VanguardSpoofer.sys
echo Driver is ready for loading with kdmapper
echo.

REM Check for driver file
if exist "Build\Release\VanguardSpoofer.sys" (
    echo [OK] Driver file created successfully
    dir "Build\Release\VanguardSpoofer.sys"
) else (
    echo [WARNING] Driver file not found in expected location
)

echo.
echo Next steps:
echo   1. Sign driver with test certificate (optional)
echo   2. Load with: kdmapper VanguardSpoofer.sys
echo   3. Or use: InstantKernel-Spoofer.ps1
echo.
pause
