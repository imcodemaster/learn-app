@echo off
title LearnInCreation - prepare production
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\prepare_production.ps1"
echo.
pause
