@echo off
setlocal EnableExtensions

rem ============================================================
rem  Drag any .apk onto this file -> copy it to the phone and open
rem  the MIUI package installer on it.
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

rem ---- copy to a fixed ASCII name on the phone ----
rem  The remote name is deliberately constant rather than the dropped file's
rem  own name. The path has to survive cmd -> adb -> the device shell, and the
rem  device shell re-splits it: a filename containing a space breaks the URI,
rem  and am start then swallows the tail as a package argument. Quoting through
rem  all three layers is fragile, so sidestep it with a name that needs no
rem  quoting. Constant also means each APK overwrites the previous one instead
rem  of piling up in Download.
rem  The old copy is removed first so a failed push cannot leave a stale APK
rem  behind for the installer to pick up.
"%ADB%" -s %SERIAL% shell "rm -f /sdcard/Download/_install.apk" >nul 2>&1
"%ADB%" -s %SERIAL% push "%APK%" /sdcard/Download/_install.apk >nul 2>&1
if errorlevel 1 exit /b 1

rem ---- hand off to the MIUI package installer ----
rem  With the display asleep this still creates the installer activity; it just
rem  is not visible until the screen is woken, at which point it is already in
rem  front. Bringing the screen up from here is not possible: the obvious
rem  "input keyevent 224" is refused with a SecurityException because MIUI
rem  blocks shell input injection unless the separate developer option
rem  "USB debugging (Security settings)" is enabled.
"%ADB%" -s %SERIAL% shell "am start -a android.intent.action.VIEW -d file:///sdcard/Download/_install.apk -t application/vnd.android.package-archive" >nul 2>&1

exit /b 0
