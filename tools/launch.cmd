@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
set "MODE=%~1"
set "ROOT=%~dp0.."
set "ENGINE=%~2"
if defined ENGINE goto validate
if defined GODOT_EXE set "ENGINE=%GODOT_EXE%"
if defined ENGINE goto validate
if exist "%ROOT%\godot_path.txt" set /p ENGINE=<"%ROOT%\godot_path.txt"
if defined ENGINE goto validate
for %%G in (godot.exe godot4.exe) do for /f "delims=" %%P in ('where %%G 2^>nul') do if not defined ENGINE set "ENGINE=%%P"
if defined ENGINE goto validate
:choose
echo Select the standard Godot 4.5.1 or newer executable. Nothing is downloaded.
set "ENGINE="
for /f "usebackq delims=" %%P in (`powershell.exe -STA -NoProfile -Command "[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false); Add-Type -AssemblyName System.Windows.Forms; $d=New-Object System.Windows.Forms.OpenFileDialog; $d.Title='Select Godot 4.5.1+ executable'; $d.Filter='Godot executable (*.exe)|*.exe'; if($d.ShowDialog() -eq 'OK'){[Console]::WriteLine($d.FileName)}"`) do set "ENGINE=%%P"
if not defined ENGINE goto missing
:validate
if not exist "%ENGINE%" goto choose
set "HOSHI_ROOT=%ROOT%"
set "HOSHI_ENGINE=%ENGINE%"
powershell.exe -NoProfile -Command "[IO.File]::WriteAllText([IO.Path]::Combine($env:HOSHI_ROOT,'godot_path.txt'),$env:HOSHI_ENGINE,(New-Object Text.UTF8Encoding($false)))" >nul 2>nul
if not exist "%ROOT%\logs" mkdir "%ROOT%\logs"
echo Checking and importing local project resources...
start "Hoshi - import" /wait "%ENGINE%" --headless --editor --path "%ROOT%" --import --log-file "%ROOT%\logs\import.log"
if errorlevel 1 goto import_failed
findstr /i /c:"SCRIPT ERROR:" /c:"Parse Error:" /c:"Failed to load script" "%ROOT%\logs\import.log" >nul 2>nul
if not errorlevel 1 goto import_failed
if "%MODE%"=="test" goto test
if "%MODE%"=="desktop" goto desktop
if "%MODE%"=="capture" goto capture
if "%MODE%"=="reset" goto reset
if "%MODE%"=="walk" goto walk
if "%MODE%"=="shelf" goto shelf
start "Hoshi Preview" "%ENGINE%" --path "%ROOT%" --log-file "%ROOT%\logs\session.log" -- --preview
exit /b 0
:desktop
start "Hoshi Companion" "%ENGINE%" --path "%ROOT%" --log-file "%ROOT%\logs\session.log" -- --desktop
exit /b 0
:capture
start "Hoshi Preview Capture" "%ENGINE%" --path "%ROOT%" --log-file "%ROOT%\logs\session.log" -- --preview --capture
exit /b 0
:walk
start "Hoshi Walk Preview" "%ENGINE%" --path "%ROOT%" --log-file "%ROOT%\logs\session.log" -- --preview --walk-demo
exit /b 0
:shelf
start "Hoshi Shelf" "%ENGINE%" --path "%ROOT%" --log-file "%ROOT%\logs\session.log" -- --preview --shelf-demo
exit /b 0
:reset
start "Hoshi Reset" "%ENGINE%" --path "%ROOT%" --log-file "%ROOT%\logs\session.log" -- --preview --reset
exit /b 0
:test
start "Hoshi runtime tests" /wait "%ENGINE%" --headless --path "%ROOT%" --script res://tests/test_runtime.gd --log-file "%ROOT%\logs\runtime_tests.log"
set "TEST_EXIT=%ERRORLEVEL%"
if exist "%ROOT%\logs\runtime_tests.log" type "%ROOT%\logs\runtime_tests.log"
findstr /i /c:"SCRIPT ERROR:" /c:"Parse Error:" /c:"Failed to load script" "%ROOT%\logs\runtime_tests.log" >nul 2>nul
if not errorlevel 1 set "TEST_EXIT=1"
findstr /c:"HOSHI_TEST_RESULT" "%ROOT%\logs\runtime_tests.log" >nul 2>nul
if errorlevel 1 set "TEST_EXIT=1"
echo.
echo Test exit code: %TEST_EXIT%
echo A successful run ends with HOSHI_TEST_RESULT and failures=0.
echo This does not test Windows transparency or GPU rendering.
pause
exit /b %TEST_EXIT%
:missing
echo No Godot executable was selected. Open project.godot in Godot 4.5.1+ instead.
pause
exit /b 1
:import_failed
echo.
echo Project import or script parsing failed. Please send logs\import.log.
if exist "%ROOT%\logs\import.log" type "%ROOT%\logs\import.log"
pause
exit /b 1
