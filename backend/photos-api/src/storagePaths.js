'use strict';

// Разбор и валидация storagePath. Backend никогда не доверяет присланному пути
// вслепую: путь либо совпадает с одним из трёх известных форматов (которые
// использует StorageService в приложении), либо запрос отклоняется.
//
// Форматы (совпадают с lib/services/storage_service.dart):
//   projects/{projectId}/stages/{stageId}/photos/{id}.{ext}   — фото/чек этапа
//   projects/{projectId}/receipts/{id}.{ext}                  — чек без этапа ("Иное")
//   projects/{projectId}/chat/{id}.{ext}                      — фото в чате
//
// {id} для чека (с этапом или без) — это id документа Firestore
// (expenses/{id}), а не случайный uuid. Для фото этапа и фото чата — тоже id
// соответствующего документа Firestore. Все они уже проходят через regex
// идентификатора, так что старые записи со случайным uuid тоже валидны.

const ID_RE = '[A-Za-z0-9_-]{1,64}';
const EXT_RE = '(?:jpg|jpeg|png|webp)';

const STAGE_PATH_RE = new RegExp(
  `^projects/(${ID_RE})/stages/(${ID_RE})/photos/(${ID_RE})\\.${EXT_RE}$`,
);
const OBJECT_RECEIPT_RE = new RegExp(`^projects/(${ID_RE})/receipts/(${ID_RE})\\.${EXT_RE}$`);
const CHAT_RE = new RegExp(`^projects/(${ID_RE})/chat/(${ID_RE})\\.${EXT_RE}$`);

/**
 * @typedef {Object} ParsedPath
 * @property {'stagePhoto'|'objectReceipt'|'chat'} pathKind — структурная
 *   категория пути. Для 'stagePhoto' в самом пути НЕЛЬЗЯ отличить обычное
 *   фото прогресса от фото-чека — оба живут по одному и тому же пути
 *   projects/{p}/stages/{s}/photos/{id}, разница только в поле `type`
 *   документа Firestore, которого на момент put-url ещё не существует.
 * @property {string} projectId
 * @property {string} [stageId]
 * @property {string} id
 */

/** @returns {ParsedPath | null} */
function parseStoragePath(path) {
  if (typeof path !== 'string' || path.length === 0 || path.length > 300) {
    return null;
  }

  let match = STAGE_PATH_RE.exec(path);
  if (match) {
    return { pathKind: 'stagePhoto', projectId: match[1], stageId: match[2], id: match[3] };
  }

  match = OBJECT_RECEIPT_RE.exec(path);
  if (match) {
    return { pathKind: 'objectReceipt', projectId: match[1], id: match[2] };
  }

  match = CHAT_RE.exec(path);
  if (match) {
    return { pathKind: 'chat', projectId: match[1], id: match[2] };
  }

  return null;
}

module.exports = { parseStoragePath };
