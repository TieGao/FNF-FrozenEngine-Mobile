@echo off
setlocal EnableExtensions

rem ============================================================
rem  Drag any .apk onto this file -> install it on the phone with
rem  "adb install -r" (overwrite in place, keeps app data).
rem
rem  No argument: falls back to the latest FrozenEngine build output.
rem  Silent by design: no prompts, no console output.
rem ============================================================

rem ---- input ----
set "APK=%~f1"
if not defined APK set "APK=D:\FNF-FrozenEngine-Moblie\export\release\android\bin\app\build\outputs\apk\release\FrozenEngine-release.apk"
if not exist "%APK%" exit /b 1

rem ---- locate adb ----
set "ADB="
if exist "F:\Android\Sdk\platform-tools\adb.exe" set "ADB=F:\Android\Sdk\platform-tools\adb.exe"
if not defined ADB if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
if not defined ADB for /f "delims=" %%i in ('where adb 2^>nul') do if not defined ADB set "ADB=%%i"
if not defined ADB exit /b 1

rem ---- pick device: prefer the Redmi 14C, else first online device ----
set "SERIAL="
for /f "skip=1 tokens=1,2" %%a in ('"%ADB%" devices 2^>nul') do if "%%b"=="device" if /i "%%a"=="4TKRSOYXJVZ5PNLJ" set "SERIAL=%%a"
if not defined SERIAL for /f "skip=1 tokens=1,2" %%a in ('"%ADB%" devices 2^>nul') do if "%%b"=="device" if not defined SERIAL set "SERIAL=%%a"
if not defined SERIAL exit /b 1

rem ---- install (overwrite, keep data) ----
rem  -r : reinstall, keeping existing app data
rem  -d : allow version downgrade (handy when you rebuild with a lower versionCode)
rem  -g : grant all runtime permissions up front (avoids first-launch dialogs)
rem  Drop -d / -g if you don't want that behaviour.
"%ADB%" -s %SERIAL% install -r -d -g "%APK%"

exit /b 0