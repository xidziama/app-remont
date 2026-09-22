/**
 * Тест-матрица прав backend photos-api — Admin SDK против Firestore Emulator.
 *
 * Роли и фикстуры намеренно совпадают с rules-tests/rules.test.mjs (owner1/
 * mgr1/mgr2/worker1/worker2/client1/outsider1, компания c1, объект p1,
 * этап s1, чужой объект p_other), чтобы обе тест-матрицы (правила и backend)
 * проверяли одну и ту же модель доступа и не расходились со временем.
 *
 * Требует Firebase Emulator (Firestore): FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
 * (или переопределить переменной окружения). Запуск:
 *   firebase emulators:exec --only firestore,auth "npm test"
 */

import assert from 'node:assert';
import http from 'node:http';

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.FIREBASE_PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'remont-76b60';

const { readConfig } = await import('../src/env.js');
const { getFirestoreDb } = await import('../src/firebase.js');
const {
  canReadProject,
  canManageProject,
  isProjectWorker,
  isAssignedStageWorker,
} = await import('../src/permissions.js');
const { parseStoragePath } = await import('../src/storagePaths.js');
const { checkWritePermission, resolveMetaKind } = await import('../src/endpoints/putUrl.js');
const { checkDeletePermission } = await import('../src/endpoints/deleteObject.js');
const { HttpError } = await import('../src/httpErrors.js');

const cfg = readConfig();

const COMPANY_ID = 'c1';
const PROJ_ID = 'p1';
const PROJ_OTHER = 'p_other';
const STAGE_ID = 's1';
const EXP_UNPAID_ID = 'exp_unpaid';
const EXP_PAID_ID = 'exp_paid';

const OWNER_UID = 'owner1';
const MGR_UID = 'mgr1';
const MGR2_UID = 'mgr2'; // менеджер компании, но не в managerIds объекта
const WORKER_UID = 'worker1';
const WORKER2_UID = 'worker2'; // назначен на этап, но не автор ни одного чека
const CLIENT_UID = 'client1';
const OUT_UID = 'outsider1';

function clearFirestoreEmulator() {
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  const path = `/emulator/v1/projects/${cfg.projectId}/databases/(default)/documents`;

  return new Promise((resolve, reject) => {
    const req = http.request({ host, port, method: 'DELETE', path }, (res) => {
      res.on('data', () => {});
      res.on('end', resolve);
    });
    req.on('error', reject);
    req.end();
  });
}

async function seed() {
  const db = getFirestoreDb(cfg);
  const iso = () => new Date().toISOString();

  const memberBase = (uid, role) => ({
    uid,
    companyId: COMPANY_ID,
    role,
    active: true,
    canCreateProjects: false,
    createdAt: iso(),
  });

  await db.doc(`companies/${COMPANY_ID}`).set({ ownerId: OWNER_UID, name: 'Рога и Копыта', status: 'active' });
  await db.doc(`companies/${COMPANY_ID}/members/${OWNER_UID}`).set(memberBase(OWNER_UID, 'owner'));
  await db.doc(`companies/${COMPANY_ID}/members/${MGR_UID}`).set(memberBase(MGR_UID, 'manager'));
  await db.doc(`companies/${COMPANY_ID}/members/${MGR2_UID}`).set(memberBase(MGR2_UID, 'manager'));

  await db.doc(`projects/${PROJ_ID}`).set({
    ownerId: OWNER_UID,
    companyId: COMPANY_ID,
    title: 'Объект №1',
    status: 'inProgress',
    participantIds: [OWNER_UID, MGR_UID, WORKER_UID, WORKER2_UID, CLIENT_UID],
    managerIds: [MGR_UID],
    workerIds: [WORKER_UID, WORKER2_UID],
    clientIds: [CLIENT_UID],
  });

  await db.doc(`projects/${PROJ_OTHER}`).set({
    ownerId: 'other_owner',
    companyId: 'company_other',
    title: 'Чужой объект',
    status: 'inProgress',
    participantIds: ['other_owner'],
    managerIds: [],
    workerIds: [],
    clientIds: [],
  });

  await db.doc(`projects/${PROJ_ID}/stages/${STAGE_ID}`).set({
    projectId: PROJ_ID,
    title: 'Этап 1',
    status: 'not_started',
    assignedUserIds: [WORKER_UID, WORKER2_UID],
  });

  await db.doc(`projects/${PROJ_ID}/expenses/${EXP_UNPAID_ID}`).set({
    id: EXP_UNPAID_ID,
    projectId: PROJ_ID,
    stageId: STAGE_ID,
    amount: 1000,
    category: 'materials',
    createdBy: WORKER_UID,
    isPaid: false,
  });

  await db.doc(`projects/${PROJ_ID}/expenses/${EXP_PAID_ID}`).set({
    id: EXP_PAID_ID,
    projectId: PROJ_ID,
    stageId: STAGE_ID,
    amount: 500,
    category: 'tools',
    createdBy: WORKER_UID,
    isPaid: true,
    paidAt: iso(),
    paidBy: OWNER_UID,
  });
}

