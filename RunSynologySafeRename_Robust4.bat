@echo off
setlocal
cd /d "%~dp0"

echo Launching SynologySafeRename (Robust4)...
echo.

where pwsh >nul 2>nul
if %errorlevel%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0SynologySafeRename_Robust4.ps1"
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SynologySafeRename_Robust4.ps1"
)

echo.
echo Script finished. Press any key to close.
pause >nul
endlocal
