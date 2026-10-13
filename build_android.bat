@echo off
REM Builds the Android test APK: dist\nz_probe_android.apk
REM Requires Android Studio / Android SDK (see README.md). Run build_windows.bat first once.
setlocal
cd /d "%~dp0"

if not exist android (
  call flutter create . --platforms=windows,android --project-name nz_probe --org ir.nisoc.desalting
  if errorlevel 1 goto :fail
)
call flutter pub get
if errorlevel 1 goto :fail
call flutter build apk --release
if errorlevel 1 goto :fail

if not exist dist mkdir dist
copy /y "build\app\outputs\flutter-apk\app-release.apk" "dist\nz_probe_android.apk" >nul
echo DONE: dist\nz_probe_android.apk
pause
exit /b 0

:fail
echo [FAILED] Copy the messages above and send them to Claude.
pause
exit /b 1
