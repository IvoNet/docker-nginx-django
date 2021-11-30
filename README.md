# NginX Django

A very simple default NginX image for a django application.

## Usage

works in combination with the following images:

- postgres
- django application image

## `settings.py`

You need to make changes to your django settings.py file to make this work:

add this to your imports:

```python
from os import getenv
```

Change the SECRET_KEY to something like the following. This gives you te 
option to change it for production by providing an environment var called 
`SECRET_KEY`.

```python
# SECURITY WARNING: keep the secret key used in production secret!
SECRET_KEY = getenv("SECRET_KEY", 'django-insecure=!!ChangeMe!!nh^fi9!#e2%v!=qb$qcbv&y__$ps#byi8+m0x4f+avdb5c@d')
```

I've introduced an IS_DEV_MODE and IS_PROD_MODE variable and based on that 
some conclusions will be made later in the `settings.py` file.

```python

# SECURITY WARNING: don't run with debug turned on in production!
IS_DEV_MODE = getenv("APP_MODE", "development") == "development"
IS_PROD_MODE = not IS_DEV_MODE

DEBUG = IS_DEV_MODE

# Space separated hosts
ALLOWED_HOSTS = getenv("APP_ALLOWED_HOSTS", 'dev.ivo2u.org').split(" ")
if not ALLOWED_HOSTS:
    ALLOWED_HOSTS = []

# Always add Localhost
ALLOWED_HOSTS.append("localhost")

# Add this IP always when in dev mode
if IS_DEV_MODE:
    ALLOWED_HOSTS.append("127.0.0.1")

# Make sure the list contains unique hosts
ALLOWED_HOSTS = list(set(ALLOWED_HOSTS))

```

* I changed the database settings to use sqlite in development mode and 
  postgresql in production mode

```python
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR / 'volumes/database/sqlite/db.sqlite3',
    }
}

if IS_PROD_MODE:
    DATABASES = {
        "default": {
            "ENGINE": getenv("SQL_ENGINE", "django.db.backends.postgresql"),
            "NAME": getenv("SQL_DATABASE", getenv("APPLICATION_NAME", "APP_DB")),
            "USER": getenv("SQL_USER", "user"),
            "PASSWORD": getenv("SQL_PASSWORD", "password"),
            "HOST": getenv("SQL_HOST", "db"),
            "PORT": getenv("SQL_PORT", "5432"),
        }
    }
```

* To set the correct settings in the database we need to create two settings 
  files. One to set the correct settings for the `settings.py` file and one 
  for the postgres docker image
* `.env`

```properties
APP_MODE=production
APP_ALLOWED_HOSTS="YOUR_HOST_HERE ::1"
SECRET_KEY=ChangeMe
DATABASE=postgres
SQL_ENGINE=django.db.backends.postgresql
SQL_DATABASE=ivonet_site
SQL_USER=ivonet_site
SQL_PASSWORD=s3cr3t
SQL_HOST=db
SQL_PORT=5432
```

* `.db.env`

```properties
POSTGRES_USER=ivonet_site
POSTGRES_PASSWORD=s3cr3t
POSTGRES_DB=ivonet_site
```

(Might even optimize this one to use only one file)


* Now we also need to configure the STATIC and MEDIA folders for prod

```python
STATIC_ROOT = BASE_DIR / "volumes" / "staticfiles"
STATIC_URL = '/static/'

MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "volumes" / "mediafiles"
```

* you can change the URL names and the names at the end of the root.
* In my setup I count on the "volumes" to be there though as that makes the 
  setup more understandable

# Docker

In order to get the docker configuration working as a whole unit we need to 
have three containers:

- Django application
- NginX proxy (this image)
- postgres

## Django container

