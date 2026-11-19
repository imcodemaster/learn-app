#!/usr/bin/env bash
# One-time local setup (macOS / Linux). Run from the backend folder: ./setup_dev.sh
set -euo pipefail
cd "$(dirname "$0")"

python3 -m venv .venv
# shellcheck disable=SC1091
. .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

if [ ! -f .env ]; then
  cp .env.example .env
  secret=$(python -c "import secrets; print(secrets.token_urlsafe(50))")
  sed -i.bak "s|^DJANGO_SECRET_KEY=.*|DJANGO_SECRET_KEY=${secret}|" .env && rm -f .env.bak
  echo "Created .env (edit it to add Razorpay, SMS and Google keys)."
fi

python manage.py makemigrations accounts core courses payments studycenter
python manage.py migrate
python manage.py seed_demo

echo
echo "Create your admin login (use your email address):"
python manage.py createsuperuser

echo
echo "All set. Start the server with:"
echo "  . .venv/bin/activate && python manage.py runserver 0.0.0.0:8000"
echo "Admin panel: http://127.0.0.1:8000/admin/"
