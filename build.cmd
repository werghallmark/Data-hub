@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM QuantDesk DataHub build + package script (Windows cmd)
REM - Restores, builds, tests
REM - Publishes Service + FrameApi + ControlPanel (if present)
REM - Packages a release ZIP:
REM     QuantDesk_DataHub_v1.2_<build>.zip
REM ============================================================

REM Always run from repo root
cd /d "%~dp0" || (echo ERROR: cannot cd to repo root & exit /b 1)

REM ---- Find solution file (prefer QuantDesk.DataHub.sln) ----
set "SLN="
if exist "QuantDesk.DataHub.sln" set "SLN=QuantDesk.DataHub.sln"
if not defined SLN (
  for %%F in (*.sln) do (
    if not defined SLN set "SLN=%%F"
  )
)
if not defined SLN (
  echo ERROR: No .sln found in repo root.
  echo Expected QuantDesk.DataHub.sln or any *.sln.
  exit /b 1
)

REM ---- Determine build id ----
set "BUILD_ID="
if not "%GITHUB_RUN_NUMBER%"=="" (
  set "BUILD_ID=%GITHUB_RUN_NUMBER%"
) else (
  REM Local build: YYYYMMDD_HHMMSS
  for /f "tokens=1-3 delims=/- " %%a in ("%date%") do (
    set "d1=%%a"
    set "d2=%%b"
    set "d3=%%c"
  )
  for /f "tokens=1-3 delims=:." %%a in ("%time%") do (
    set "t1=%%a"
    set "t2=%%b"
    set "t3=%%c"
  )
  set "t1=!t1: =0!"
  set "BUILD_ID=!d3!!d2!!d1!_!t1!!t2!!t3!"
)

set "OUT_ZIP=QuantDesk_DataHub_v1.2_%BUILD_ID%.zip"
set "STAGE=_release_stage"
set "PUBLISH=%STAGE%\publish"

REM ---- Clean staging ----
if exist "%STAGE%" rmdir /s /q "%STAGE%" >nul 2>&1
mkdir "%PUBLISH%" >nul 2>&1 || (echo ERROR: cannot create staging folder & exit /b 1)

echo.
echo ============================================================
echo Building solution: %SLN%
echo Build ID:          %BUILD_ID%
echo Output ZIP:        %OUT_ZIP%
echo ============================================================
echo.

REM ---- Restore, build, test ----
dotnet --info
if errorlevel 1 (
  echo ERROR: dotnet not found on PATH.
  exit /b 1
)

echo.
echo [1/4] dotnet restore
dotnet restore "%SLN%"
if errorlevel 1 exit /b 1

echo.
echo [2/4] dotnet build (Release)
dotnet build "%SLN%" -c Release --no-restore
if errorlevel 1 exit /b 1

echo.
echo [3/4] dotnet test (Release)
dotnet test "%SLN%" -c Release --no-build
if errorlevel 1 exit /b 1

REM ---- Publish known projects if they exist ----
echo.
echo [4/4] dotnet publish (best-effort for known projects)

call :PublishIfExists "src\QuantDesk.DataHub.Service\QuantDesk.DataHub.Service.csproj" "Service"
if errorlevel 1 exit /b 1

call :PublishIfExists "src\QuantDesk.DataHub.FrameApi\QuantDesk.DataHub.FrameApi.csproj" "FrameApi"
if errorlevel 1 exit /b 1

call :PublishIfExists "src\QuantDesk.DataHub.ControlPanel\QuantDesk.DataHub.ControlPanel.csproj" "ControlPanel"
if errorlevel 1 exit /b 1

REM ---- Stage repo files needed for release ----
echo.
echo Staging release content...

REM Copy docs if present
if exist "docs" (
  xcopy /e /i /y "docs" "%STAGE%\docs" >nul
)

REM Copy installer sources if present
if exist "src\QuantDesk.DataHub.Installer" (
  xcopy /e /i /y "src\QuantDesk.DataHub.Installer" "%STAGE%\src\QuantDesk.DataHub.Installer" >nul
)

REM Copy uninstaller sources if present
if exist "src\QuantDesk.DataHub.Uninstaller" (
  xcopy /e /i /y "src\QuantDesk.DataHub.Uninstaller" "%STAGE%\src\QuantDesk.DataHub.Uninstaller" >nul
)

REM Copy build manifest/runbook if present at root (optional)
for %%F in (QD-DH-SPEC-BOOKMAP-PARITY_v1.2.0.md README.md) do (
  if exist "%%F" copy /y "%%F" "%STAGE%\%%F" >nul
)

REM Include published outputs
if exist "%PUBLISH%" (
  xcopy /e /i /y "%PUBLISH%" "%STAGE%\app" >nul
)

REM Include build.cmd itself
copy /y "build.cmd" "%STAGE%\build.cmd" >nul

REM ---- Create ZIP using PowerShell (built-in on Windows) ----
echo.
echo Creating ZIP: %OUT_ZIP%

if exist "%OUT_ZIP%" del /f /q "%OUT_ZIP%" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Compress-Archive -Path '%STAGE%\*' -DestinationPath '%OUT_ZIP%' -Force"
if errorlevel 1 (
  echo ERROR: Failed to create ZIP via Compress-Archive.
  exit /b 1
)

echo.
echo SUCCESS: Created %OUT_ZIP%
echo.
exit /b 0

REM ============================================================
REM Functions
REM ============================================================
:PublishIfExists
set "PROJ=%~1"
set "NAME=%~2"
if exist "%PROJ%" (
  echo Publishing %NAME%...
  dotnet publish "%PROJ%" -c Release -o "%PUBLISH%\%NAME%" --no-build
  if errorlevel 1 (
    echo ERROR: publish failed for %NAME%
    exit /b 1
  )
) else (
  echo Skipping %NAME% (project not found: %PROJ%)
)
exit /b 0
