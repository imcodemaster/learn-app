#!/bin/sh
# Starts the backend container:
#  1. gives the uploads folder to the "app" user (hosting disks such as Render's
#     can be mounted owned by root), then continues as that unprivileged user;
#  2. updates the database tables;
#  3. creates the first admin user from ADMIN_EMAIL / ADMIN_PASSWORD (once);
#  4. adds the sample catalog when SEED_DEMO_CONTENT=1 and there are no courses;
#  5. runs the web server.
set -e

if [ "$(id -u)" = "0" ]; then
    media="${MEDIA_ROOT:-/app/media}"
    mkdir -p "$media"
    chown app:app "$media" || echo "Warning: could not give $media to the app user; image uploads may fail."
    exec setpriv --reuid="$(id -u app)" --regid="$(id -g app)" --init-groups "$0" "$@"
fi

python manage.py migrate --noinput
python manage.py ensure_admin
if [ "${SEED_DEMO_CONTENT:-0}" = "1" ]; then
    python manage.py seed_demo --if-empty
fi
exec "$@"
