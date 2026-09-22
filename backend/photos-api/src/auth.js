'use strict';

const { getAuthClient } = require('./firebase');
const { HttpError } = require('./httpErrors');

/** Достаёт "Bearer &lt;token&gt;" из заголовков запроса (регистронезависимо). */
function extractBearerToken(headers) {
  const raw = headers && (headers.authorization || headers.Authorization);
  if (typeof raw !== 'string') return null;
  const match = /^Bearer\s+(.+)$/i.exec(raw.trim());
  return match ? match[1].trim() : null;
}

/**
 * Проверяет Firebase ID token и возвращает uid вызывающего пользователя.
 * Бросает HttpError(401) на любую проблему — без деталей наружу (сообщения
 * verifyIdToken могут отличаться версия от версии и не должны утекать клиенту).
 */
async function requireUid(event, cfg) {
  const token = extractBearerToken(event && event.headers);
  if (!token) {
    throw new HttpError(401, 'unauthenticated', 'Missing Authorization: Bearer <Firebase ID token>.');
  }

  try {
    const decoded = await getAuthClient(cfg).verifyIdToken(token);
    return decoded.uid;
  } catch (_err) {
    throw new HttpError(401, 'unauthenticated', 'Invalid or expired ID token.');
  }
}

module.exports = { requireUid, extractBearerToken };
