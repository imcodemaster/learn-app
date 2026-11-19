@echo off
title LearnInCreation - upload to GitHub
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\push_to_github.ps1" -RepoUrl "https://github.com/imcodemaster/learn-app.git" %*
echo.
pause
