'use strict';

const { initializeApp, getApps, cert } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');

let app = null;

/**
 * Ленивая инициализация единственного firebase-admin приложения на инстанс
 * функции (переиспользуется между тёплыми вызовами).
 *
 * Два режима:
 *  - Локально с Firebase Emulator Suite (FIRESTORE_EMULATOR_HOST задан
 *    docker-compose.yml) — реальный ключ сервисного аккаунта не нужен.
 *  - В Yandex Cloud Functions — FIREBASE_SA_JSON обязателен (секрет из
 *    Lockbox, тот же сервисный аккаунт photos-backend-reader с ролью Cloud
 *    Datastore Viewer, что уже проверен зондом).
 */
function getFirebaseApp(cfg) {
  if (app) return app;
  if (getApps().length > 0) {
    app = getApps()[0];
    return app;
  }

  if (cfg.firestoreEmulatorHost) {
    app = initializeApp({ projectId: cfg.projectId });
    return app;
  }

  if (!cfg.firebaseServiceAccountJson) {
    throw new Error(
      'FIREBASE_SA_JSON не задан. Нужен JSON-ключ сервисного аккаунта ' +
        'photos-backend-reader (секрет Lockbox photos-backend-secrets).',
    );
  }

  let serviceAccount;
  try {
    serviceAccount = JSON.parse(cfg.firebaseServiceAccountJson);
  } catch (_err) {
    throw new Error('FIREBASE_SA_JSON содержит некорректный JSON.');
  }

  app = initializeApp({ credential: cert(serviceAccount), projectId: cfg.projectId });
  return app;
}

function getFirestoreDb(cfg) {
  return getFirestore(getFirebaseApp(cfg));
}

function getAuthClient(cfg) {
  return getAuth(getFirebaseApp(cfg));
}

module.exports = { getFirebaseApp, getFirestoreDb, getAuthClient };
