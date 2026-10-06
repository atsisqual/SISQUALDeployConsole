@echo off
setlocal
set "ROOT=%~dp0"
set "PWSH=%ROOT%runtime\pwsh\pwsh.exe"
set "ENTRY=%ROOT%runtime\Start-SisqualDeployConsole.ps1"

if not exist "%PWSH%" (
  echo SISQUALDeployConsole: portable PowerShell runtime not found: "%PWSH%" 1>&2
  exit /b 10
)

if not exist "%ENTRY%" (
  echo SISQUALDeployConsole: runtime entry point not found: "%ENTRY%" 1>&2
  exit /b 12
)

"%PWSH%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%ENTRY%" %*
exit /b %ERRORLEVEL%
