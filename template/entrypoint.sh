#!/bin/sh

if [ "$DATABASE" = "postgres" ]; then
  echo "Waiting for postgres..."

  while ! nc -z "${SQL_HOST:-db}" "${SQL_PORT:-5432}"; do
    sleep 0.1
  done

  echo "PostgreSQL started"
elif [ ! -f /app/volumes/database/db.sqlite3 ]; then
  echo "Initializing sqlite new site."
  mkdir -p /app/volumes/database 2>/dev/null
  mkdir -p /app/volumes/mediafiles 2>/dev/null
  touch /app/volumes/database/db.sqlite3 2>/dev/null
fi

echo "Make migrations"
python3 manage.py makemigrations
echo "Migrate database"
python3 manage.py migrate
echo "Collect static files"
python manage.py collectstatic --noinput

exec "$@"
