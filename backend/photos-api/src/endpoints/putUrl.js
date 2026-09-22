'use strict';

const { parseStoragePath } = require('../storagePaths');
const { canManageProject, canReadProject, isProjectWorker, isAssignedStageWorker } = require('../permissions');
const { presignPutUrl, objectExists } = require('../s3');
const { HttpError } = require('../httpErrors');

/**
 * Проверка прав на ЗАПИСЬ по пути (см. firestore.rules, create-правила):
 *
 *  - stagePhoto (projects/{p}/stages/{s}/photos/{id}) — по пути нельзя
 *    отличить фото прогресса от фото-чека (оба используют один и тот же
 *    путь, разница только в поле `type` документа, которого на момент
 *    put-url ещё нет). Правила create для этих двух случаев РАЗНЫЕ:
 *      • create фото прогресса:  canManageProject || isAssignedStageWorker
 *      • create чека (expenses): canManageProject || (isProjectWorker && isAssignedStageWorker)
 *    Мы применяем БОЛЕЕ строгий (второй) вариант равномерно ко всем
 *    stagePhoto-путям — это подмножество первого, то есть никого лишнего не
 *    пускаем, но потенциально можем отказать назначенному на этап
 *    подрядчику, который почему-то не в workerIds проекта (в текущей модели
 *    приложения assignedUserIds всегда набирается из workerIds, поэтому
 *    на практике это не должно возникать). ОТКРЫТЫЙ ВОПРОС для Павла — см.
 *    Отчёт_photos-api.md.
 *
 *  - objectReceipt (projects/{p}/receipts/{id}) — только canManageProject:
 *    правило создания чека требует hasString(stageId), то есть подрядчик в
 *    принципе не может создать чек без этапа ("Иное") — это подтверждено и
 *    клиентским кодом (expenses_screen.dart блокирует выбор "Иное" для роли
 *    worker).
 *
 *  - chat (projects/{p}/chat/{id}) — canReadProject: любой участник объекта
 *    может отправить в чат сообщение с фото (правило messages/create не
 *    ограничивает роль, только canReadProject + senderId==uid, а senderId
 *    проверяет уже сам клиентский код записи в Firestore).
 */
async function checkWritePermission(cfg, parsed, uid) {
  if (parsed.pathKind === 'stagePhoto') {
    if (await canManageProject(cfg, parsed.projectId, uid)) return true;
    return (
      (await isProjectWorker(cfg, parsed.projectId, uid)) &&
      (await isAssignedStageWorker(cfg, parsed.projectId, parsed.stageId, uid))
    );
  }

  if (parsed.pathKind === 'objectReceipt') {
    return canManageProject(cfg, parsed.projectId, uid);
  }

  if (parsed.pathKind === 'chat') {
    return canReadProject(cfg, parsed.projectId, uid);
  }

  return false;
}

/**
 * D3: metadata-kind объекта. Для чека-без-этапа и для чата путь уже
 * однозначен. Для stagePhoto клиент может подсказать `kind` в теле запроса
 * (в приложении это известно: PhotoUploadSheet ветвится на _isReceipt ДО
 * вызова StorageService) — если не передан, по умолчанию 'photo'.
 */
function resolveMetaKind(parsed, requestedKind) {
  if (parsed.pathKind === 'objectReceipt') return 'receipt';
  if (parsed.pathKind === 'chat') return 'photo';
  return requestedKind === 'receipt' ? 'receipt' : 'photo';
}

async function handlePutUrl(body, uid, cfg) {
  const storagePath = body && body.storagePath;
  const requestedKind = body && body.kind;
  const contentType = (body && body.contentType) || 'image/jpeg';

  if (typeof storagePath !== 'string') {
    throw new HttpError(400, 'invalid_argument', 'storagePath обязателен и должен быть строкой.');
  }
  if (!cfg.allowedContentTypes.has(contentType)) {
    throw new HttpError(
      400,
      'invalid_argument',
      `contentType должен быть одним из: ${[...cfg.allowedContentTypes].join(', ')}.`,
    );
  }
  if (requestedKind !== undefined && requestedKind !== 'photo' && requestedKind !== 'receipt') {
    throw new HttpError(400, 'invalid_argument', "kind должен быть 'photo' или 'receipt', если указан.");
  }

  const parsed = parseStoragePath(storagePath);
  if (!parsed) {
    throw new HttpError(400, 'invalid_argument', 'storagePath не соответствует ни одному ожидаемому формату.');
  }

  const allowed = await checkWritePermission(cfg, parsed, uid);
  if (!allowed) {
    throw new HttpError(403, 'permission_denied', 'Недостаточно прав для загрузки по этому пути.');
  }

  // D4: защита от затирания уже существующего файла (чужого или того же id повторно).
  if (await objectExists(cfg, storagePath)) {
    throw new HttpError(409, 'already_exists', 'Файл с таким storagePath уже существует.');
  }

  const metaKind = resolveMetaKind(parsed, requestedKind);
  const signed = presignPutUrl(cfg, {
    key: storagePath,
    contentType,
    uploaderUid: uid,
    kind: metaKind,
    expiresInSeconds: cfg.putUrlTtlSeconds,
  });

  return {
    uploadUrl: signed.url,
    storagePath,
    headers: signed.headers,
    expiresAt: new Date(Date.now() + cfg.putUrlTtlSeconds * 1000).toISOString(),
  };
}

module.exports = { handlePutUrl, checkWritePermission, resolveMetaKind };
