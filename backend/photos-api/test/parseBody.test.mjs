/**
 * Тесты разбора event.body — без Firestore/Auth эмулятора (чистая функция).
 *
 * Причина появления: прямой вызов функции (smoke-тест из консоли) отдаёт
 * body обычным текстом, а реальный вызов через API Gateway — в base64
 * (event.isBase64Encoded). На практике этот флаг у Yandex API Gateway не
 * всегда надёжен, поэтому parseBody не должен ему слепо доверять — тесты
 * ниже фиксируют это поведение для обоих путей вызова и для случая, когда
 * флаг вообще не совпадает с реальным кодированием тела.
 */

import assert from 'node:assert';
import { parseBody } from '../index.js';

function b64(obj) {
  return Buffer.from(JSON.stringify(obj), 'utf8').toString('base64');
}

describe('parseBody', () => {
  it('пустое/отсутствующее тело -> {}', () => {
    assert.deepStrictEqual(parseBody({}), {});
    assert.deepStrictEqual(parseBody({ body: null }), {});
    assert.deepStrictEqual(parseBody({ body: '' }), {});
  });

  it('прямой вызов функции: обычный JSON-текст, isBase64Encoded не задан', () => {
    const event = { body: JSON.stringify({ storagePath: 'projects/p1/chat/m1.jpg' }) };
    assert.deepStrictEqual(parseBody(event), { storagePath: 'projects/p1/chat/m1.jpg' });
  });

  it('через API Gateway: base64 + isBase64Encoded === true (boolean)', () => {
    const payload = { storagePaths: ['projects/p1/chat/m1.jpg'] };
    const event = { body: b64(payload), isBase64Encoded: true };
    assert.deepStrictEqual(parseBody(event), payload);
  });

  it('через API Gateway: base64 + isBase64Encoded как строка "true"', () => {
    const payload = { kind: 'receipt' };
    const event = { body: b64(payload), isBase64Encoded: 'true' };
    assert.deepStrictEqual(parseBody(event), payload);
  });

  it('КЛЮЧЕВОЙ ТЕСТ: тело в base64, но isBase64Encoded ложно false/не задан (наблюдалось на реальном шлюзе)', () => {
    const payload = { storagePath: 'projects/p1/receipts/r1.jpg', contentType: 'image/jpeg' };
    const event = { body: b64(payload), isBase64Encoded: false };
    assert.deepStrictEqual(parseBody(event), payload);

    const eventNoFlag = { body: b64(payload) };
    assert.deepStrictEqual(parseBody(eventNoFlag), payload);
  });

  it('обычный текстовый JSON, но isBase64Encoded ошибочно true', () => {
    const payload = { storagePath: 'projects/p1/chat/m2.jpg' };
    const event = { body: JSON.stringify(payload), isBase64Encoded: true };
    assert.deepStrictEqual(parseBody(event), payload);
  });

  it('действительно некорректное тело -> HttpError 400 (ни одна трактовка не даёт JSON-объект)', () => {
    assert.throws(
      () => parseBody({ body: 'это не json и не осмысленный base64-json' }),
      (err) => err.statusCode === 400 && err.code === 'invalid_argument',
    );
  });

  it('JSON-массив или примитив на верхнем уровне отклоняется (нужен объект)', () => {
    assert.throws(
      () => parseBody({ body: JSON.stringify([1, 2, 3]) }),
      (err) => err.statusCode === 400,
    );
    assert.throws(
      () => parseBody({ body: JSON.stringify('строка') }),
      (err) => err.statusCode === 400,
    );
  });
});
