'use strict';

const { parseStoragePath } = require('../storagePaths');
const { canManageProject, getExpenseData } = require('../permissions');
const { deleteObject } = require('../s3');
const { HttpError } = require('../httpErrors');

/**
 * D5 + авторство. Источник истины по isPaid и по автору — Firestore-документ
 * projects/{projectId}/expenses/{expenseId}, НЕ x-amz-meta-uploader из S3.
 *
 * Почему так, а не HeadObject-метаданные (задача явно предлагала оба
 * варианта на выбор):
 *  - expenses/{id}.createdBy — то самое поле, которое уже проверяет
 *    isOwnExpense() в firestore.rules; переиспользуя его, backend не заводит
 *    параллельный источник истины об авторстве.
 *  - Один Firestore-запрос даёт СРАЗУ и isPaid, и createdBy — вместо
 *    HeadObject (S3) + отдельного чтения Firestore для isPaid.
 *  - x-amz-meta-uploader не будет существовать на объектах, загруженных до
 *    этой миграции (старые файлы без метаданных) — тогда HeadObject-путь
 *    для них не сработал бы вообще, а Firestore-документ есть всегда.
 *
 * D1 делает id объекта равным id документа expenses/{id}, поэтому для
 * ЧЕКА (kind === 'receipt') можно взять expenseId прямо из последнего
 * сегмента storagePath — без этапа (objectReceipt) и с этапом (stagePhoto)
 * одинаково, потому что зеркало в stages/{s}/photos/{id} использует тот же id.
 */
async function getReceiptAuthInfo(cfg, projectId, expenseId) {
  const expense = await getExpenseData(cfg, projectId, expenseId);
  if (!expense) return { found: false };
  return { found: true, isPaid: expense.isPaid === true, createdBy: expense.createdBy };
}

async function checkDeletePermission(cfg, parsed, kind, uid) {
  if (parsed.pathKind === 'chat') {
    // Удаление фото чата этой функцией не поддерживается — в приложении
    // сейчас вообще нет удаления сообщений чата (project_repository.dart не
    // содержит такого метода). Осиротевшие файлы чата — известный техдолг,
    // которым займётся отдельная функция-чистильщик (см. Приложение_контекст.md).
    throw new HttpError(400, 'invalid_argument', 'Удаление файлов чата не поддерживается этим эндпоинтом.');
  }

  if (kind === 'photo') {
    // Мирроор рулес: stages/{s}/photos/{id} delete = canManageProject, без
    // исключений для автора — даже подрядчик, загрузивший прогресс-фото, не
    // может его удалить сам.
    if (parsed.pathKind !== 'stagePhoto') {
      throw new HttpError(400, 'invalid_argument', "kind='photo' допустим только для фото этапа.");
    }
    const allowed = await canManageProject(cfg, parsed.projectId, uid);
    if (!allowed) throw new HttpError(403, 'permission_denied', 'Недостаточно прав для удаления этого фото.');
    return;
  }

  // kind === 'receipt'
  const manage = await canManageProject(cfg, parsed.projectId, uid);
  const authInfo = await getReceiptAuthInfo(cfg, parsed.projectId, parsed.id);

  if (authInfo.found && authInfo.isPaid) {
    // D5: оплаченный чек заморожен для ВСЕХ, включая владельца/менеджера.
    throw new HttpError(403, 'permission_denied', 'Оплаченный чек нельзя удалить — он заморожен для всех ролей.');
  }

  if (manage) return;

  // Автор может удалить только СВОЙ и только если документ чека найден —
  // если expenses/{id} не существует (например, объект без сопоставленного
  // документа), правами для автора считать нельзя, разрешаем только canManage.
  if (authInfo.found && authInfo.createdBy === uid) return;

  throw new HttpError(403, 'permission_denied', 'Недостаточно прав для удаления этого чека.');
}

async function handleDelete(body, uid, cfg) {
  const storagePath = body && body.storagePath;
  const kind = body && body.kind;

  if (typeof storagePath !== 'string') {
    throw new HttpError(400, 'invalid_argument', 'storagePath обязателен и должен быть строкой.');
  }
  if (kind !== 'photo' && kind !== 'receipt') {
    throw new HttpError(400, 'invalid_argument', "kind должен быть 'photo' или 'receipt'.");
  }

  const parsed = parseStoragePath(storagePath);
  if (!parsed) {
    throw new HttpError(400, 'invalid_argument', 'storagePath не соответствует ни одному ожидаемому формату.');
  }

  await checkDeletePermission(cfg, parsed, kind, uid);
  await deleteObject(cfg, storagePath);

  return { ok: true };
}

module.exports = { handleDelete, checkDeletePermission };
