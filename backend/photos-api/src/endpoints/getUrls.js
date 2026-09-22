'use strict';

const { parseStoragePath } = require('../storagePaths');
const { canReadProject } = require('../permissions');
const { presignGetUrl } = require('../s3');
const { HttpError } = require('../httpErrors');

/**
 * Пакетная выдача свежих GET-ссылок. Ровно одна проверка прав на путь —
 * canReadProject (аналог canReadProjectData()/canReadProject() из
 * firestore.rules, той же функции, что governs чтение projects/stages/
 * expenses/photos/messages). Она общая для всех трёх форматов пути
 * (stagePhoto/objectReceipt/chat), потому что чтение в firestore.rules не
 * различает их — оно всегда сводится к "виден ли проект целиком".
 *
 * Недоступные и некорректные (не прошедшие parseStoragePath) пути молча не
 * попадают в ответ — не 400 и не отдельная пометка, чтобы не подсказывать
 * атакующему, какие из его путей "почти правильные".
 */
async function handleGetUrls(body, uid, cfg) {
  const storagePaths = body && body.storagePaths;

  if (!Array.isArray(storagePaths) || storagePaths.length === 0) {
    throw new HttpError(400, 'invalid_argument', 'storagePaths должен быть непустым массивом строк.');
  }
  if (storagePaths.length > cfg.maxGetUrlsBatch) {
    throw new HttpError(
      400,
      'invalid_argument',
      `storagePaths: не более ${cfg.maxGetUrlsBatch} путей за один запрос.`,
    );
  }

  const urls = {};

  // Сначала уникальные пути (клиент может случайно прислать дубли).
  const uniquePaths = [...new Set(storagePaths)];

  for (const path of uniquePaths) {
    const parsed = parseStoragePath(path);
    if (!parsed) continue;

    const allowed = await canReadProject(cfg, parsed.projectId, uid);
    if (!allowed) continue;

    urls[path] = presignGetUrl(cfg, path);
  }

  return { urls };
}

module.exports = { handleGetUrls };