async function deniedWith(promise, expectedStatus) {
  try {
    await promise;
  } catch (err) {
    assert.ok(err instanceof HttpError, `ожидалась HttpError, получено: ${err}`);
    assert.strictEqual(err.statusCode, expectedStatus);
    return;
  }
  assert.fail('ожидался отказ (HttpError), но проверка прошла');
}

describe('photos-api permissions — matrix', () => {
  before(async () => {
    await clearFirestoreEmulator();
    await seed();
  });

  // -------------------------------------------------------------------------
  // storagePaths — базовая валидация формата
  // -------------------------------------------------------------------------
  describe('parseStoragePath', () => {
    it('разбирает путь фото этапа', () => {
      const parsed = parseStoragePath(`projects/${PROJ_ID}/stages/${STAGE_ID}/photos/ph1.jpg`);
      assert.deepStrictEqual(parsed, {
        pathKind: 'stagePhoto',
        projectId: PROJ_ID,
        stageId: STAGE_ID,
        id: 'ph1',
      });
    });

    it('разбирает путь чека без этапа', () => {
      const parsed = parseStoragePath(`projects/${PROJ_ID}/receipts/${EXP_UNPAID_ID}.jpg`);
      assert.deepStrictEqual(parsed, { pathKind: 'objectReceipt', projectId: PROJ_ID, id: EXP_UNPAID_ID });
    });

    it('разбирает путь фото чата', () => {
      const parsed = parseStoragePath(`projects/${PROJ_ID}/chat/msg1.png`);
      assert.deepStrictEqual(parsed, { pathKind: 'chat', projectId: PROJ_ID, id: 'msg1' });
    });

    it('отклоняет traversal и посторонние сегменты', () => {
      assert.strictEqual(parseStoragePath(`projects/${PROJ_ID}/stages/../secrets/x.jpg`), null);
      assert.strictEqual(parseStoragePath(`projects/${PROJ_ID}/stages/${STAGE_ID}/photos/x.exe`), null);
      assert.strictEqual(parseStoragePath('not/a/known/format.jpg'), null);
    });
  });

  // -------------------------------------------------------------------------
  // canReadProject — базовая матрица (чтение)
  // -------------------------------------------------------------------------
  describe('canReadProject', () => {
    it('owner читает свой объект', async () => {
      assert.strictEqual(await canReadProject(cfg, PROJ_ID, OWNER_UID), true);
    });

    it('worker и worker2 (в participantIds/workerIds) читают объект', async () => {
      assert.strictEqual(await canReadProject(cfg, PROJ_ID, WORKER_UID), true);
      assert.strictEqual(await canReadProject(cfg, PROJ_ID, WORKER2_UID), true);
    });

    it('client (в clientIds) читает объект', async () => {
      assert.strictEqual(await canReadProject(cfg, PROJ_ID, CLIENT_UID), true);
    });

    it('manager2 (менеджер компании, но не в managerIds объекта) НЕ читает объект', async () => {
      assert.strictEqual(await canReadProject(cfg, PROJ_ID, MGR2_UID), false);
    });

    it('outsider не читает чужой объект', async () => {
      assert.strictEqual(await canReadProject(cfg, PROJ_ID, OUT_UID), false);
      assert.strictEqual(await canReadProject(cfg, PROJ_OTHER, OWNER_UID), false);
    });

    it('несуществующий проект — false, а не исключение', async () => {
      assert.strictEqual(await canReadProject(cfg, 'no-such-project', OWNER_UID), false);
    });
  });

  // -------------------------------------------------------------------------
  // canManageProject / isProjectWorker / isAssignedStageWorker
  // -------------------------------------------------------------------------
  describe('canManageProject / worker-предикаты', () => {
    it('owner и manager (в managerIds) управляют объектом', async () => {
      assert.strictEqual(await canManageProject(cfg, PROJ_ID, OWNER_UID), true);
      assert.strictEqual(await canManageProject(cfg, PROJ_ID, MGR_UID), true);
    });

    it('manager2 НЕ управляет чужим для него объектом', async () => {
      assert.strictEqual(await canManageProject(cfg, PROJ_ID, MGR2_UID), false);
    });

    it('worker не управляет объектом', async () => {
      assert.strictEqual(await canManageProject(cfg, PROJ_ID, WORKER_UID), false);
    });

    it('isAssignedStageWorker верно для worker/worker2, неверно для client', async () => {
      assert.strictEqual(await isAssignedStageWorker(cfg, PROJ_ID, STAGE_ID, WORKER_UID), true);
      assert.strictEqual(await isAssignedStageWorker(cfg, PROJ_ID, STAGE_ID, WORKER2_UID), true);
      assert.strictEqual(await isAssignedStageWorker(cfg, PROJ_ID, STAGE_ID, CLIENT_UID), false);
    });

    it('isProjectWorker верно для worker/worker2, неверно для client/manager', async () => {
      assert.strictEqual(await isProjectWorker(cfg, PROJ_ID, WORKER_UID), true);
      assert.strictEqual(await isProjectWorker(cfg, PROJ_ID, CLIENT_UID), false);
      assert.strictEqual(await isProjectWorker(cfg, PROJ_ID, MGR_UID), false);
    });
  });

  // -------------------------------------------------------------------------
  // put-url — проверка прав на запись (без реального обращения к S3)
  // -------------------------------------------------------------------------
  describe('checkWritePermission (put-url)', () => {
    const stagePath = { pathKind: 'stagePhoto', projectId: PROJ_ID, stageId: STAGE_ID, id: 'new1' };
    const objectReceiptPath = { pathKind: 'objectReceipt', projectId: PROJ_ID, id: 'new2' };
    const chatPath = { pathKind: 'chat', projectId: PROJ_ID, id: 'new3' };
    const foreignStagePath = { pathKind: 'stagePhoto', projectId: PROJ_OTHER, stageId: 's_x', id: 'x' };

    it('owner/manager могут писать фото/чек в любой этап своего объекта', async () => {
      assert.strictEqual(await checkWritePermission(cfg, stagePath, OWNER_UID), true);
      assert.strictEqual(await checkWritePermission(cfg, stagePath, MGR_UID), true);
    });

    it('назначенный подрядчик может писать в СВОЙ этап', async () => {
      assert.strictEqual(await checkWritePermission(cfg, stagePath, WORKER_UID), true);
      assert.strictEqual(await checkWritePermission(cfg, stagePath, WORKER2_UID), true);
    });

    it('outsider не может писать в чужой объект', async () => {
      assert.strictEqual(await checkWritePermission(cfg, stagePath, OUT_UID), false);
      assert.strictEqual(await checkWritePermission(cfg, foreignStagePath, OWNER_UID), false);
    });

    it('client не может загружать фото/чек этапа', async () => {
      assert.strictEqual(await checkWritePermission(cfg, stagePath, CLIENT_UID), false);
    });

    it('чек без этапа (objectReceipt) — только canManageProject, worker не может', async () => {
      assert.strictEqual(await checkWritePermission(cfg, objectReceiptPath, OWNER_UID), true);
      assert.strictEqual(await checkWritePermission(cfg, objectReceiptPath, MGR_UID), true);
      assert.strictEqual(await checkWritePermission(cfg, objectReceiptPath, WORKER_UID), false);
    });

    it('чат — доступен любому участнику объекта, но не постороннему', async () => {
      assert.strictEqual(await checkWritePermission(cfg, chatPath, CLIENT_UID), true);
      assert.strictEqual(await checkWritePermission(cfg, chatPath, WORKER_UID), true);
      assert.strictEqual(await checkWritePermission(cfg, chatPath, OUT_UID), false);
    });

    it('resolveMetaKind: receipts всегда receipt, chat всегда photo, stagePhoto — по подсказке клиента', () => {
      assert.strictEqual(resolveMetaKind(objectReceiptPath, undefined), 'receipt');
      assert.strictEqual(resolveMetaKind(chatPath, 'receipt'), 'photo');
      assert.strictEqual(resolveMetaKind(stagePath, 'receipt'), 'receipt');
      assert.strictEqual(resolveMetaKind(stagePath, undefined), 'photo');
    });
  });

  // -------------------------------------------------------------------------
  // delete — ключевая матрица: заморозка оплаченного чека для ВСЕХ
  // -------------------------------------------------------------------------
  describe('checkDeletePermission (delete)', () => {
    const unpaidReceiptPath = { pathKind: 'stagePhoto', projectId: PROJ_ID, stageId: STAGE_ID, id: EXP_UNPAID_ID };
    const paidReceiptPath = { pathKind: 'stagePhoto', projectId: PROJ_ID, stageId: STAGE_ID, id: EXP_PAID_ID };
    const progressPhotoPath = { pathKind: 'stagePhoto', projectId: PROJ_ID, stageId: STAGE_ID, id: 'ph_progress' };
    const chatPath = { pathKind: 'chat', projectId: PROJ_ID, id: 'msg1' };

    it('автор удаляет свой НЕОПЛАЧЕННЫЙ чек → allow', async () => {
      await checkDeletePermission(cfg, unpaidReceiptPath, 'receipt', WORKER_UID);
    });

    it('worker2 (не автор) удаляет чужой неоплаченный чек → deny 403', async () => {
      await deniedWith(checkDeletePermission(cfg, unpaidReceiptPath, 'receipt', WORKER2_UID), 403);
    });

    it('owner/manager удаляют любой НЕОПЛАЧЕННЫЙ чек проекта → allow', async () => {
      await checkDeletePermission(cfg, unpaidReceiptPath, 'receipt', OWNER_UID);
      await checkDeletePermission(cfg, unpaidReceiptPath, 'receipt', MGR_UID);
    });

    it('КЛЮЧЕВОЙ ТЕСТ: оплаченный чек не удаляет НИКТО — ни owner, ни manager, ни автор', async () => {
      await deniedWith(checkDeletePermission(cfg, paidReceiptPath, 'receipt', OWNER_UID), 403);
      await deniedWith(checkDeletePermission(cfg, paidReceiptPath, 'receipt', MGR_UID), 403);
      await deniedWith(checkDeletePermission(cfg, paidReceiptPath, 'receipt', WORKER_UID), 403);
    });

    it('client не удаляет чек ни в каком состоянии', async () => {
      await deniedWith(checkDeletePermission(cfg, unpaidReceiptPath, 'receipt', CLIENT_UID), 403);
      await deniedWith(checkDeletePermission(cfg, paidReceiptPath, 'receipt', CLIENT_UID), 403);
    });

    it("kind='photo' (прогресс-фото) — удаляет только canManageProject, автор-подрядчик не может", async () => {
      await checkDeletePermission(cfg, progressPhotoPath, 'photo', OWNER_UID);
      await deniedWith(checkDeletePermission(cfg, progressPhotoPath, 'photo', WORKER_UID), 403);
    });

    it('удаление файлов чата не поддерживается этим эндпоинтом', async () => {
      await deniedWith(checkDeletePermission(cfg, chatPath, 'photo', OWNER_UID), 400);
    });
  });
});