```Dockerfile
###########
# BUILDER #
###########

# pull official base image
FROM python:3.9.9-alpine as builder

# set work directory
WORKDIR /usr/src/app

# set environment variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# install psycopg2 / Pillow dependencies
RUN apk update \
    && apk add postgresql-dev gcc python3-dev musl-dev zlib-dev jpeg-dev

# lint
RUN pip install --upgrade pip
RUN pip install flake8
COPY . .
RUN flake8 --ignore=E501,F401 .

# install dependencies
COPY ./requirements.txt .
# RUN pip wheel --no-cache-dir --wheel-dir /usr/src/app/wheels -r requirements.txt


#########
# FINAL #
#########

# pull official base image
FROM python:3.9.9-alpine

ARG SECRET_KEY
ARG APP_MODE="production"
# space separated list of allowed hosts
ARG ALLOWED_HOSTS="dev.ivo2u.org"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_MODE=$APP_MODE \
    APP_ALLOWED_HOSTS=$ALLOWED_HOSTS \
    SECRET_KEY=$SECRET_KEY

WORKDIR /app

# create directory for the app user
ENV HOME=/app
WORKDIR $HOME

# create the app user
RUN addgroup -S app && adduser -S app -G app

# create the appropriate directories
RUN mkdir -p $HOME/volumes/staticfiles \
 && mkdir -p $HOME/volumes/mediafiles

#COPY --from=builder /usr/src/app/wheels /wheels
#COPY --from=builder /usr/src/app/requirements.txt .
RUN apk update \
 && apk add libpq \
 && pip install --upgrade pip

# copy project
COPY . .

#RUN apk add --virtual build-deps postgresql-dev gcc python3-dev musl-dev zlib-dev jpeg-dev \
#TODO find out which deps can be uninstalled through a --virtual build-deps setting
RUN apk add postgresql-dev gcc python3-dev musl-dev zlib-dev jpeg-dev \
 && pip install --no-cache -r requirements.txt
# && apk del build-deps

RUN chmod +x  $HOME/entrypoint.sh \
 && chown -R app:app $HOME

# change to the app user
USER app

# run entrypoint.sh
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/usr/local/bin/gunicorn", "ivonet_site.wsgi:application", "--bind", "0.0.0.0:8000", "--log-file=-", "--workers", "3"]
```

- The entrypoint mentioned here looks like this:

```shell
#!/bin/sh


if [ "$DATABASE" = "postgres" ]
then
    echo "Waiting for postgres..."

    while ! nc -z "${SQL_HOST:-db}" "${SQL_PORT:-5432}"; do
      sleep 0.1
    done

    echo "PostgreSQL started"
else # sqlite
  mkdir -p /app/volumes/database 2>/dev/null
  mkdir -p /app/volumes/mediafiles 2>/dev/null
  touch /app/volumes/database/db.sqlite3 2>/dev/null
fi

echo "Make migrations"
python3 manage.py makemigrations --noinput
echo "Migrate database"
python3 manage.py migrate --noinput
echo "Collect static files"
python manage.py collectstatic --noinput

exec "$@"
```

## NginX proxy

in this project:

```shell
docker build -t ivonet/nginx-django .
```

## Postgres container

you need that one too.

# Creating a superuser

After creating and running the docker setup run the following command

```shell
docker compose exec -it web python manage.py createsuperuser
```


# complete `docker-compose.yml`

```yaml
version: '3.8'

services:
  db:
    image: postgres:13.0-alpine
    volumes:
      - ./volumes/database/postgres:/var/lib/postgresql/data/
    env_file:
      - ./.db.env
  nginx:
    build: ./nginx
    volumes:
      - static_volume:/app/volumes/staticfiles
      - ./volumes/mediafiles:/app/volumes/mediafiles
    ports:
      - "1337:80"
    depends_on:
      - web
  web:
    image: ivonet/ivonet-site
    build:
      context: .
      dockerfile: Dockerfile
    volumes:
      - static_volume:/app/volumes/staticfiles
      - ./volumes/mediafiles:/app/volumes/mediafiles
    env_file:
      - ./.env
    depends_on:
      - db


volumes:
  static_volume:
```

# Complete docker-compose.yml with docker volumes

```yaml
version: '3.8'

services:
  db:
    image: postgres:13.0-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data/
    env_file:
      - ./.db.env
  nginx:
    build: ./nginx
    volumes:
      - static_volume:/app/volumes/staticfiles
      - media_volume:/app/volumes/mediafiles
    ports:
      - "1337:80"
    depends_on:
      - web
  web:
    image: ivonet/ivonet-site
    build:
      context: .
      dockerfile: Dockerfile
    volumes:
      - static_volume:/app/volumes/staticfiles
      - media_volume:/app/volumes/mediafiles
    env_file:
      - ./.env
    depends_on:
      - db


volumes:
  postgres_data:
  static_volume:
  media_volume:
```


# `.dockerignore`

in order to build cleanly you can add a docker ignore file to your web django 
project so that no unnecessary files are copied to the image during build

```text
.idea
*.iml
node_modules
.DS_Store
target
__pycache__
Dockerfile
README.md
.git
.*env
.dockerignore
volumes
```
