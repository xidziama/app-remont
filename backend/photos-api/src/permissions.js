'use strict';

// Повторяет логику firestore.rules (источник истины — файл firestore.rules в
// корне проекта) на Admin SDK. Any правка в firestore.rules должна быть
// отражена и здесь — иначе backend и клиентские правила разойдутся.
//
// Соответствие используемым в firestore.rules функциям:
//   canReadProjectData / canReadProject  -> canReadProject()
//   canManageProject                     -> canManageProject()
//   isProjectWorker                      -> isProjectWorker()
//   isAssignedStageWorker                -> isAssignedStageWorker()
//   isOwnExpense / isOwnReceiptMirror     -> getExpenseAuthInfo() (см. delete.js)

const { getFirestoreDb } = require('./firebase');

const ACTIVE_COMPANY_ROLES = new Set(['owner', 'manager', 'worker', 'client']);

// -----------------------------------------------------------------------
// Небольшой кэш в памяти инстанса функции. Существует только в пределах
// одного тёплого инстанса и одного набора запросов (например, одного
// пакетного get-urls на ~30 путей одного проекта) — не для правильности
// как таковой, а чтобы не читать один и тот же документ по 30 раз.
// D8: не дольше 30 секунд, поэтому долгоживущий инстанс всё равно скоро
// увидит отзыв прав.
// -----------------------------------------------------------------------
function createCache(ttlMs) {
  const store = new Map();
  return {
    async get(key, fetcher) {
      const now = Date.now();
      const hit = store.get(key);
      if (hit && hit.expiresAt > now) return hit.value;

      const value = await fetcher();
      store.set(key, { value, expiresAt: now + ttlMs });
      return value;
    },
  };
}

let cache = null;
function getCache(cfg) {
  if (!cache) cache = createCache(cfg.permissionCacheTtlMs);
  return cache;
}

// -----------------------------------------------------------------------
// Чтение документов (кэшированное)
// -----------------------------------------------------------------------

async function getProjectData(cfg, projectId) {
  return getCache(cfg).get(`project:${projectId}`, async () => {
    const snap = await getFirestoreDb(cfg).collection('projects').doc(projectId).get();
    return snap.exists ? snap.data() : null;
  });
}

async function getStageData(cfg, projectId, stageId) {
  return getCache(cfg).get(`stage:${projectId}:${stageId}`, async () => {
    const snap = await getFirestoreDb(cfg)
      .collection('projects')
      .doc(projectId)
      .collection('stages')
      .doc(stageId)
      .get();
    return snap.exists ? snap.data() : null;
  });
}

async function getCompanyMemberData(cfg, companyId, uid) {
  return getCache(cfg).get(`member:${companyId}:${uid}`, async () => {
    const snap = await getFirestoreDb(cfg)
      .collection('companies')
      .doc(companyId)
      .collection('members')
      .doc(uid)
      .get();
    return snap.exists ? snap.data() : null;
  });
}

/** Не кэшируется дольше запроса на удаление — читается один раз перед delete. */
async function getExpenseData(cfg, projectId, expenseId) {
  const snap = await getFirestoreDb(cfg)
    .collection('projects')
    .doc(projectId)
    .collection('expenses')
    .doc(expenseId)
    .get();
  return snap.exists ? snap.data() : null;
}

// -----------------------------------------------------------------------
// Хелперы-предикаты (аналоги одноимённых функций firestore.rules)
// -----------------------------------------------------------------------

function isStringArrayContains(value, uid) {
  return Array.isArray(value) && value.includes(uid);
}

function hasNonEmptyString(value) {
  return typeof value === 'string' && value.length > 0;
}

function isActiveCompanyMember(member) {
  return (
    !!member &&
    member.active === true &&
    typeof member.role === 'string' &&
    ACTIVE_COMPANY_ROLES.has(member.role)
  );
}

async function isCompanyOwner(cfg, companyId, uid) {
  const member = await getCompanyMemberData(cfg, companyId, uid);
  return isActiveCompanyMember(member) && member.role === 'owner';
}

async function isCompanyManager(cfg, companyId, uid) {
  const member = await getCompanyMemberData(cfg, companyId, uid);
  return isActiveCompanyMember(member) && member.role === 'manager';
}

/** Аналог canReadProjectData()/canReadProject() из firestore.rules. */
async function canReadProject(cfg, projectId, uid) {
  const project = await getProjectData(cfg, projectId);
  if (!project) return false;

  if (project.ownerId === uid) return true;
  if (isStringArrayContains(project.participantIds, uid)) return true;
  if (isStringArrayContains(project.workerIds, uid)) return true;
  if (isStringArrayContains(project.clientIds, uid)) return true;

  const companyId = project.companyId;
  if (hasNonEmptyString(companyId)) {
    if (await isCompanyOwner(cfg, companyId, uid)) return true;
    if (
      (await isCompanyManager(cfg, companyId, uid)) &&
      isStringArrayContains(project.managerIds, uid)
    ) {
      return true;
    }
  }

  return false;
}

/** Аналог canManageProject() из firestore.rules. */
async function canManageProject(cfg, projectId, uid) {
  const project = await getProjectData(cfg, projectId);
  if (!project || !hasNonEmptyString(project.companyId)) return false;

  const companyId = project.companyId;
  if (await isCompanyOwner(cfg, companyId, uid)) return true;
  if (
    (await isCompanyManager(cfg, companyId, uid)) &&
    isStringArrayContains(project.managerIds, uid)
  ) {
    return true;
  }
  return false;
}

/** Аналог isProjectWorker() из firestore.rules. */
async function isProjectWorker(cfg, projectId, uid) {
  const project = await getProjectData(cfg, projectId);
  return !!project && isStringArrayContains(project.workerIds, uid);
}

/** Аналог isAssignedStageWorker() из firestore.rules. */
async function isAssignedStageWorker(cfg, projectId, stageId, uid) {
  const stage = await getStageData(cfg, projectId, stageId);
  return !!stage && isStringArrayContains(stage.assignedUserIds, uid);
}

async function projectExists(cfg, projectId) {
  return (await getProjectData(cfg, projectId)) !== null;
}

module.exports = {
  canReadProject,
  canManageProject,
  isProjectWorker,
  isAssignedStageWorker,
  projectExists,
  getExpenseData,
  getProjectData,
};
