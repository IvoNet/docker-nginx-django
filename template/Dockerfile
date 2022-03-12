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

RUN apk add musl-dev zlib-dev jpeg-dev
RUN apk add --virtual build-deps postgresql-dev gcc python3-dev  \
 && pip install --no-cache -r requirements.txt \
 && apk del build-deps

RUN chmod +x  $HOME/entrypoint.sh \
 && chown -R app:app $HOME

# change to the app user
USER app

# run entrypoint.sh
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/usr/local/bin/gunicorn", "ivonet_site.wsgi:application", "--bind", "0.0.0.0:8000", "--log-file=-", "--workers", "3"]
