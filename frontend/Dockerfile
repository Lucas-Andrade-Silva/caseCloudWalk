# syntax=docker/dockerfile:1
# Imagem de desenvolvimento e teste do frontend. O código entra por bind mount (ver compose.yaml).
FROM node:24.15.0-slim

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint
RUN chmod +x /usr/local/bin/docker-entrypoint

ENTRYPOINT ["docker-entrypoint"]
EXPOSE 5173
CMD ["npm", "run", "dev"]
