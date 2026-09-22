'use strict';

// Конфигурация читается ТОЛЬКО из переменных окружения. Несекретные значения
// (S3_BUCKET, S3_ENDPOINT, S3_REGION, FIREBASE_PROJECT_ID) задаются в консоли
// функции как обычные переменные; секреты (S3_ACCESS_KEY, S3_SECRET_KEY,
// FIREBASE_SA_JSON) подключаются из Yandex Lockbox (секрет photos-backend-secrets)
// — те же самые, что уже использовались зондом (backend/probe/).

function readConfig() {
  const env = (name, fallback = '') => (process.env[name] ?? fallback).trim();

  return {
    projectId: env('FIREBASE_PROJECT_ID', 'remont-76b60'),
    bucket: env('S3_BUCKET', 'app-remont-photos'),
    endpoint: env('S3_ENDPOINT', 'storage.yandexcloud.net').replace(/^https?:\/\//i, '').replace(/\/+$/, ''),
    region: env('S3_REGION', 'ru-central1'),

    s3AccessKey: env('S3_ACCESS_KEY'),
    s3SecretKey: env('S3_SECRET_KEY'),
    firebaseServiceAccountJson: env('FIREBASE_SA_JSON'),
    firestoreEmulatorHost: env('FIRESTORE_EMULATOR_HOST'),

    putUrlTtlSeconds: 10 * 60, // D8: 10 минут на загрузку
    getUrlTtlSeconds: 60 * 60, // D8: 60 минут на чтение
    permissionCacheTtlMs: 30 * 1000, // D8: кэш прав ≤30 секунд

    maxGetUrlsBatch: 50,
    allowedContentTypes: new Set(['image/jpeg', 'image/png', 'image/webp']),
    maxUploadBytes: 10 * 1024 * 1024, // как в storage.rules: 10 МБ
  };
}

module.exports = { readConfig };
