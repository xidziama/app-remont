FROM node:20-bookworm

# Firestore emulator запускается на Java, поэтому в контейнере нужен JRE.
RUN apt-get update \
    && apt-get install -y --no-install-recommends openjdk-17-jre-headless \
    && rm -rf /var/lib/apt/lists/*

# Firebase CLI ставится в отдельный образ один раз при build.
# Это быстрее и стабильнее, чем скачивать CLI при каждом `docker compose up`.
RUN npm install -g firebase-tools@13.35.1

WORKDIR /workspace
