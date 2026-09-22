#!/usr/bin/env node
'use strict';

/**
 * Разовый скрипт: заполняет storagePath в старых документах, у которых его
 * нет, но есть legacy-ссылка (presigned URL, выпущенная старым клиентом
 * напрямую S3-ключом до миграции на backend photos-api).
 *
 * Зачем: с этого момента приложение показывает фото ТОЛЬКО по storagePath
 * (см. lib/widgets/storage_image.dart) — запрашивает свежую ссылку у backend
 * при каждом показе. У документов без storagePath (созданных до этой
 * миграции) фото показать нечем, пока не заполнить это поле.
 *
 * Как это делает скрипт: сам файл в S3 не трогает и не проверяет его
 * существование — только парсит уже сохранённую в документе legacy-ссылку
 * (`downloadUrl`/`imageUrl`/`receiptUrl`) и вытаскивает из неё ключ объекта
 * (всё, что в пути ссылки идёт после `/{bucket}/`, без query-строки с
 * подписью). Тот же алгоритм, что раньше был в
 * StorageService._keyFromUrl (удалён при миграции на backend).
 *
 * Проверяются три места, где фото/чек могли быть загружены СТАРЫМ клиентом:
 *   - projects/{p}/stages/{s}/photos/{id}  (Photo, поле downloadUrl)
 *   - projects/{p}/expenses/{id}           (Expense, поле receiptUrl —
 *     с фолбэками на downloadUrl/receiptPhotoUrl, как в Expense.fromMap)
 *   - projects/{p}/messages/{id}, type=='image' (ChatMessage, поле imageUrl)
 *
 * ПО УМОЛЧАНИЮ РЕЖИМ DRY-RUN — только печатает, что нашёл и что сделал бы.
 * Ничего не пишет в Firestore, пока явно не передан флаг --apply.
 *
 * Запуск (нужен ключ сервисного аккаунта С ПРАВОМ ЗАПИСИ в Firestore —
 * НЕ photos-backend-reader, у него только Cloud Datastore Viewer):
 *
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *     node backend/scripts/backfill-storage-paths.mjs [--project=remont-76b60] [--bucket=app-remont-photos]
 *
 *   # Когда убедились по выводу dry-run, что всё верно:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *     node backend/scripts/backfill-storage-paths.mjs --apply
 */

import { initializeApp, applicationDefault, cert } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const args = process.argv.slice(2);
const APPLY = args.includes('--apply');
const arg = (name, fallback) => {
  const prefix = `--${name}=`;
  const found = args.find((a) => a.startsWith(prefix));
  return found ? found.slice(prefix.length) : fallback;
};

const PROJECT_ID = arg('project', process.env.FIREBASE_PROJECT_ID || 'remont-76b60');
const BUCKET = arg('bucket', process.env.S3_BUCKET || 'app-remont-photos');
const BATCH_SIZE = 400; // запас до лимита Firestore batch write (500)

function initFirebase() {
  const credentials = process.env.FIREBASE_SA_JSON
    ? cert(JSON.parse(process.env.FIREBASE_SA_JSON))
    : applicationDefault();
  initializeApp({ credential: credentials, projectId: PROJECT_ID });
  return getFirestore();
}

/** Тот же алгоритм, что был в StorageService._keyFromUrl до миграции. */
function keyFromLegacyUrl(url) {
  if (typeof url !== 'string' || url.length === 0) return null;
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }
  const prefix = `/${BUCKET}/`;
  if (!parsed.pathname.startsWith(prefix)) return null;
  const key = decodeURIComponent(parsed.pathname.slice(prefix.length));
  return key.length > 0 ? key : null;
}

function firstNonEmptyString(doc, fields) {
  for (const field of fields) {
    const value = doc[field];
    if (typeof value === 'string' && value.trim().length > 0) return value;
  }
  return null;
}

class Report {
  constructor(label) {
    this.label = label;
    this.scanned = 0;
    this.alreadyOk = 0;
    this.fixed = 0;
    this.noLegacyUrl = 0;
    this.unparseable = 0;
  }
  print() {
    console.log(
      `\n${this.label}: scanned=${this.scanned} alreadyOk=${this.alreadyOk} ` +
        `${APPLY ? 'fixed' : 'wouldFix'}=${this.fixed} noLegacyUrl=${this.noLegacyUrl} ` +
        `unparseable=${this.unparseable}`,
    );
  }
}

async function commitInBatches(db, writes) {
  for (let i = 0; i < writes.length; i += BATCH_SIZE) {
    const chunk = writes.slice(i, i + BATCH_SIZE);
    if (!APPLY) continue;
    const batch = db.batch();
    for (const { ref, data } of chunk) batch.update(ref, data);
    await batch.commit();
  }
}

