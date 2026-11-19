@echo off
title LearnInCreation backend - keep this window open while using the app
cd /d "%~dp0backend"
if exist ".venv\Scripts\python.exe" goto run
echo The backend is not set up yet. Double-click SETUP-AND-BUILD-ON-WINDOWS.cmd first.
pause
exit /b 1

:run
echo LearnInCreation backend is starting on port 8000.
echo Admin panel on this PC: http://127.0.0.1:8000/admin/  (login in backend\ADMIN-LOGIN.txt)
echo Sign-in codes and password-reset emails are printed in this window while testing.
echo Close this window to stop the server.
echo.
".venv\Scripts\python.exe" manage.py runserver 0.0.0.0:8000
pause
