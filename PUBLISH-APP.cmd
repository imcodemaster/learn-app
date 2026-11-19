@echo off
title LearnInCreation - publish the app
cd /d "%~dp0"
echo LearnInCreation: builds the app for the live server and publishes it on GitHub.
echo It takes about 10 minutes. Details are also saved to publish-log.txt.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\publish_app.ps1" %*
echo.
if errorlevel 1 goto failed
echo All done.
pause
exit /b 0

:failed
echo Publishing stopped. The reason is just above and in publish-log.txt.
pause
exit /b 1
