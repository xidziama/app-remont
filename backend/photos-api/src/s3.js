'use strict';

const https = require('https');
const aws4 = require('aws4');
const { HttpError } = require('./httpErrors');

function credentials(cfg) {
  return { accessKeyId: cfg.s3AccessKey, secretAccessKey: cfg.s3SecretKey };
}

function assertCredentialsConfigured(cfg) {
  if (!cfg.s3AccessKey || !cfg.s3SecretKey) {
    throw new Error(
      'S3_ACCESS_KEY/S3_SECRET_KEY не заданы. Это секреты из Lockbox ' +
        '(photos-backend-secrets), они должны быть подключены к функции.',
    );
  }
}

function objectPath(cfg, key) {
  return `/${cfg.bucket}/${key}`;
}

/** Подписанный URL для PUT с обязательными заголовками (D3). */
function presignPutUrl(cfg, { key, contentType, uploaderUid, kind, expiresInSeconds }) {
  assertCredentialsConfigured(cfg);

  const opts = {
    host: cfg.endpoint,
    method: 'PUT',
    service: 's3',
    region: cfg.region,
    path: `${objectPath(cfg, key)}?X-Amz-Expires=${expiresInSeconds}`,
    signQuery: true,
    headers: {
      'content-type': contentType,
      'x-amz-meta-uploader': uploaderUid,
      'x-amz-meta-kind': kind,
    },
  };
  aws4.sign(opts, credentials(cfg));

  return {
    url: `https://${opts.host}${opts.path}`,
    // Клиент обязан отправить PUT ровно с этими заголовками — они входят в
    // подпись (X-Amz-SignedHeaders), другое значение даст SignatureDoesNotMatch.
    headers: {
      'content-type': contentType,
      'x-amz-meta-uploader': uploaderUid,
      'x-amz-meta-kind': kind,
    },
  };
}

/** Подписанный URL для GET (D8: TTL из cfg.getUrlTtlSeconds). */
function presignGetUrl(cfg, key) {
  assertCredentialsConfigured(cfg);

  const opts = {
    host: cfg.endpoint,
    method: 'GET',
    service: 's3',
    region: cfg.region,
    path: `${objectPath(cfg, key)}?X-Amz-Expires=${cfg.getUrlTtlSeconds}`,
    signQuery: true,
  };
  aws4.sign(opts, credentials(cfg));

  return `https://${opts.host}${opts.path}`;
}

function request(cfg, { method, key, timeoutMs = 10000 }) {
  const opts = {
    host: cfg.endpoint,
    method,
    service: 's3',
    region: cfg.region,
    path: objectPath(cfg, key),
  };
  aws4.sign(opts, credentials(cfg));

  return new Promise((resolve, reject) => {
    const req = https.request(
      { method, host: opts.host, path: opts.path, headers: opts.headers, timeout: timeoutMs },
      (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () =>
          resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString('utf8') }),
        );
      },
    );
    req.on('timeout', () => req.destroy(new Error(`S3 ${method} ${key}: нет ответа за ${timeoutMs} мс`)));
    req.on('error', reject);
    req.end();
  });
}

/** true — объект существует (200), false — не найден (404). */
async function objectExists(cfg, key) {
  assertCredentialsConfigured(cfg);
  const res = await request(cfg, { method: 'HEAD', key });
  if (res.status === 404) return false;
  if (res.status >= 200 && res.status < 300) return true;
  throw new HttpError(502, 'storage_error', `S3 HEAD вернул неожиданный статус ${res.status}.`);
}

/** Идемпотентно: отсутствующий объект (404) считается успехом. */
async function deleteObject(cfg, key) {
  assertCredentialsConfigured(cfg);
  const res = await request(cfg, { method: 'DELETE', key });
  const ok = (res.status >= 200 && res.status < 300) || res.status === 404;
  if (!ok) {
    throw new HttpError(502, 'storage_error', `S3 DELETE вернул неожиданный статус ${res.status}.`);
  }
}

module.exports = { presignPutUrl, presignGetUrl, objectExists, deleteObject };
