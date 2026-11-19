@echo off
title LearnInCreation setup
cd /d "%~dp0"
echo LearnInCreation: installs Flutter and the backend packages, runs the tests,
echo builds the Android app and starts the backend.
echo The first run can take 30-60 minutes. Progress is also saved to setup-log.txt.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\setup_and_build.ps1" %*
echo.
if errorlevel 1 goto failed
echo All done. The APK is in this folder and the backend runs in its own window.
pause
exit /b 0

:failed
echo Setup stopped with an error. The reason is just above and in setup-log.txt.
pause
exit /b 1