async function backfillStagePhotos(db) {
  const report = new Report('stages/*/photos (Photo.storagePath)');
  const writes = [];

  const snapshot = await db.collectionGroup('photos').get();
  for (const doc of snapshot.docs) {
    // Коллекция 'photos' также используется легаси-документами
    // projects/{p}/photos/{id} (не production-модель Photo) — у них нет
    // stageId, пропускаем их этим шагом, они не относятся к текущей миграции.
    if (!doc.ref.path.includes('/stages/')) continue;

    report.scanned += 1;
    const data = doc.data();
    if (typeof data.storagePath === 'string' && data.storagePath.trim().length > 0) {
      report.alreadyOk += 1;
      continue;
    }

    const legacyUrl = firstNonEmptyString(data, ['downloadUrl']);
    if (!legacyUrl) {
      report.noLegacyUrl += 1;
      continue;
    }

    const key = keyFromLegacyUrl(legacyUrl);
    if (!key) {
      report.unparseable += 1;
      console.warn(`  [photos] не удалось разобрать ссылку: ${doc.ref.path}`);
      continue;
    }

    report.fixed += 1;
    console.log(`  [photos] ${doc.ref.path} -> storagePath="${key}"`);
    writes.push({ ref: doc.ref, data: { storagePath: key } });
  }

  await commitInBatches(db, writes);
  report.print();
}

async function backfillExpenses(db) {
  const report = new Report('expenses (Expense.receiptStoragePath)');
  const writes = [];

  const snapshot = await db.collectionGroup('expenses').get();
  for (const doc of snapshot.docs) {
    report.scanned += 1;
    const data = doc.data();
    const existing = firstNonEmptyString(data, ['receiptStoragePath', 'storagePath']);
    if (existing) {
      report.alreadyOk += 1;
      continue;
    }

    const legacyUrl = firstNonEmptyString(data, [
      'receiptUrl',
      'downloadUrl',
      'receiptPhotoUrl',
    ]);
    if (!legacyUrl) {
      report.noLegacyUrl += 1;
      continue;
    }

    const key = keyFromLegacyUrl(legacyUrl);
    if (!key) {
      report.unparseable += 1;
      console.warn(`  [expenses] не удалось разобрать ссылку: ${doc.ref.path}`);
      continue;
    }

    report.fixed += 1;
    console.log(`  [expenses] ${doc.ref.path} -> receiptStoragePath="${key}"`);
    writes.push({
      ref: doc.ref,
      data: { receiptStoragePath: key, storagePath: key },
    });
  }

  await commitInBatches(db, writes);
  report.print();
}

async function backfillChatMessages(db) {
  const report = new Report('messages type=image (ChatMessage.storagePath)');
  const writes = [];

  const snapshot = await db
    .collectionGroup('messages')
    .where('type', '==', 'image')
    .get();

  for (const doc of snapshot.docs) {
    report.scanned += 1;
    const data = doc.data();
    if (typeof data.storagePath === 'string' && data.storagePath.trim().length > 0) {
      report.alreadyOk += 1;
      continue;
    }

    const legacyUrl = firstNonEmptyString(data, ['imageUrl']);
    if (!legacyUrl) {
      report.noLegacyUrl += 1;
      continue;
    }

    const key = keyFromLegacyUrl(legacyUrl);
    if (!key) {
      report.unparseable += 1;
      console.warn(`  [messages] не удалось разобрать ссылку: ${doc.ref.path}`);
      continue;
    }

    report.fixed += 1;
    console.log(`  [messages] ${doc.ref.path} -> storagePath="${key}"`);
    writes.push({ ref: doc.ref, data: { storagePath: key } });
  }

  await commitInBatches(db, writes);
  report.print();
}

async function main() {
  console.log(`project=${PROJECT_ID} bucket=${BUCKET} mode=${APPLY ? 'APPLY (пишет в Firestore)' : 'DRY-RUN (ничего не пишет)'}`);
  if (!APPLY) {
    console.log('Передайте --apply, когда убедитесь, что вывод ниже выглядит правильно.\n');
  }

  const db = initFirebase();

  await backfillStagePhotos(db);
  await backfillExpenses(db);
  await backfillChatMessages(db);

  console.log(`\nГотово. ${APPLY ? 'Изменения записаны.' : 'Это был dry-run — ничего не изменено.'}`);
}

main().catch((error) => {
  console.error('Скрипт завершился с ошибкой:', error);
  process.exitCode = 1;
});
