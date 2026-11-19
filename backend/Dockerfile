FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

# Creates database migrations from the models if the project has none yet,
# and collects admin CSS/JS. No database is needed for either step.
RUN DJANGO_SECRET_KEY=build-step-only-not-a-real-secret-0123456789abcdef \
    APP_ENV=build DB_ENGINE=sqlite \
    sh -c "python manage.py makemigrations accounts core courses payments studycenter --noinput \
           && python manage.py collectstatic --noinput"

RUN useradd --create-home --uid 10001 app \
    && mkdir -p /app/media \
    && chown -R app:app /app/media \
    && chmod +x /app/deploy/docker-entrypoint.sh
USER app

EXPOSE 8000
ENTRYPOINT ["/app/deploy/docker-entrypoint.sh"]
CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "3", "--timeout", "60", "--access-logfile", "-"]
