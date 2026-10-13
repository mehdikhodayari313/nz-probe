@echo off
REM ============================================================
REM  NZ Probe - Windows build script
REM  Builds the test app and packages it as dist\nz_probe_windows.zip
REM  Run this on YOUR development PC (not the company PC).
REM ============================================================
setlocal
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Flutter is not installed or not in PATH. See README.md, step 1.
  goto :fail
)

if exist windows goto :packages
echo.
echo === [1/6] Creating platform folders: windows, android ===
call flutter create . --platforms=windows,android --project-name nz_probe --org ir.nisoc.desalting
if errorlevel 1 goto :fail
REM Window title
powershell -NoProfile -Command "(Get-Content 'windows\runner\main.cpp') -replace 'L\"nz_probe\"', 'L\"NZ Probe - Desalting Price Bank\"' | Set-Content 'windows\runner\main.cpp'"

:packages
echo.
echo === [2/6] Downloading packages ===
call flutter pub get
if errorlevel 1 goto :fail

echo.
echo === [3/6] Static analysis ===
call flutter analyze
if errorlevel 1 (
  echo [WARNING] Analyzer reported issues. Send the output above to Claude. Continuing...
)

echo.
echo === [4/6] Unit tests ===
call flutter test
if errorlevel 1 goto :fail

echo.
echo === [5/6] Release build ===
call flutter build windows --release
if errorlevel 1 goto :fail

set "OUT=build\windows\x64\runner\Release"
if not exist "%OUT%" set "OUT=build\windows\runner\Release"
if not exist "%OUT%\nz_probe.exe" (
  echo [ERROR] Build output not found.
  goto :fail
)

REM Bundle the Visual C++ runtime next to the exe, so nothing has to be installed on the company PC.
for %%F in (msvcp140.dll vcruntime140.dll vcruntime140_1.dll) do (
  if exist "%SystemRoot%\System32\%%F" copy /y "%SystemRoot%\System32\%%F" "%OUT%\" >nul
)

echo.
echo === [6/6] Packaging ===
if not exist dist mkdir dist
powershell -NoProfile -Command "Compress-Archive -Path '%OUT%\*' -DestinationPath 'dist\nz_probe_windows.zip' -Force"
if errorlevel 1 goto :fail

powershell -NoProfile -Command "Get-FileHash 'dist\nz_probe_windows.zip' -Algorithm SHA256 | ForEach-Object { $_.Hash } | Set-Content 'dist\nz_probe_windows.zip.sha256'"

echo.
echo ============================================================
echo  DONE: dist\nz_probe_windows.zip
echo  SHA-256 (for IT): dist\nz_probe_windows.zip.sha256
echo  Copy the zip to the company PC, extract it, run nz_probe.exe
echo ============================================================
pause
exit /b 0

:fail
echo.
echo [FAILED] Copy the messages above and send them to Claude.
pause
exit /b 1
