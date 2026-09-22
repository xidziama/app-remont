'use strict';

const { readConfig } = require('./src/env');
const { requireUid } = require('./src/auth');
const { HttpError } = require('./src/httpErrors');
const { handlePutUrl } = require('./src/endpoints/putUrl');
const { handleGetUrls } = require('./src/endpoints/getUrls');
const { handleDelete } = require('./src/endpoints/deleteObject');

const ROUTES = {
  '/put-url': { method: 'POST', run: handlePutUrl },
  '/get-urls': { method: 'POST', run: handleGetUrls },
  '/delete': { method: 'POST', run: handleDelete },
};

/**
 * Достаёт путь запроса независимо от того, как именно API Gateway передаёт
 * его в событие (наблюдались варианты event.path и вложенный
 * requestContext.http.path в разных интеграциях Yandex Cloud Functions).
 * Всегда возвращает путь БЕЗ префикса stage/базового пути шлюза — сравнение
 * ниже идёт по последнему сегменту вида "/put-url".
 */
function resolveRoutePath(event) {
  const raw =
    (event && event.path) ||
    (event && event.requestContext && event.requestContext.http && event.requestContext.http.path) ||
    (event && event.url) ||
    '';
  const match = /\/(put-url|get-urls|delete)\/?$/.exec(String(raw));
  return match ? `/${match[1]}` : null;
}

function isTruthyFlag(value) {
  return value === true || value === 'true' || value === 1 || value === '1';
}

function tryParseJsonObject(raw) {
  try {
    const parsed = JSON.parse(raw);
    const isPlainObject = parsed !== null && typeof parsed === 'object' && !Array.isArray(parsed);
    return isPlainObject ? { ok: true, value: parsed } : { ok: false };
  } catch (_err) {
    return { ok: false };
  }
}

/**
 * Разбирает event.body в JSON-объект.
 *
 * API Gateway перед Cloud Function и прямой вызов функции (как в
 * smoke-тесте) кодируют body по-разному: прямой вызов отдаёт обычный текст,
 * а через шлюз тело нередко приходит в base64 с флагом
 * event.isBase64Encoded. На практике этот флаг у Yandex API Gateway не
 * всегда надёжен (зависит от конфигурации интеграции и типа контента) —
 * поэтому мы НЕ доверяем ему слепо: сначала пробуем декодирование, которое
 * он подсказывает, и, если результат не парсится как JSON-объект, пробуем
 * противоположную трактовку, прежде чем окончательно вернуть 400. Это
 * работает одинаково для обоих реальных путей вызова, независимо от того,
 * прислал ли Yandex флаг корректно.
 */
function parseBody(event) {
  if (event == null || event.body == null || event.body === '') return {};

  const raw = String(event.body);
  const decodedFromBase64 = Buffer.from(raw, 'base64').toString('utf8');
  const candidates = isTruthyFlag(event.isBase64Encoded)
    ? [decodedFromBase64, raw]
    : [raw, decodedFromBase64];

  for (const candidate of candidates) {
    const result = tryParseJsonObject(candidate);
    if (result.ok) return result.value;
  }

  throw new HttpError(400, 'invalid_argument', 'Тело запроса должно быть корректным JSON.');
}

function jsonResponse(statusCode, payload) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
    body: JSON.stringify(payload),
  };
}

async function handler(event, _context) {
  const cfg = readConfig();
  const routeKey = resolveRoutePath(event);
  const route = routeKey ? ROUTES[routeKey] : null;

  if (!route) {
    return jsonResponse(404, { error: 'not_found', message: 'Неизвестный маршрут.' });
  }

  const method = (event && event.httpMethod) || 'POST';
  if (method !== route.method) {
    return jsonResponse(405, { error: 'method_not_allowed', message: `Ожидался ${route.method}.` });
  }

  let uid = null;
  try {
    uid = await requireUid(event, cfg);
    const body = parseBody(event);
    const result = await route.run(body, uid, cfg);
    return jsonResponse(200, result);
  } catch (err) {
    if (err instanceof HttpError) {
      if (err.statusCode >= 500) {
        console.error(JSON.stringify({ route: routeKey, uid, code: err.code, statusCode: err.statusCode }));
      }
      return jsonResponse(err.statusCode, { error: err.code, message: err.message });
    }

    // Непредвиденная ошибка: сообщение наружу не отдаём (могло бы содержать
    // детали инфраструктуры), только код маршрута и факт ошибки в лог.
    console.error(JSON.stringify({ route: routeKey, uid, code: 'internal', message: String(err && err.message) }));
    return jsonResponse(500, { error: 'internal', message: 'Внутренняя ошибка сервера.' });
  }
}

module.exports = { handler, parseBody };
