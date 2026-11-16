# syntax=docker/dockerfile:1
# Imagem de desenvolvimento e teste. O código entra por bind mount (ver compose.yaml).
FROM ruby:3.4.12-slim

RUN apt-get update -qq \
 && apt-get install --no-install-recommends -y \
      build-essential curl git libpq-dev libyaml-dev pkg-config postgresql-client \
 && rm -rf /var/lib/apt/lists/*

ENV BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY docker/entrypoint.sh /usr/local/bin/docker-entrypoint
RUN chmod +x /usr/local/bin/docker-entrypoint

ENTRYPOINT ["docker-entrypoint"]
EXPOSE 3000
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
