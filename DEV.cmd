@echo off
setlocal
set "MODE=%~1"
if not defined MODE set "MODE=check"
python "%~dp0tools\dev.py" "%MODE%"
set "RC=%ERRORLEVEL%"
if "%~1"=="" pause
exit /b %RC%
