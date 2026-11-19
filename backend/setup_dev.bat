@echo off
REM One-time local setup on Windows. Double-click or run from the backend folder.
cd /d "%~dp0"

py -3 -m venv .venv || python -m venv .venv
call .venv\Scripts\activate.bat
python -m pip install --upgrade pip
pip install -r requirements.txt || goto :error

if not exist .env (
  copy .env.example .env >nul
  for /f "delims=" %%s in ('python -c "import secrets; print(secrets.token_urlsafe(50))"') do set SECRET=%%s
  powershell -NoProfile -Command "(Get-Content .env) -replace '^DJANGO_SECRET_KEY=.*', 'DJANGO_SECRET_KEY=%SECRET%' | Set-Content .env"
  echo Created .env - edit it to add Razorpay, SMS and Google keys.
)

python manage.py makemigrations accounts core courses payments studycenter || goto :error
python manage.py migrate || goto :error
python manage.py seed_demo || goto :error

echo.
echo Create your admin login (use your email address):
python manage.py createsuperuser

echo.
echo All set. Start the server with:
echo   .venv\Scripts\activate ^&^& python manage.py runserver 0.0.0.0:8000
echo Admin panel: http://127.0.0.1:8000/admin/
pause
exit /b 0

:error
echo Setup failed. Read the message above.
pause
exit /b 1
